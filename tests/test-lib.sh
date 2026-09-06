#!/usr/bin/env bash
# tests/test-lib.sh — shared helpers for t-*.sh test files.
# Sourced by tests/run-tests.sh inside each test's isolated subshell.
# Keep this file dependency-free (bash builtins + coreutils only).

# ── assertions ──────────────────────────────────────────────────
# Each check prints PASS/FAIL to stdout; counts are derived by the runner
# from the log (lines match '^  PASS  ' / '^  FAIL  ' / '^  SKIP  ').

check_eq() { # check_eq <desc> <expected> <actual>
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  PASS  %s\n' "$desc"
    else
        printf '  FAIL  %s (expected=[%s] actual=[%s])\n' "$desc" "$expected" "$actual"
    fi
}

check_rc() { # check_rc <desc> <expected-rc> <actual-rc>
    local desc="$1"
    check_eq "$desc (rc)" "$2" "$3"
}

check_contains() { # check_contains <desc> <needle> <haystack>
    local desc="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) printf '  PASS  %s (contains: %s)\n' "$desc" "$needle" ;;
        *)           printf '  FAIL  %s (missing: [%s] in [%s])\n' "$desc" "$needle" "$haystack" ;;
    esac
}

check_not_contains() { # check_not_contains <desc> <needle> <haystack>
    local desc="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) printf '  FAIL  %s (unexpected: [%s] found in [%s])\n' "$desc" "$needle" "$haystack" ;;
        *)           printf '  PASS  %s (absent: %s)\n' "$desc" "$needle" ;;
    esac
}

check_file_exists() { # check_file_exists <desc> <path>
    if [ -e "$2" ]; then
        printf '  PASS  %s (exists: %s)\n' "$1" "$2"
    else
        printf '  FAIL  %s (missing file: %s)\n' "$1" "$2"
    fi
}

check_file_absent() { # check_file_absent <desc> <path>
    if [ -e "$2" ]; then
        printf '  FAIL  %s (unexpected file: %s)\n' "$1" "$2"
    else
        printf '  PASS  %s (absent: %s)\n' "$1" "$2"
    fi
}

count_occurrences() { # count_occurrences <needle> <haystack> → echo count
    local needle="$1" haystack="$2" n=0 line
    while IFS= read -r line; do
        case "$line" in
            *"$needle"*) n=$((n + 1)) ;;
        esac
    done <<< "$haystack"
    printf '%s' "$n"
}

# ── execution helpers ───────────────────────────────────────────
# test_run <cmd...> — runs a command that may fail, captures combined output
# into $TR_OUT and exit code into $TR_RC. Never triggers set -e.
test_run() {
    set +e
    TR_OUT="$("$@" 2>&1)"
    TR_RC=$?
    set -e
}

# test_run_env <env-assignments...> -- <cmd...> — env overrides then run.
test_run_env() {
    local args=()
    while [ $# -gt 0 ]; do
        if [ "$1" = "--" ]; then
            shift
            break
        fi
        args+=("$1")
        shift
    done
    local envs=("${args[@]}")
    set +e
    TR_OUT="$(env "${envs[@]}" "$@" 2>&1)"
    TR_RC=$?
    set -e
}

# ── sandbox helpers ─────────────────────────────────────────────
# mksandbox <name> — fresh temp dir under $TEST_TMP; auto-cleaned by runner.
mksandbox() {
    local name="${1:-sandbox}"
    local d="$TEST_TMP/$name"
    mkdir -p "$d"
    printf '%s' "$d"
}

# write_env_file <path> <key=value>... — deterministic env-file fixture.
write_env_file() {
    local path="$1"; shift
    local line
    for line in "$@"; do
        printf '%s\n' "$line" >>"$path"
    done
}

# ── skip contract ───────────────────────────────────────────────
# skip_case <desc> <reason> — a case that cannot run in this environment.
skip_case() {
    printf '  SKIP  %s (%s)\n' "$1" "$2"
}

# require_cmd <binary> <desc> — SKIP + abort the current function (usage:
#   require_cmd jq "telegram auth" || return 0
require_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    skip_case "$2" "$1 not available"
    return 1
}

# ── repo helpers ────────────────────────────────────────────────
# repo_root — absolute path of the checkout under test.
repo_root() {
    printf '%s' "$ROOT"
}

# tool_path <name> — absolute path of a bin/pos-* tool.
tool_path() {
    printf '%s' "$ROOT/bin/$1"
}

# tracked_tree_copy <dest> — copy only git-tracked files (works on dirty
# trees; excludes .git and untracked files) using git ls-files + tar.
tracked_tree_copy() {
    local dest="$1"
    mkdir -p "$dest"
    (
        cd "$ROOT"
        git ls-files -z | tar --null -T - -cf - | (cd "$dest" && tar xf -)
    )
}

# counts a token in a multiline string
count_token() { # count_token <token> <multiline-string> → echo N
    local token="$1" haystack="$2" n=0 line
    while IFS= read -r line; do
        case "$line" in
            *"$token"*) n=$((n + 1)) ;;
        esac
    done <<< "$haystack"
    printf '%s' "$n"
}