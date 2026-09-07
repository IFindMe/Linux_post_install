#!/usr/bin/env bash
set -euo pipefail
# t-menu-allow-empty.sh — regression for the alias-menu fix (2026-09-06):
#   Part A: menu_ask_value --allow-empty semantics matrix against the REAL
#           lib/menu-lib.sh via the non-TTY stdin path (the same deterministic
#           route as the Detective's repro — no TTY, no raw-mode reader).
#           Default contract (empty + no default → rc 1) must be unchanged;
#           the flag must flip ONLY the empty+no-default cell (rc 0 + empty);
#           genuine EOF/cancel must remain rc 1 even with the flag.
#   Part B: static guards on bin/pos-ai-alias — create-flow steps 1..5 must all
#           be labeled /5 (FAILS if anyone regresses /4 back), exactly the 2
#           approved --allow-empty call sites must exist (both in _alias_create),
#           the edit flow must stay untouched at 4 × /4, and no OTHER tool may
#           have adopted the flag (scope fence).
#
# Strategy: production logic is never re-typed. menu_ask_value is sourced from
# lib/menu-lib.sh; function bodies are brace-extracted from bin/pos-ai-alias
# with the same extract_fn pattern as t-ai-server-validate.sh.

# extract_fn <source-file> <fnname> — print one brace-delimited function body.
extract_fn() {
    local file="$1" fn="$2"
    awk -v fn="$fn" '
        BEGIN { found=0; depth=0 }
        {
            if (!found && $0 ~ ("^" fn "\\(\\)")) { found=1; depth=0 }
            if (found) {
                n_open  = gsub(/\{/, "{")
                n_close = gsub(/\}/, "}")
                depth = depth + n_open - n_close
                print
                if (depth <= 0) exit
            }
        }
    ' "$file"
}

# ask_case <desc> <feed(printf %b bytes)> <expect_rc> <expect_out> <args...>
# Feeds literal bytes to the REAL menu_ask_value and asserts rc + stdout.
ask_case() {
    local desc="$1" feed="$2" expect_rc="$3" expect_out="$4"
    shift 4
    local out rc
    set +e
    out="$(printf '%b' "$feed" | menu_ask_value "$@" 2>/dev/null)"
    rc=$?
    set -e
    check_rc "$desc" "$expect_rc" "$rc"
    check_eq "$desc (value)" "$expect_out" "$out"
}

run_test() {
    local sandbox alias_tool
    sandbox="$(mksandbox menu-allow-empty)"
    alias_tool="$ROOT/bin/pos-ai-alias"

    source "$ROOT/lib/menu-lib.sh"

    # ═══ Part A0: reader contract the fix builds on (non-TTY fallback) ═══
    # menu_read_value must distinguish empty-Enter (rc 0 + empty) from EOF (rc 1);
    # otherwise --allow-empty could never tell cancel from empty.
    local rr_out rr_rc

    # empty line → rc 0, empty value
    set +e
    rr_out="$(printf '\n' | menu_read_value "probe" 2>/dev/null)"; rr_rc=$?
    set -e
    check_rc "reader: empty line → rc 0" 0 "$rr_rc"
    check_eq "reader: empty line → empty value" "" "$rr_out"

    # EOF → rc 1 (cancel)
    set +e
    rr_out="$(printf '' | menu_read_value "probe" 2>/dev/null)"; rr_rc=$?
    set -e
    check_rc "reader: EOF → rc 1 (cancel)" 1 "$rr_rc"

    # ═══ Part A: --allow-empty semantics matrix (Builder's 7 smoke cases) ═══

    # 1. empty line, no default, WITHOUT flag → rc 1 (default contract unchanged)
    ask_case "empty-no-default no flag → rc 1 (contract unchanged)" '\n' 1 "" "label" ""
    # 2. empty line, no default, WITH --allow-empty → rc 0 + empty value
    ask_case "empty-no-default with flag → rc 0 + empty" '\n' 0 "" "--allow-empty" "label" ""
    # 3. empty line, default present, WITH flag → rc 0 + default (default wins)
    ask_case "empty-with-default with flag → default wins" '\n' 0 "def" "--allow-empty" "label" "def"
    # 4. empty line, default present, no flag → rc 0 + default (regression)
    ask_case "empty-with-default no flag → default (regression)" '\n' 0 "def" "label" "def"
    # 5. non-empty line WITH flag → rc 0 + value
    ask_case "non-empty with flag → rc 0 + value" 'xyz\n' 0 "xyz" "--allow-empty" "label" ""
    # 6. non-empty line, no flag → rc 0 + value (regression)
    ask_case "non-empty no flag → rc 0 + value (regression)" 'xyz\n' 0 "xyz" "label" ""
    # 7. genuine EOF (no input at all) WITH flag → rc 1 (cancel stays cancel)
    ask_case "EOF with flag → rc 1 (cancel stays cancel)" '' 1 "" "--allow-empty" "label" ""
    # 8. genuine EOF, no flag → rc 1 (contract, flag independent)
    ask_case "EOF no flag → rc 1 (contract)" '' 1 "" "label" ""
    # 9. typed value beats default with flag (default only covers empty)
    ask_case "typed value beats default with flag" 'xyz\n' 0 "xyz" "--allow-empty" "label" "def"

    # ═══ Part B: static source guards (create-flow step labels + call sites) ═══
    local create_fn="$sandbox/alias-create-fn.sh"
    local edit_fn="$sandbox/alias-edit-fn.sh"
    extract_fn "$alias_tool" _alias_create > "$create_fn"
    extract_fn "$alias_tool" _alias_edit > "$edit_fn"

    # Create flow: exactly 5 numbered steps, all labeled /5 → FAILS if /4 returns.
    local nums totals
    nums="$(grep -oE 'step [0-9]' "$create_fn" | awk '{print $2}' | tr '\n' ' ')"
    totals="$(grep -oE 'step [0-9] [0-9]' "$create_fn" | awk '{print $3}' | tr '\n' ' ')"
    check_eq "create flow steps numbered 1..5" "1 2 3 4 5 " "$nums"
    check_eq "create flow step totals all /5" "5 5 5 5 5 " "$totals"
    check_eq "create flow has no /4 label" 0 "$(grep -cE 'step [0-9] 4' "$create_fn" || true)"

    # Exactly the 2 approved --allow-empty call sites, both inside _alias_create.
    check_eq "pos-ai-alias has exactly 2 --allow-empty call sites" 2 \
        "$(grep -c 'menu_ask_value --allow-empty' "$alias_tool" || true)"
    check_eq "both --allow-empty sites inside _alias_create" 2 \
        "$(grep -c 'menu_ask_value --allow-empty' "$create_fn" || true)"

    # Edit flow untouched: still 4 steps, all /4, none with the flag.
    check_eq "edit flow has 4 numbered steps" 4 \
        "$(grep -cE 'step [0-9] [0-9]' "$edit_fn" || true)"
    check_eq "edit flow all /4 (untouched)" 4 \
        "$(grep -cE 'step [0-9] 4' "$edit_fn" || true)"
    check_eq "no --allow-empty in edit flow" 0 \
        "$(grep -c 'menu_ask_value --allow-empty' "$edit_fn" || true)"

    # Scope fence: no OTHER pos tool adopted the flag.
    check_eq "no other tool adopted --allow-empty (scope fence)" 0 \
        "$(grep -l 'menu_ask_value --allow-empty' "$ROOT"/bin/pos-* 2>/dev/null | grep -vc 'pos-ai-alias$' || true)"
}