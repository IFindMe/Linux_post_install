#!/usr/bin/env bash
set -euo pipefail
# t-share-mountpoint.sh — permanent regression for the share-client
# ask_mountpoint() manual-entry flow (2026-09-07 `t=type` UX change in
# bin/pos-share-smb-client + bin/pos-share-nfs-client; byte-identical bodies).
#
# Behaviour contract under test (both clients):
#   existing dir   → printed as-is, rc 0, NO confirm, NO mkdir
#   new dir + y    → confirm gate passes, sudo mkdir -p, dir created, rc 0
#   new dir + n    → rc 1, nothing created        (confirm EOF also denies)
#   existing file  → rc 1 + "not a directory" warning
#   relative / trailing-slash / system paths / empty-EOF → rc 1, no side effects
#   mkdir failure  → rc 1 + "Could not create" warning
#   stream         → display on stderr, result on stdout
#
# Strategy (production logic is never re-typed): the REAL ask_mountpoint body
# is brace-extracted verbatim from each client file (extract_fn, same pattern
# as t-menu-allow-empty.sh / t-ai-server-validate.sh) and sourced; the REAL
# helper chain lib/common.sh (warn/confirm/run/log) + lib/share-lib.sh
# (share_ask_value → menu_ask_value → menu_read_value) is exercised through
# the deterministic NON-TTY stdin path (stty -g fails on a pipe → plain
# IFS= read, common.sh:181-186). Input is fed as `printf '%b' | fn`, exactly
# like t-menu-allow-empty.sh feeds menu_ask_value. A fake `sudo` on PATH
# records every invocation and honors SUDO_FAIL, so the sandbox never touches
# the real system. NOTE: bash suppresses read -rp prompt text on a pipe, so
# the confirm prompt string is never asserted — the confirm gate is proven
# behaviourally (feed y → created; feed n → rc 1; missing answer → EOF-deny
# rc 1) and by SUDO_LOG (mkdir attempted or not).

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

run_test() {
    source "$ROOT/lib/common.sh"        # warn / confirm / run / log
    source "$ROOT/lib/share-lib.sh"     # share_ask_value → REAL menu_ask_value

    local sandbox stubs
    sandbox="$(mksandbox share-mountpoint)"
    stubs="$sandbox/stubs"
    mkdir -p "$stubs"

    # Fake sudo: records every invocation to $SUDO_LOG; exits 1 (no side
    # effect) when SUDO_FAIL=1, otherwise `exec "$@"` (real mkdir) so the
    # confirmed-create case genuinely creates the dir inside the sandbox.
    cat > "$stubs/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${SUDO_LOG:?fake sudo needs SUDO_LOG}"
if [ "${SUDO_FAIL:-0}" = "1" ]; then
    printf 'sudo: permission denied (fake)\n' >&2
    exit 1
fi
[ $# -gt 0 ] && exec "$@"
exit 0
STUB
    chmod +x "$stubs/sudo"
    export PATH="$stubs:$PATH"
    export SUDO_LOG="$sandbox/sudo.log"
    export SUDO_FAIL=0
    : > "$SUDO_LOG"

    # ═══ Part A0: non-TTY stdin contract of the real reader chain ═══
    # The whole matrix below is only deterministic if menu_read_value falls
    # back to plain `IFS= read` on a pipe and confirm() also reads plain
    # stdin. Prove both against the REAL helpers.
    local probe_out probe_rc
    set +e
    probe_out="$(printf 'x\n' | menu_read_value "probe" 2>/dev/null)"; probe_rc=$?
    set -e
    check_rc "non-TTY: menu_read_value pipe → rc 0 (plain-read fallback)" 0 "$probe_rc"
    check_eq "non-TTY: menu_read_value pipe → value" "x" "$probe_out"

    set +e
    printf '' | stty -g >/dev/null 2>&1; probe_rc=$?
    set -e
    check_rc "non-TTY: stty -g fails on a pipe (plain-read path active)" 1 "$probe_rc"

    set +e
    printf 'y\n' | confirm probe n >/dev/null 2>&1; probe_rc=$?
    set -e
    check_rc "non-TTY: confirm y → rc 0" 0 "$probe_rc"
    set +e
    printf 'n\n' | confirm probe n >/dev/null 2>&1; probe_rc=$?
    set -e
    check_rc "non-TTY: confirm n → rc 1" 1 "$probe_rc"
    set +e
    printf '' | confirm probe n >/dev/null 2>&1; probe_rc=$?
    set -e
    check_rc "non-TTY: confirm EOF → rc 1 (fail-closed)" 1 "$probe_rc"

    # ═══ Part A/B runner over the REAL extracted ask_mountpoint ═══
    # mp_case <prefix> <desc> <feed> <expect_rc> <expect_out>
    #          [<stderr-needle> [<stderr-absent> [<sudo_fail>]]]
    # feed = literal bytes: line 1 = mountpoint, line 2 (when present) = the
    # confirm answer. SUDO_LOG resets per case; side effects asserted by the
    # caller. SUDO_FAIL applies to the ask_mountpoint call only (assignment
    # prefix on the pipeline element; exported attribute carries it to the
    # fake sudo child process).
    mp_case() {
        local prefix="$1" desc="$2" feed="$3" expect_rc="$4" expect_out="$5"
        local needle="${6:-}" absent="${7:-}" failflag="${8:-0}"
        local out rc errf="$sandbox/mp.err"
        : > "$SUDO_LOG"
        set +e
        out="$(printf '%b' "$feed" | SUDO_FAIL="$failflag" ask_mountpoint 2>"$errf")"
        rc=$?
        set -e
        check_rc "$prefix: $desc (rc)" "$expect_rc" "$rc"
        check_eq "$prefix: $desc (stdout)" "$expect_out" "$out"
        if [ -n "$needle" ]; then
            check_contains "$prefix: $desc (stderr)" "$needle" "$(cat "$errf")"
        fi
        if [ -n "$absent" ]; then
            check_not_contains "$prefix: $desc (stderr)" "$absent" "$(cat "$errf")"
        fi
    }

    local client file
    for client in smb nfs; do
        case "$client" in
            smb) file="$ROOT/bin/pos-share-smb-client" ;;
            nfs) file="$ROOT/bin/pos-share-nfs-client" ;;
        esac

        local fn_file="$sandbox/ask_mountpoint-$client.sh"
        extract_fn "$file" ask_mountpoint > "$fn_file"
        source "$fn_file"     # REAL body — a syntax error here aborts (FAIL, never silent)

        local cdir="$sandbox/$client"
        mkdir -p "$cdir/existing"
        touch "$cdir/file"

        # 1. existing dir → as-is, rc 0. Feed has NO y/n line, so reaching the
        #    confirm gate would hit EOF → rc 1; rc 0 + empty SUDO_LOG proves
        #    the confirm/mkdir branch was never entered.
        mp_case "$client" "existing dir → used as-is, no create" \
            "$cdir/existing\n" 0 "$cdir/existing" "" "Created mount point"
        check_eq "$client: existing dir → sudo NOT attempted" "" "$(cat "$SUDO_LOG")"
        check_file_exists "$client: existing dir → fixture intact" "$cdir/existing"

        # 2. new dir + confirm y → sudo mkdir -p, dir created, printed, logged
        mp_case "$client" "new dir confirm=y → rc 0 + created" \
            "$cdir/newdir\ny\n" 0 "$cdir/newdir" "Created mount point"
        check_contains "$client: new dir → sudo mkdir -p attempted" \
            "sudo mkdir -p $cdir/newdir" "$(cat "$SUDO_LOG")"
        check_file_exists "$client: new dir → created" "$cdir/newdir"

        # 3. new dir + confirm n → rc 1, nothing created
        mp_case "$client" "new dir confirm=n → rc 1" \
            "$cdir/declined\nn\n" 1 "" "" ""
        check_eq "$client: declined → sudo NOT attempted" "" "$(cat "$SUDO_LOG")"
        check_file_absent "$client: declined → no dir created" "$cdir/declined"

        # 4. new dir + confirm EOF → rc 1 (gate fails closed)
        mp_case "$client" "new dir confirm=EOF → rc 1 (fail-closed)" \
            "$cdir/eof\n" 1 "" "" ""
        check_eq "$client: confirm-EOF → sudo NOT attempted" "" "$(cat "$SUDO_LOG")"
        check_file_absent "$client: confirm-EOF → no dir created" "$cdir/eof"

        # 5. existing non-directory → rc 1 + not-a-directory warning
        mp_case "$client" "existing file → rc 1 not-a-directory" \
            "$cdir/file\n" 1 "" "not a directory" ""
        check_eq "$client: file → sudo NOT attempted" "" "$(cat "$SUDO_LOG")"

        # 6. relative path → rc 1, warned, no write
        mp_case "$client" "relative path → rc 1" \
            "relative/path\n" 1 "" "not an absolute path" ""
        check_eq "$client: relative → sudo NOT attempted" "" "$(cat "$SUDO_LOG")"

        # 7. trailing slash → rc 1, warned, no write
        mp_case "$client" "trailing slash → rc 1" \
            "$cdir/existing/\n" 1 "" "must not end with a slash" ""
        check_eq "$client: trailing slash → sudo NOT attempted" "" "$(cat "$SUDO_LOG")"

        # 8. system paths → rc 1 (shape glob fires before any FS access)
        mp_case "$client" "system path /etc → rc 1" "/etc\n" 1 "" "Refusing system path" ""
        mp_case "$client" "system path /root → rc 1" "/root\n" 1 "" "Refusing system path" ""
        mp_case "$client" "system path /home/*/.ssh* → rc 1" \
            "/home/ci-user/.ssh/authorized_keys\n" 1 "" "Refusing system path" ""
        check_eq "$client: system paths → sudo NEVER attempted" "" "$(cat "$SUDO_LOG")"

        # 9. empty/EOF on the path input → rc 1 (share_ask_value cancel)
        mp_case "$client" "EOF on path → rc 1" "" 1 "" "" ""
        check_eq "$client: EOF → sudo NOT attempted" "" "$(cat "$SUDO_LOG")"

        # 10. mkdir failure (sudo shim fails) → rc 1 + could-not-create warning
        mp_case "$client" "mkdir fails → rc 1" \
            "$cdir/failmkdir\ny\n" 1 "" "Could not create" "" 1
        check_file_absent "$client: mkdir-fail → no dir created" "$cdir/failmkdir"

        # ═══ Part B: static guards — the old n=new flow must not regress ═══
        local thint=0 tarm=0
        grep -q 't=type' "$file" && thint=1
        grep -q 't | T)' "$file" && tarm=1
        check_eq "$client: t=type hint present" 1 "$thint"
        check_eq "$client: t | T arm present" 1 "$tarm"
        check_eq "$client: no n=new hint" 0 "$(grep -c 'n=new' "$file" || true)"
        check_eq "$client: no n | N arm" 0 "$(grep -c 'n | N)' "$file" || true)"
        check_eq "$client: no ask_new_mountpoint" 0 "$(grep -c 'ask_new_mountpoint' "$file" || true)"

        # Behavioural contract: the existing-dir branch must precede the
        # confirm/mkdir create flow inside the extracted body, so an existing
        # dir can never reach confirm/mkdir.
        check_eq "$client: ask_mountpoint has -d branch" 1 \
            "$(grep -cF '[ -d "$dir" ]' "$fn_file" || true)"
        check_eq "$client: ask_mountpoint has create flow" 1 \
            "$(grep -cF 'confirm "Create mountpoint' "$fn_file" || true)"
        local dline cline order=0
        dline="$(grep -nF '[ -d "$dir" ]' "$fn_file" | head -1 | cut -d: -f1 || true)"
        cline="$(grep -nF 'confirm "Create mountpoint' "$fn_file" | head -1 | cut -d: -f1 || true)"
        [ -n "$dline" ] && [ -n "$cline" ] && [ "$dline" -lt "$cline" ] && order=1
        check_eq "$client: existing-dir branch precedes confirm/mkdir" 1 "$order"

        unset -f ask_mountpoint
    done

    # ═══ Part C: symmetry — the two shipped bodies must stay identical ═══
    local same=0
    cmp -s "$sandbox/ask_mountpoint-smb.sh" "$sandbox/ask_mountpoint-nfs.sh" && same=1
    check_eq "ask_mountpoint bodies byte-identical (smb == nfs)" 1 "$same"
}