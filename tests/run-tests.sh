#!/usr/bin/env bash
set -euo pipefail
# tests/run-tests.sh — zero-dependency Bash regression runner.
#
# Discovers tests/t-*.sh, runs each in an isolated subshell (temp sandbox per
# test, cleaned up automatically), collects PASS/FAIL/SKIP, prints a summary
# table, and exits non-zero when any check failed.
#
# Usage: tests/run-tests.sh [test-file ...]
#   No args        → run every tests/t-*.sh (sorted)
#   With args      → run only the named test files (path or bare name)
#
# Skip contract (hard): a test that cannot run in this environment MUST call
# skip_case "<desc>" "<reason>" — it prints `[SKIP] reason`, is counted in the
# summary, and never counts as PASS. A test file whose run_test() produced
# zero checks and zero skips is reported as FAIL ("no assertions") so a broken
# harness can never silently pass. Tests must never lie.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)"

PASS=0; FAIL=0; SKIP=0
files_total=0; files_pass=0; files_fail=0; files_skip=0
declare -a FAILED_FILES=()
START_TS="$(date +%s)"

# ── per-test state set by the runner before sourcing a test file ──
TEST_NAME=""
TEST_TMP=""
TEST_TRAP_SET=0

cleanup_test_tmp() {
    if [ -n "${TEST_TMP:-}" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
    TEST_TMP=""
}

# Run one test file in a subshell; stdout/stderr go to the per-test log.
# Returns 0 = no FAIL lines, 1 = FAIL, 2 = SKIP-only.
run_one() {
    local test_file="$1"
    local log="$TEST_TMP/$TEST_NAME.log"
    local rc=0

    # Run in a subshell; the exit status must be captured via `if` because a
    # plain `( ... ); rc=$?` would let the subshell's failure trigger errexit
    # in the parent (set -e applies to subshells as ordinary commands).
    local rc=0
    if (
        # Isolated sandbox for this test.
        TEST_NAME="$(basename "$test_file")"
        TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pos-test-${TEST_NAME}.XXXXXX")"
        export TEST_NAME TEST_TMP
        trap cleanup_test_tmp EXIT

        # Shared helpers + strict mode (the runner already has -euo pipefail;
        # re-assert it in the subshell for belt-and-braces).
        set -euo pipefail
        source "$TEST_DIR/test-lib.sh"
        source "$test_file"
        run_test
    ) >"$log" 2>&1; then
        rc=0
    else
        rc=$?
    fi

    local f_p=0 f_f=0 f_s=0
    f_p="$(grep -c '^  PASS  ' "$log" 2>/dev/null || true)"
    f_f="$(grep -c '^  FAIL  ' "$log" 2>/dev/null || true)"
    f_s="$(grep -c '^  SKIP  ' "$log" 2>/dev/null || true)"
    PASS=$((PASS + f_p)); FAIL=$((FAIL + f_f)); SKIP=$((SKIP + f_s))
    files_total=$((files_total + 1))

    # A test that aborted (rc != 0) WITHOUT a checked FAIL is still a FAIL —
    # set -e / errexit killed it mid-run.
    if [ "$rc" -ne 0 ] && [ "$f_f" -eq 0 ]; then
        f_f=1
        FAIL=$((FAIL + 1))
        printf '\n  FAIL  test aborted (exit %s) before a check failed — see log below\n' "$rc" >>"$log"
    fi

    if [ "$f_f" -gt 0 ]; then
        files_fail=$((files_fail + 1))
        FAILED_FILES+=("$test_file")
        printf '  FAIL  %s (%s checks, %s failed, %s skipped)\n' "$TEST_NAME" "$f_p" "$f_f" "$f_s"
    elif [ "$f_p" -gt 0 ]; then
        files_pass=$((files_pass + 1))
        if [ "$f_s" -gt 0 ]; then
            printf '  PASS  %s (%s checks, %s skipped)\n' "$TEST_NAME" "$f_p" "$f_s"
        else
            printf '  PASS  %s (%s checks)\n' "$TEST_NAME" "$f_p"
        fi
    elif [ "$f_s" -gt 0 ]; then
        files_skip=$((files_skip + 1))
        local reasons
        reasons="$(grep '^  SKIP  ' "$log" 2>/dev/null | sed 's/^  SKIP  //' | tr '\n' '; ' )"
        printf '  SKIP  %s (%s reasons: %s)\n' "$TEST_NAME" "$f_s" "${reasons:-none}"
    else
        files_fail=$((files_fail + 1))
        FAILED_FILES+=("$test_file")
        printf '  FAIL  %s (no assertions run — harness broken)\n' "$TEST_NAME"
    fi
}

main() {
    local tests=() f
    if [ $# -gt 0 ]; then
        for f in "$@"; do
            case "$f" in
                */*) tests+=("$f") ;;
                *)
                    if [ -f "$TEST_DIR/$f.sh" ]; then
                        tests+=("$TEST_DIR/$f.sh")
                    elif [ -f "$TEST_DIR/$f" ]; then
                        tests+=("$TEST_DIR/$f")
                    else
                        echo "No such test: $f" >&2
                        exit 2
                    fi
                    ;;
            esac
        done
    else
        # Deterministic order: sorted by name.
        while IFS= read -r f; do
            tests+=("$f")
        done < <(find "$TEST_DIR" -maxdepth 1 -name 't-*.sh' -type f | sort)
    fi

    [ "${#tests[@]}" -gt 0 ] || { echo "No test files found in $TEST_DIR" >&2; exit 1; }

    echo "Running ${#tests[@]} test file(s) — strict mode: no network, no sudo, no system changes."
    echo

    local one
    for one in "${tests[@]}"; do
        TEST_NAME="$(basename "$one")"
        TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pos-run.XXXXXX")"
        run_one "$one"
        # keep the per-test sandbox only on FAILURE for debugging
        if [ -f "$TEST_TMP/$TEST_NAME.log" ]; then
            if [ "$(grep -c '^  FAIL  ' "$TEST_TMP/$TEST_NAME.log" 2>/dev/null || true)" -gt 0 ]; then
                echo "─── $TEST_NAME log ───"
                sed 's/^/    /' "$TEST_TMP/$TEST_NAME.log"
                echo "──────────────────────"
            fi
            rm -f "$TEST_TMP/$TEST_NAME.log"
        fi
        rm -rf "$TEST_TMP"
    done
    TEST_TMP=""

    local elapsed=$(( $(date +%s) - START_TS ))
    echo
    echo "──────────────────────────────────────────────"
    echo "Summary: files ${files_pass} pass / ${files_fail} fail / ${files_skip} skip (of ${files_total})"
    echo "Checks : ${PASS} pass / ${FAIL} fail / ${SKIP} skip"
    echo "Runtime: ${elapsed}s"
    if [ "${#FAILED_FILES[@]}" -gt 0 ]; then
        printf 'Failed : %s\n' "${FAILED_FILES[*]}"
    fi
    [ "$FAIL" -eq 0 ] && [ "$files_fail" -eq 0 ]
}

main "$@"