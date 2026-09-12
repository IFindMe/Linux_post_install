#!/usr/bin/env bash
set -euo pipefail
# t-bank.sh — Command Bank feature: bank-lib.sh unit tests + pos system bank CLI
# integration tests.
#
# Storage contract: pipe-delimited name|description|command in $BANK_FILE.
# Parameter syntax: {param} placeholders in command templates.

run_test() {
    local sandbox helper
    sandbox="$(mksandbox bank)"
    helper="$sandbox/helper.sh"

    # ── Build a sourced helper that gives us bank-lib functions ──
    cat > "$helper" <<'HELPER'
source "$ROOT/tests/bank-test-helper.sh"
HELPER

    # ═══════════════════════════════════════════════════════════════
    # Part A: bank-lib.sh unit tests
    # ═══════════════════════════════════════════════════════════════

    # A1: bank_add + bank_load — add two entries, verify arrays
    (
        BANK_FILE="$sandbox/a1.bank.env"
        : > "$BANK_FILE"
        source "$helper"
        bank_add "deploy" "Deploy to prod" "ssh prod 'cd /app && git pull'"
        bank_add "backup" "Backup database" "pg_dump mydb | gzip > /tmp/db.sql.gz"
        bank_load
        # Check arrays
        [ "${#BANK_NAMES[@]}" -eq 2 ] || { echo "FAIL A1: expected 2 names, got ${#BANK_NAMES[@]}"; exit 1; }
        [ "${BANK_NAMES[0]}" = "deploy" ] || { echo "FAIL A1: name[0] mismatch"; exit 1; }
        [ "${BANK_DESCS[0]}" = "Deploy to prod" ] || { echo "FAIL A1: desc[0] mismatch"; exit 1; }
        [ "${BANK_CMDS[1]}" = "pg_dump mydb | gzip > /tmp/db.sql.gz" ] || { echo "FAIL A1: cmd[1] mismatch"; exit 1; }
        echo "PASS A1: bank_add + bank_load populates arrays correctly"
    ) && printf '  PASS  bank_add + bank_load populates arrays\n' \
      || printf '  FAIL  bank_add + bank_load populates arrays\n'

    # A2: bank_add duplicate — returns rc 1
    (
        BANK_FILE="$sandbox/a2.bank.env"
        printf 'old|Old cmd|echo old\n' > "$BANK_FILE"
        source "$helper"
        bank_add "old" "New desc" "echo new"
        exit $?
    )
    check_rc "bank_add duplicate returns rc 1" 1 $?

    # A3: bank_remove — remove entry, verify gone
    (
        BANK_FILE="$sandbox/a3.bank.env"
        printf 'aaa|desc a|cmd a\nbbb|desc b|cmd b\nccc|desc c|cmd c\n' > "$BANK_FILE"
        source "$helper"
        bank_remove "bbb"
        bank_load
        [ "${#BANK_NAMES[@]}" -eq 2 ] || { echo "FAIL A3: expected 2, got ${#BANK_NAMES[@]}"; exit 1; }
        [ "${BANK_NAMES[0]}" = "aaa" ] || { echo "FAIL A3: name[0] mismatch"; exit 1; }
        [ "${BANK_NAMES[1]}" = "ccc" ] || { echo "FAIL A3: name[1] mismatch"; exit 1; }
        # Verify file on disk
        grep -q '^bbb|' "$BANK_FILE" && { echo "FAIL A3: bbb still in file"; exit 1; }
        echo "PASS A3: bank_remove"
    ) && printf '  PASS  bank_remove removes entry\n' \
      || printf '  FAIL  bank_remove removes entry\n'

    # A4: bank_remove missing — returns rc 1
    (
        BANK_FILE="$sandbox/a4.bank.env"
        printf 'xxx|desc|cmd\n' > "$BANK_FILE"
        source "$helper"
        bank_remove "nonexistent"
        exit $?
    )
    check_rc "bank_remove missing returns rc 1" 1 $?

    # A5: bank_update — update entry, verify changed
    (
        BANK_FILE="$sandbox/a5.bank.env"
        printf 'mycmd|old desc|old cmd\n' > "$BANK_FILE"
        source "$helper"
        bank_update "mycmd" "new desc" "new cmd"
        bank_load
        [ "${BANK_DESCS[0]}" = "new desc" ] || { echo "FAIL A5: desc mismatch"; exit 1; }
        [ "${BANK_CMDS[0]}" = "new cmd" ] || { echo "FAIL A5: cmd mismatch"; exit 1; }
        # Verify on disk
        grep -q 'new desc|new cmd' "$BANK_FILE" || { echo "FAIL A5: not persisted"; exit 1; }
        echo "PASS A5: bank_update"
    ) && printf '  PASS  bank_update updates entry\n' \
      || printf '  FAIL  bank_update updates entry\n'

    # A6: bank_update missing — returns rc 1
    (
        BANK_FILE="$sandbox/a6.bank.env"
        printf 'exists|desc|cmd\n' > "$BANK_FILE"
        source "$helper"
        bank_update "nope" "desc" "cmd"
        exit $?
    )
    check_rc "bank_update missing returns rc 1" 1 $?

    # A7: bank_find — found sets BANK_IDX, not-found returns 1
    (
        BANK_FILE="$sandbox/a7.bank.env"
        printf 'alpha|d1|c1\nbeta|d2|c2\ngamma|d3|c3\n' > "$BANK_FILE"
        source "$helper"
        bank_find "beta"
        [ "${BANK_IDX:-}" = "1" ] || { echo "FAIL A7: expected BANK_IDX=1, got ${BANK_IDX:-unset}"; exit 1; }
        bank_find "nonexistent" && { echo "FAIL A7: should return 1 for missing"; exit 1; }
        echo "PASS A7: bank_find"
    ) && printf '  PASS  bank_find sets BANK_IDX / returns 1\n' \
      || printf '  FAIL  bank_find sets BANK_IDX / returns 1\n'

    # A8: bank_get — returns tab-separated output
    (
        BANK_FILE="$sandbox/a8.bank.env"
        printf 'mytool|My Tool|echo hello\n' > "$BANK_FILE"
        source "$helper"
        local out
        out="$(bank_get "mytool")"
        [ "$out" = "mytool	My Tool	echo hello" ] || { echo "FAIL A8: unexpected output [$out]"; exit 1; }
        echo "PASS A8: bank_get"
    ) && printf '  PASS  bank_get returns tab-separated output\n' \
      || printf '  FAIL  bank_get returns tab-separated output\n'

    # A9: bank_list_names — lists all names
    (
        BANK_FILE="$sandbox/a9.bank.env"
        printf 'one|x|y\ntwo|a|b\nthree|c|d\n' > "$BANK_FILE"
        source "$helper"
        local names
        names="$(bank_list_names)"
        local expected
        expected="$(printf 'one\ntwo\nthree')"
        [ "$names" = "$expected" ] || { echo "FAIL A9: expected [$expected] got [$names]"; exit 1; }
        echo "PASS A9: bank_list_names"
    ) && printf '  PASS  bank_list_names lists all names\n' \
      || printf '  FAIL  bank_list_names lists all names\n'

    # A10: bank_count — returns correct count
    (
        BANK_FILE="$sandbox/a10.bank.env"
        printf 'a|1|2\nb|3|4\nc|5|6\nd|7|8\n' > "$BANK_FILE"
        source "$helper"
        local cnt
        cnt="$(bank_count)"
        [ "$cnt" -eq 4 ] || { echo "FAIL A10: expected 4, got $cnt"; exit 1; }
        echo "PASS A10: bank_count"
    ) && printf '  PASS  bank_count returns correct count\n' \
      || printf '  FAIL  bank_count returns correct count\n'

    # A11: bank_count — empty file returns 0
    (
        BANK_FILE="$sandbox/a11.bank.env"
        : > "$BANK_FILE"
        source "$helper"
        local cnt
        cnt="$(bank_count)"
        [ "$cnt" -eq 0 ] || { echo "FAIL A11: expected 0, got $cnt"; exit 1; }
        echo "PASS A11: bank_count empty"
    ) && printf '  PASS  bank_count returns 0 for empty file\n' \
      || printf '  FAIL  bank_count returns 0 for empty file\n'

    # A12: bank_valid_name — valid names pass
    (
        source "$helper"
        local fail=0
        for n in "deploy" "my-cmd" "test_123" "A" "z9"; do
            bank_valid_name "$n" || { fail=1; printf 'FAIL A12: %s should be valid\n' "$n" >&2; }
        done
        [ "$fail" -eq 0 ] || exit 1
        echo "PASS A12: bank_valid_name accepts valid names"
    ) && printf '  PASS  bank_valid_name accepts valid names\n' \
      || printf '  FAIL  bank_valid_name accepts valid names\n'

    # A13: bank_valid_name — invalid names fail
    (
        source "$helper"
        local fail=0
        for n in "" "1abc" "-start" "_under" "has space" "special!"; do
            bank_valid_name "$n" && { fail=1; printf 'FAIL A13: %s should be invalid\n' "$n" >&2; }
        done
        [ "$fail" -eq 0 ] || exit 1
        echo "PASS A13: bank_valid_name rejects invalid names"
    ) && printf '  PASS  bank_valid_name rejects invalid names\n' \
      || printf '  FAIL  bank_valid_name rejects invalid names\n'

    # A14: _extract_params — extracts {param} names from template
    (
        source "$helper"
        local params
        params="$(_extract_params "echo {name} {path}")"
        local expected
        expected="$(printf 'name\npath')"
        [ "$params" = "$expected" ] || { echo "FAIL A14: expected [$expected] got [$params]"; exit 1; }
        echo "PASS A14: _extract_params"
    ) && printf '  PASS  _extract_params extracts param names\n' \
      || printf '  FAIL  _extract_params extracts param names\n'

    # A15: _extract_params — no params returns empty
    (
        source "$helper"
        local params
        params="$(_extract_params "echo hello world")"
        [ -z "$params" ] || { echo "FAIL A15: expected empty, got [$params]"; exit 1; }
        echo "PASS A15: _extract_params empty"
    ) && printf '  PASS  _extract_params returns empty for no params\n' \
      || printf '  FAIL  _extract_params returns empty for no params\n'

    # A16: _extract_params — deduplicates repeated params
    (
        source "$helper"
        local params
        params="$(_extract_params "cp {src} {dst} && ls {src}")"
        local count
        count="$(printf '%s' "$params" | grep -c '^src$' || true)"
        [ "$count" -eq 1 ] || { echo "FAIL A16: expected 1 occurrence of src, got $count"; exit 1; }
        echo "PASS A16: _extract_params deduplicates"
    ) && printf '  PASS  _extract_params deduplicates\n' \
      || printf '  FAIL  _extract_params deduplicates\n'

    # A17: _substitute_params — replaces {param} with quoted values
    (
        source "$helper"
        local result
        result="$(_substitute_params "scp {file} user@host:{dest}" "file=/tmp/data.csv" "dest=/var/data")"
        local expected='scp "/tmp/data.csv" user@host:"/var/data"'
        [ "$result" = "$expected" ] || { echo "FAIL A17: expected [$expected] got [$result]"; exit 1; }
        echo "PASS A17: _substitute_params"
    ) && printf '  PASS  _substitute_params replaces params\n' \
      || printf '  FAIL  _substitute_params replaces params\n'

    # A18: bank_load — comments and blank lines are skipped
    (
        BANK_FILE="$sandbox/a18.bank.env"
        cat > "$BANK_FILE" <<'BANK'
# Command Bank — managed by pos system bank (do not hand-edit)
# Format: name|description|command

real|Real command|echo real
# another comment

  # indented comment
  
BANK
        source "$helper"
        bank_load
        [ "${#BANK_NAMES[@]}" -eq 1 ] || { echo "FAIL A18: expected 1, got ${#BANK_NAMES[@]}"; exit 1; }
        [ "${BANK_NAMES[0]}" = "real" ] || { echo "FAIL A18: name mismatch"; exit 1; }
        echo "PASS A18: bank_load skips comments and blanks"
    ) && printf '  PASS  bank_load skips comments and blank lines\n' \
      || printf '  FAIL  bank_load skips comments and blank lines\n'

    # A19: multiline command storage round-trip — escapes \n, single record line
    (
        BANK_FILE="$sandbox/a19.bank.env"
        : > "$BANK_FILE"
        source "$helper"
        script="$(cat <<'SCRIPT'
#!/usr/bin/env bash
for tag in one two; do
    out="$(printf '%s' "$tag" | tr 'a-z' 'A-Z')"
    echo "tag=${tag} out=${out} done"
done
SCRIPT
)"
        bank_add "ml" "Multiline demo" "$script"
        bank_load
        [ "${#BANK_NAMES[@]}" -eq 1 ] || { echo "FAIL A19: expected 1 entry, got ${#BANK_NAMES[@]}"; exit 1; }
        [ "${BANK_CMDS[0]}" = "$script" ] || { echo "FAIL A19: command bytes differ"; exit 1; }
        rec_lines="$(grep -c '^ml|' "$BANK_FILE" || true)"
        [ "$rec_lines" -eq 1 ] || { echo "FAIL A19: expected 1 record line, got $rec_lines"; exit 1; }
        [ "$(wc -l < "$BANK_FILE")" -eq 4 ] || { echo "FAIL A19: file has bogus physical lines"; exit 1; }
        grep -q '\\n' "$BANK_FILE" || { echo "FAIL A19: missing \\n escape in file"; exit 1; }
        echo "PASS A19: multiline round-trip"
    ) && printf '  PASS  multiline storage round-trip (one record line, \\n escapes)\n' \
      || printf '  FAIL  multiline storage round-trip (one record line, \\n escapes)\n'

    # A20: literal \n (backslash-n) in command round-trips literally — NOT a real newline
    (
        BANK_FILE="$sandbox/a20.bank.env"
        : > "$BANK_FILE"
        source "$helper"
        esc="$(printf '%s' "printf 'a\\nb'")"
        bank_add "esc" "Escapes" "$esc"
        bank_load
        [ "${BANK_CMDS[0]}" = "$esc" ] || { echo "FAIL A20: literal \\n not preserved [${BANK_CMDS[0]}]"; exit 1; }
        case "${BANK_CMDS[0]}" in
            *$'\n'*) echo "FAIL A20: decoded literal \\n into a real newline"; exit 1 ;;
        esac
        echo "PASS A20: literal \\n round-trip"
    ) && printf '  PASS  literal \\n command round-trips literally\n' \
      || printf '  FAIL  literal \\n command round-trips literally\n'

    # A21: old-format file (no BANK_VERSION marker) keeps raw backslashes — no %b decode
    (
        BANK_FILE="$sandbox/a21.bank.env"
        cat > "$BANK_FILE" <<'BANK'
# Command Bank — managed by pos system bank (do not hand-edit)
# Format: name|description|command
raw|Raw echo|echo 'a\b'
BANK
        source "$helper"
        bank_load
        expected="$(printf '%s' "echo 'a\\b'")"
        [ "${BANK_CMDS[0]}" = "$expected" ] || { echo "FAIL A21: raw backslash changed [${BANK_CMDS[0]}]"; exit 1; }
        echo "PASS A21: old-format raw backslash"
    ) && printf '  PASS  old-format file keeps raw backslash (no decode)\n' \
      || printf '  FAIL  old-format file keeps raw backslash (no decode)\n'

    # A22: old-format entry survives a re-save byte-identically (escape + decode round-trip)
    (
        BANK_FILE="$sandbox/a22.bank.env"
        cat > "$BANK_FILE" <<'BANK'
# Command Bank — managed by pos system bank (do not hand-edit)
# Format: name|description|command
ts-google|Tailscale Google|tailscale status --json >/tmp/ts.json && grep -q '"ExitNodeStatus":null' /tmp/ts.json && tailscale set --exit-node=google || tailscale set --exit-node=
BANK
        source "$helper"
        bank_load
        orig="${BANK_CMDS[0]}"
        bank_add "new-cmd" "New entry" "echo ok"
        bank_load
        [ "${#BANK_NAMES[@]}" -eq 2 ] || { echo "FAIL A22: expected 2 entries, got ${#BANK_NAMES[@]}"; exit 1; }
        [ "${BANK_CMDS[0]}" = "$orig" ] || { echo "FAIL A22: old entry changed after re-save"; exit 1; }
        [ "${BANK_CMDS[1]}" = "echo ok" ] || { echo "FAIL A22: new entry missing"; exit 1; }
        echo "PASS A22: old-format re-save round-trip"
    ) && printf '  PASS  old-format entry round-trips through re-save\n' \
      || printf '  FAIL  old-format entry round-trips through re-save\n'

    # ═══════════════════════════════════════════════════════════════
    # Part B: pos system bank CLI integration tests
    # ═══════════════════════════════════════════════════════════════

    local pos_bank="$ROOT/bin/pos-system-bank"

    # B1: pos system bank --help shows usage
    test_run env BANK_FILE="$sandbox/b1.bank.env" "$pos_bank" --help
    check_rc "pos system bank --help exits 0" 0 "$TR_RC"
    check_contains "pos system bank --help shows Usage" "Usage:" "$TR_OUT"
    check_contains "pos system bank --help mentions subcommands" "Subcommands:" "$TR_OUT"

    # B2: pos system bank list on empty bank shows empty message
    : > "$sandbox/b2.bank.env"
    test_run env BANK_FILE="$sandbox/b2.bank.env" "$pos_bank" list
    check_rc "pos system bank list empty exits 0" 0 "$TR_RC"
    check_contains "pos system bank list empty message" "Command bank is empty" "$TR_OUT"

    # B3: pos system bank add — adds a command, verify in bank.env
    : > "$sandbox/b3.bank.env"
    test_run env BANK_FILE="$sandbox/b3.bank.env" "$pos_bank" add "disk-usage" "Check disk usage" "df -h"
    check_rc "pos system bank add exits 0" 0 "$TR_RC"
    check_contains "pos system bank add confirms" "Saved: disk-usage" "$TR_OUT"
    # Verify the file
    if grep -q '^disk-usage|Check disk usage|df -h$' "$sandbox/b3.bank.env"; then
        printf '  PASS  pos system bank add persists to bank.env\n'
    else
        printf '  FAIL  pos system bank add did not persist to bank.env\n'
    fi

    # B4: pos system bank add duplicate — fails
    test_run env BANK_FILE="$sandbox/b3.bank.env" "$pos_bank" add "disk-usage" "dup" "echo dup"
    check_not_contains "pos system bank add duplicate errors" "0" "$TR_RC"
    check_contains "pos system bank add duplicate message" "already exists" "$TR_OUT"

    # B5: pos system bank show — shows command details
    test_run env BANK_FILE="$sandbox/b3.bank.env" "$pos_bank" show "disk-usage"
    check_rc "pos system bank show exits 0" 0 "$TR_RC"
    check_contains "pos system bank show shows name" "Name: disk-usage" "$TR_OUT"
    check_contains "pos system bank show shows description" "Check disk usage" "$TR_OUT"
    check_contains "pos system bank show shows command" "df -h" "$TR_OUT"

    # B6: pos system bank show missing — fails
    test_run env BANK_FILE="$sandbox/b3.bank.env" "$pos_bank" show "nonexistent"
    check_not_contains "pos system bank show missing exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank show missing message" "not found" "$TR_OUT"

    # B7: pos system bank list after add — shows the entry
    test_run env BANK_FILE="$sandbox/b3.bank.env" "$pos_bank" list
    check_rc "pos system bank list populated exits 0" 0 "$TR_RC"
    check_contains "pos system bank list shows header" "COMMAND BANK" "$TR_OUT"
    check_contains "pos system bank list shows entry" "disk-usage" "$TR_OUT"

    # B8: pos system bank remove — removes a command
    test_run env BANK_FILE="$sandbox/b3.bank.env" "$pos_bank" remove "disk-usage"
    check_rc "pos system bank remove exits 0" 0 "$TR_RC"
    check_contains "pos system bank remove confirms" "Removed: disk-usage" "$TR_OUT"
    # Verify gone
    if grep -q '^disk-usage|' "$sandbox/b3.bank.env"; then
        printf '  FAIL  pos system bank remove did not delete from bank.env\n'
    else
        printf '  PASS  pos system bank remove deletes from bank.env\n'
    fi

    # B9: pos system bank remove missing — fails
    : > "$sandbox/b9.bank.env"
    test_run env BANK_FILE="$sandbox/b9.bank.env" "$pos_bank" remove "ghost"
    check_not_contains "pos system bank remove missing exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank remove missing message" "not found" "$TR_OUT"

    # B10: pos system bank add with parameters — show lists them
    : > "$sandbox/b10.bank.env"
    test_run env BANK_FILE="$sandbox/b10.bank.env" "$pos_bank" add "convert" "Convert video" "ffmpeg -i {input} -q:v {quality} {output}"
    check_rc "pos system bank add with params exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b10.bank.env" "$pos_bank" show "convert"
    check_contains "show lists input param" "input" "$TR_OUT"
    check_contains "show lists quality param" "quality" "$TR_OUT"
    check_contains "show lists output param" "output" "$TR_OUT"

    # B11: pos system bank add invalid name — fails
    : > "$sandbox/b11.bank.env"
    test_run env BANK_FILE="$sandbox/b11.bank.env" "$pos_bank" add "1bad" "desc" "cmd"
    check_not_contains "pos system bank add invalid name exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank add invalid name message" "Invalid name" "$TR_OUT"

    # B12: pos system bank run — executes a saved command (no params)
    # Negative control: the old `local name="" -a cli_params=()` declaration
    # crashed at line 150 before any output (rc != 0, no "Running:" line).
    : > "$sandbox/b12.bank.env"
    test_run env BANK_FILE="$sandbox/b12.bank.env" "$pos_bank" add "greet" "Greet" "echo bank-run-ok"
    check_rc "pos system bank add for run exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b12.bank.env" "$pos_bank" run "greet"
    check_rc "pos system bank run executes saved command" 0 "$TR_RC"
    check_contains "pos system bank run logs the command" "Running: echo bank-run-ok" "$TR_OUT"
    check_contains "pos system bank run executes output" "bank-run-ok" "$TR_OUT"

    # B13: pos system bank run missing command — fails
    test_run env BANK_FILE="$sandbox/b12.bank.env" "$pos_bank" run "ghost"
    check_not_contains "pos system bank run missing exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank run missing message" "Command not found" "$TR_OUT"

    # B14: pos system bank run with params — CLI key=val substitution, no interactive prompt
    : > "$sandbox/b14.bank.env"
    test_run env BANK_FILE="$sandbox/b14.bank.env" "$pos_bank" add "echo-param" "Echo param" "echo hi {who}"
    check_rc "pos system bank add param exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b14.bank.env" "$pos_bank" run "echo-param" "who=there"
    check_rc "pos system bank run with params exits 0" 0 "$TR_RC"
    check_contains "pos system bank run substitutes param" 'Running: echo hi "there"' "$TR_OUT"
    check_contains "pos system bank run executes substituted command" "hi there" "$TR_OUT"

    # B15: pos system bank add multiline + show — cmd_show retrieves the FULL script via arrays
    # Negative control: bank_get + cut -f3 truncated the command at the first newline.
    # (Brace-free script: {param} template detection would prompt on run in a non-TTY.)
    : > "$sandbox/b15.bank.env"
    ml_script="$(cat <<'SCRIPT'
#!/usr/bin/env bash
n=0
while [ "$n" -lt 2 ]; do
    n=$((n + 1))
    echo "round $n: $(printf 'ok')"
done
SCRIPT
)"
    test_run env BANK_FILE="$sandbox/b15.bank.env" "$pos_bank" add "ml-demo" "Multiline demo" "$ml_script"
    check_rc "pos system bank add multiline exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b15.bank.env" "$pos_bank" show "ml-demo"
    check_rc "pos system bank show multiline exits 0" 0 "$TR_RC"
    check_contains "pos system bank show prints script shebang" '#!/usr/bin/env bash' "$TR_OUT"
    check_contains "pos system bank show prints loop line" 'while [ "$n" -lt 2 ]; do' "$TR_OUT"
    check_contains "pos system bank show prints arithmetic line" 'n=$((n + 1))' "$TR_OUT"
    check_contains "pos system bank show prints substitution echo" 'echo "round $n: $(printf' "$TR_OUT"

    # B16: pos system bank run multiline — executes the WHOLE script via eval of the full command
    test_run env BANK_FILE="$sandbox/b15.bank.env" "$pos_bank" run "ml-demo"
    check_rc "pos system bank run multiline exits 0" 0 "$TR_RC"
    check_contains "pos system bank run multiline output line 1" "round 1: ok" "$TR_OUT"
    check_contains "pos system bank run multiline output line 2" "round 2: ok" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Part B2: pos system bank alias — managed ~/.bashrc block
    # ═══════════════════════════════════════════════════════════════

    local A_START='# >>> pos bank aliases (managed by pos system bank — do not hand-edit) <<<'
    local A_END='# <<< pos bank aliases (managed by pos system bank) <<<'

    # B17: alias create writes the managed block with the exact line format
    : > "$sandbox/b17.bank.env"
    : > "$sandbox/b17.bashrc"
    test_run env BANK_FILE="$sandbox/b17.bank.env" BASH_RC_FILE="$sandbox/b17.bashrc" "$pos_bank" add "backup" "Backup" "rsync -a src/ dst/"
    check_rc "pos system bank add for alias exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b17.bank.env" BASH_RC_FILE="$sandbox/b17.bashrc" "$pos_bank" alias "backup" "bk"
    check_rc "pos system bank alias create exits 0" 0 "$TR_RC"
    check_contains "pos system bank alias create confirms" "Alias 'bk'" "$TR_OUT"
    check_contains "pos system bank alias create hints source" "source $sandbox/b17.bashrc" "$TR_OUT"
    if grep -qF "alias bk='pos system bank run backup'" "$sandbox/b17.bashrc" \
        && grep -qF "$A_START" "$sandbox/b17.bashrc" \
        && grep -qF "$A_END" "$sandbox/b17.bashrc"; then
        printf '  PASS  alias create writes managed block with exact line\n'
    else
        printf '  FAIL  alias create writes managed block with exact line\n'
    fi

    # B18: alias create is idempotent — same alias name stays a single line
    test_run env BANK_FILE="$sandbox/b17.bank.env" BASH_RC_FILE="$sandbox/b17.bashrc" "$pos_bank" alias "backup" "bk"
    check_rc "pos system bank alias create idempotent exits 0" 0 "$TR_RC"
    local cnt18
    cnt18="$(grep -c '^alias bk=' "$sandbox/b17.bashrc" || true)"
    [ "$cnt18" -eq 1 ] && printf '  PASS  alias create stays a single line when repeated\n' \
        || printf '  FAIL  alias create stays a single line when repeated (count=%s)\n' "$cnt18"

    # B19: alias list — shows the header and the alias row
    test_run env BANK_FILE="$sandbox/b17.bank.env" BASH_RC_FILE="$sandbox/b17.bashrc" "$pos_bank" alias list
    check_rc "pos system bank alias list exits 0" 0 "$TR_RC"
    check_contains "pos system bank alias list shows header" "BANK ALIASES" "$TR_OUT"
    check_contains "pos system bank alias list shows bk row" "bk" "$TR_OUT"
    check_contains "pos system bank alias list shows target" "pos system bank run backup" "$TR_OUT"

    # B20: alias list without a block errors
    : > "$sandbox/b20.bashrc"
    test_run env BANK_FILE="$sandbox/b17.bank.env" BASH_RC_FILE="$sandbox/b20.bashrc" "$pos_bank" alias list
    check_not_contains "pos system bank alias list no-block exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank alias list no-block message" "No alias block" "$TR_OUT"

    # B21: alias for an unknown bank command errors
    test_run env BANK_FILE="$sandbox/b17.bank.env" BASH_RC_FILE="$sandbox/b17.bashrc" "$pos_bank" alias "ghost"
    check_not_contains "pos system bank alias unknown bank exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank alias unknown bank message" "Command not found" "$TR_OUT"

    # B22: invalid alias name errors
    test_run env BANK_FILE="$sandbox/b17.bank.env" BASH_RC_FILE="$sandbox/b17.bashrc" "$pos_bank" alias "backup" "1bad"
    check_not_contains "pos system bank alias invalid name exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank alias invalid name message" "Invalid alias name" "$TR_OUT"

    # B23: PATH-shadowed alias warns (non-blocking)
    : > "$sandbox/b23.bank.env"
    : > "$sandbox/b23.bashrc"
    test_run env BANK_FILE="$sandbox/b23.bank.env" BASH_RC_FILE="$sandbox/b23.bashrc" "$pos_bank" add "cat" "Cat" "cat file"
    check_rc "pos system bank add path-shadow cmd exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b23.bank.env" BASH_RC_FILE="$sandbox/b23.bashrc" "$pos_bank" alias "cat"
    check_rc "pos system bank alias path-shadow still exits 0" 0 "$TR_RC"
    check_contains "pos system bank alias path-shadow warns" "also a command on PATH" "$TR_OUT"

    # B24: alias colliding with an outer (unmanaged) alias is refused, file untouched
    : > "$sandbox/b24.bank.env"
    printf '%s\n' "alias ls='ls --color=auto'" "# my config" > "$sandbox/b24.bashrc"
    test_run env BANK_FILE="$sandbox/b24.bank.env" BASH_RC_FILE="$sandbox/b24.bashrc" "$pos_bank" add "ls" "Ls" "ls -la"
    check_rc "pos system bank add for collision exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b24.bank.env" BASH_RC_FILE="$sandbox/b24.bashrc" "$pos_bank" alias "ls"
    check_not_contains "pos system bank alias collision exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank alias collision message" "already defined outside the managed block" "$TR_OUT"
    if grep -qF "alias ls='ls --color=auto'" "$sandbox/b24.bashrc" \
        && ! grep -qF "$A_START" "$sandbox/b24.bashrc"; then
        printf '  PASS  alias collision leaves bashrc untouched\n'
    else
        printf '  FAIL  alias collision leaves bashrc untouched\n'
    fi

    # B25: retarget + multiple aliases — alias name is the key; alias <name> [alias_name]
    : > "$sandbox/b25.bank.env"
    : > "$sandbox/b25.bashrc"
    test_run env BANK_FILE="$sandbox/b25.bank.env" BASH_RC_FILE="$sandbox/b25.bashrc" "$pos_bank" add "backup" "Backup" "rsync"
    test_run env BANK_FILE="$sandbox/b25.bank.env" BASH_RC_FILE="$sandbox/b25.bashrc" "$pos_bank" add "df-x" "Df" "df -h"
    test_run env BANK_FILE="$sandbox/b25.bank.env" BASH_RC_FILE="$sandbox/b25.bashrc" "$pos_bank" alias "backup" "bk"
    check_rc "pos system bank alias first exits 0" 0 "$TR_RC"
    # retarget: same alias name bk now points at df-x via a different bank name
    test_run env BANK_FILE="$sandbox/b25.bank.env" BASH_RC_FILE="$sandbox/b25.bashrc" "$pos_bank" alias "df-x" "bk"
    check_rc "pos system bank alias retarget exits 0" 0 "$TR_RC"
    if grep -qF "alias bk='pos system bank run df-x'" "$sandbox/b25.bashrc" \
        && ! grep -qF "alias bk='pos system bank run backup'" "$sandbox/b25.bashrc"; then
        printf '  PASS  alias with same alias name retargets the existing line\n'
    else
        printf '  FAIL  alias with same alias name retargets the existing line\n'
    fi
    # a second distinct alias for the same bank command is allowed
    test_run env BANK_FILE="$sandbox/b25.bank.env" BASH_RC_FILE="$sandbox/b25.bashrc" "$pos_bank" alias "backup" "bku"
    check_rc "pos system bank alias second name exits 0" 0 "$TR_RC"
    local cnt25
    cnt25="$(grep -c '^alias ' "$sandbox/b25.bashrc" || true)"
    [ "$cnt25" -eq 2 ] && printf '  PASS  two aliases coexist (2 lines)\n' \
        || printf '  FAIL  two aliases coexist (lines=%s)\n' "$cnt25"

    # B26: alias remove keeps the block when other aliases remain
    test_run env BANK_FILE="$sandbox/b25.bank.env" BASH_RC_FILE="$sandbox/b25.bashrc" "$pos_bank" alias remove "bk"
    check_rc "pos system bank alias remove exits 0" 0 "$TR_RC"
    check_contains "pos system bank alias remove confirms" "Removed alias 'bk'" "$TR_OUT"
    if grep -qF "$A_START" "$sandbox/b25.bashrc" && grep -qF "$A_END" "$sandbox/b25.bashrc" \
        && ! grep -qF "alias bk=" "$sandbox/b25.bashrc" \
        && grep -qF "alias bku=" "$sandbox/b25.bashrc"; then
        printf '  PASS  alias remove keeps block with remaining aliases\n'
    else
        printf '  FAIL  alias remove keeps block with remaining aliases\n'
    fi

    # B27: removing the last alias cleans the block from the file entirely
    : > "$sandbox/b27.bank.env"
    : > "$sandbox/b27.bashrc"
    test_run env BANK_FILE="$sandbox/b27.bank.env" BASH_RC_FILE="$sandbox/b27.bashrc" "$pos_bank" add "deploy" "Deploy" "deploy.sh"
    test_run env BANK_FILE="$sandbox/b27.bank.env" BASH_RC_FILE="$sandbox/b27.bashrc" "$pos_bank" alias "deploy" "d"
    test_run env BANK_FILE="$sandbox/b27.bank.env" BASH_RC_FILE="$sandbox/b27.bashrc" "$pos_bank" alias remove "d"
    check_rc "pos system bank alias remove last exits 0" 0 "$TR_RC"
    if ! grep -qF "$A_START" "$sandbox/b27.bashrc" && [ ! -s "$sandbox/b27.bashrc" ]; then
        printf '  PASS  removing last alias cleans block and empties file\n'
    else
        printf '  FAIL  removing last alias cleans block and empties file\n'
    fi

    # B28: removing a missing alias errors (block present)
    : > "$sandbox/b28.bank.env"
    : > "$sandbox/b28.bashrc"
    test_run env BANK_FILE="$sandbox/b28.bank.env" BASH_RC_FILE="$sandbox/b28.bashrc" "$pos_bank" add "deploy" "Deploy" "deploy.sh"
    test_run env BANK_FILE="$sandbox/b28.bank.env" BASH_RC_FILE="$sandbox/b28.bashrc" "$pos_bank" alias "deploy" "d"
    test_run env BANK_FILE="$sandbox/b28.bank.env" BASH_RC_FILE="$sandbox/b28.bashrc" "$pos_bank" alias remove "nope"
    check_not_contains "pos system bank alias remove missing exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank alias remove missing message" "not found" "$TR_OUT"

    # B29: bank remove also drops aliases pointing at the removed command
    : > "$sandbox/b29.bank.env"
    : > "$sandbox/b29.bashrc"
    test_run env BANK_FILE="$sandbox/b29.bank.env" BASH_RC_FILE="$sandbox/b29.bashrc" "$pos_bank" add "foo" "Foo" "echo foo"
    test_run env BANK_FILE="$sandbox/b29.bank.env" BASH_RC_FILE="$sandbox/b29.bashrc" "$pos_bank" alias "foo" "f"
    test_run env BANK_FILE="$sandbox/b29.bank.env" BASH_RC_FILE="$sandbox/b29.bashrc" "$pos_bank" remove "foo"
    check_rc "pos system bank remove with alias exits 0" 0 "$TR_RC"
    check_contains "pos system bank remove mentions alias cleanup" "Removed alias pointing to 'foo'" "$TR_OUT"
    check_contains "pos system bank remove confirms" "Removed: foo" "$TR_OUT"
    if ! grep -qF "alias f=" "$sandbox/b29.bashrc" && ! grep -qF "$A_START" "$sandbox/b29.bashrc"; then
        printf '  PASS  bank remove drops alias and cleans block\n'
    else
        printf '  FAIL  bank remove drops alias and cleans block\n'
    fi

    # B30: unrelated bashrc content survives an alias add+remove round-trip byte-identically
    : > "$sandbox/b30.bank.env"
    printf '%s\n' "# user config" "export EDITOR=vim" "PATH=/custom:\$PATH" > "$sandbox/b30.orig"
    cp "$sandbox/b30.orig" "$sandbox/b30.bashrc"
    test_run env BANK_FILE="$sandbox/b30.bank.env" BASH_RC_FILE="$sandbox/b30.bashrc" "$pos_bank" add "tool" "Tool" "tool-cmd"
    test_run env BANK_FILE="$sandbox/b30.bank.env" BASH_RC_FILE="$sandbox/b30.bashrc" "$pos_bank" alias "tool" "tl"
    check_rc "pos system bank alias on custom bashrc exits 0" 0 "$TR_RC"
    test_run env BANK_FILE="$sandbox/b30.bank.env" BASH_RC_FILE="$sandbox/b30.bashrc" "$pos_bank" alias remove "tl"
    check_rc "pos system bank alias remove on custom bashrc exits 0" 0 "$TR_RC"
    if cmp -s "$sandbox/b30.orig" "$sandbox/b30.bashrc"; then
        printf '  PASS  unrelated bashrc content preserved byte-identically\n'
    else
        printf '  FAIL  unrelated bashrc content preserved byte-identically\n'
    fi

    # B31: malformed block (start marker without end) errors instead of rewriting
    printf '%s\n' "$A_START" "alias broken='pos system bank run junk'" > "$sandbox/b31.bashrc"
    : > "$sandbox/b31.bank.env"
    test_run env BANK_FILE="$sandbox/b31.bank.env" BASH_RC_FILE="$sandbox/b31.bashrc" "$pos_bank" alias list
    check_not_contains "pos system bank alias malformed block exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank alias malformed block message" "malformed" "$TR_OUT"

    # B32: empty block lists cleanly
    printf '%s\n' "$A_START" "$A_END" > "$sandbox/b32.bashrc"
    : > "$sandbox/b32.bank.env"
    test_run env BANK_FILE="$sandbox/b32.bank.env" BASH_RC_FILE="$sandbox/b32.bashrc" "$pos_bank" alias list
    check_rc "pos system bank alias empty block exits 0" 0 "$TR_RC"
    check_contains "pos system bank alias empty block message" "No aliases" "$TR_OUT"

    # B33: alias remove without a name on a non-tty errors with usage
    test_run env BANK_FILE="$sandbox/b27.bank.env" BASH_RC_FILE="$sandbox/b27.bashrc" "$pos_bank" alias remove
    check_not_contains "pos system bank alias remove no-arg exits non-zero" "0" "$TR_RC"
    check_contains "pos system bank alias remove no-arg usage" "pos system bank alias remove" "$TR_OUT"
}
