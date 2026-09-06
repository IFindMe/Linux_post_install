#!/usr/bin/env bash
set -euo pipefail
# t-gen-docs-drift.sh — generated-docs drift gate:
#   - `make gen` on a pristine tracked tree must be idempotent: running it
#     twice produces zero diff (CI's `git diff --exit-code` style check),
#   - the very first `make gen` on a baseline must succeed.
# Runs in a temp tracked-file copy (git ls-files) so the dirty working tree
# (parallel tracks) cannot influence the result.

run_test() {
    require_cmd git "gen-docs drift" || return 0
    require_cmd make "gen-docs drift" || return 0
    require_cmd timeout "gen-docs drift" || return 0

    local sandbox copy
    sandbox="$(mksandbox gen-docs-drift)"
    copy="$sandbox/tree"
    tracked_tree_copy "$copy" || { skip_case "gen-docs drift" "tracked tree copy failed"; return 0; }

    (
        cd "$copy"
        git init -q
        git config user.email test@example.invalid
        git config user.name "test"
        git add -A
        git commit -qm base

        timeout 120 make gen >"$sandbox/gen1.out" 2>&1
        local rc1=$?
        git add -A
        git commit -qm "after gen 1"

        timeout 120 make gen >"$sandbox/gen2.out" 2>&1
        local rc2=$?
        local dirty after2
        dirty="$(git status --porcelain)"
        git diff --exit-code >/dev/null 2>&1
        local diffrc=$?
        printf '%s %s\n' "$rc1" "$rc2" > "$sandbox/make-rcs"
        printf '%s\n' "$dirty" > "$sandbox/dirty"
        printf '%s\n' "$diffrc" > "$sandbox/diffrc"
    )
    local ok=no
    [ -f "$sandbox/make-rcs" ] && ok=yes
    if [ "$ok" = "no" ]; then
        printf '  SKIP  gen-docs drift (git/make unavailable in sandbox)\n'
        return 0
    fi

    local make_rcs dirty diffrc
    make_rcs="$(cat "$sandbox/make-rcs")"
    dirty="$(cat "$sandbox/dirty")"
    diffrc="$(cat "$sandbox/diffrc")"
    local rc1="${make_rcs%% *}" rc2="${make_rcs##* }"
    check_rc "first make gen succeeds" 0 "$rc1"
    check_rc "second make gen succeeds (idempotence run)" 0 "$rc2"
    check_eq "no dirty files after second gen" "" "$dirty"
    check_rc "git diff --exit-code clean after second gen" 0 "$diffrc"
}