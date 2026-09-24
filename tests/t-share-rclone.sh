#!/usr/bin/env bash
set -euo pipefail
# t-share-rclone.sh — zero-dependency regression tests for bin/pos-share-rclone
# (paste-and-use rclone config: import/show/remotes/status/ls/check/copy/export).
#
# Behaviour contract under test (from AgentsReport/builder/2026-09-23_share-rclone-build.md):
#   deps/dispatch: no rclone → err rc!=0 (even for --help: guard sits before
#     help dispatch) · unknown cmd → err · --help → rc 0 · per-sub --help
#   import: piped-stdin paste + --file both validate via stub `rclone config
#     show` rc, write temp-then-rename, chmod 600, log success lines
#   validation: stub rc!=0 → "Invalid rclone config" · empty paste/file refused
#   no-clobber: occupied target without --force → 4-warn refusal rc!=0, target
#     untouched · --force overwrites with warning
#   show: secrets masked "(set, masked)", type/client_id/host verbatim, sentinel
#     absent · unknown remote → hint · empty config → hint rc!=0
#   remotes/status: empty config hints (remotes rc!=0, status 0 + hints)
#   copy: --dry-run forwards (log line + stub sees --dry-run) · $DRY_RUN=1
#     short-circuits with no rclone invoke · import $DRY_RUN writes nothing
#   negative controls: sentinel tripwire proven live on a planted leak;
#     fail-closed guards asserted present in the tool source.
#
# Strategy: stub-PATH fake rclone + RCLONE_CONFIG seam sandbox (never the real
# ~/.config/rclone/). No network, no sudo, no system changes. Every tool
# invocation gets stdin from a herestring (same stdin-paste path as a pipe)
# or /dev/null so NOTHING can block on a TTY prompt. Interactive menu flows
# need a human/TTY → skip_case (never fake).

run_test() {
    local sandbox stubs target tool
    sandbox="$(mksandbox share-rclone)"
    stubs="$sandbox/stubs"
    mkdir -p "$stubs"
    target="$sandbox/rclone.conf"
    tool="$ROOT/bin/pos-share-rclone"

    # Sentinel secret: unique, grep-safe; must NEVER appear in masked output.
    local SECRET="rcl-s3cr3t-sentinel-7q2b"

    # ── stub rclone ──
    # Hermetic fake: logs every argv line, resolves the effective config from
    # --config (else $RCLONE_CONFIG), and emulates config show / listremotes /
    # config file / version / ls / check / copy offline. RCLONE_CONFIG_SHOW_FAIL=1
    # forces `config show` rc!=0 (import validation-failure path); RCLONE_FAIL=1
    # forces ls/check/copy rc!=0 with $RCLONE_FAIL_MSG on stderr.
    cat > "$stubs/rclone" <<'STUB'
#!/usr/bin/env bash
logf="${RCLONE_LOG:-/dev/null}"
printf 'rclone %s\n' "$*" >>"$logf"
eff=""; prev=""
for a in "$@"; do
    if [ "$prev" = "--config" ]; then eff="$a"; prev=""; continue; fi
    if [ "$a" = "--config" ]; then prev="--config"; fi
done
cfg="${eff:-${RCLONE_CONFIG:-}}"
case "$*" in
    *"config show"*)
        if [ "${RCLONE_CONFIG_SHOW_FAIL:-0}" = "1" ]; then
            printf 'Failed to parse config (forced failure)\n' >&2
            printf 'Failed to parse config (forced failure)\n'
            exit 1
        fi
        if [ -z "$cfg" ] || [ ! -f "$cfg" ] || ! grep -qE '^\[.+\]' "$cfg" 2>/dev/null; then
            printf '; empty config\n'
            exit 0
        fi
        remote=""; skip_next=0; saw_show=0
        for a in "$@"; do
            if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
            if [ "$a" = "--config" ]; then skip_next=1; continue; fi
            case "$a" in --*) continue ;; esac
            if [ "$saw_show" -eq 1 ]; then
                case "$a" in config|show) continue ;; *) remote="$a" ;; esac
            fi
            if [ "$a" = "show" ]; then saw_show=1; fi
        done
        if [ -n "$remote" ]; then
            if grep -qE "^\[$remote\]" "$cfg" 2>/dev/null; then
                cat "$cfg"; exit 0
            else
                printf "didn't find section '%s' in config file\n" "$remote" >&2
                exit 1
            fi
        fi
        cat "$cfg"; exit 0
        ;;
    *"listremotes"*)
        if [ -z "$cfg" ] || [ ! -f "$cfg" ] || ! grep -qE '^\[.+\]' "$cfg" 2>/dev/null; then
            exit 0
        fi
        names="$(grep -E '^\[.+\]' "$cfg" | sed 's/^\[//;s/\].*//')"
        case "$*" in
            *"--long"*) for n in $names; do printf '%s:  testtype\n' "$n"; done ;;
            *) for n in $names; do printf '%s:\n' "$n"; done ;;
        esac
        exit 0
        ;;
    *"config file"*)
        if [ -n "$eff" ]; then
            printf 'Configuration file is stored at:\n%s\n' "$eff"
        else
            printf 'Configuration file is stored at:\n%s\n' "${RCLONE_CONFIG:-$HOME/.config/rclone/rclone.conf}"
        fi
        exit 0
        ;;
    *"version"*)
        printf 'rclone v9.9.9-test\n'
        exit 0
        ;;
    *"check"*)
        if [ "${RCLONE_FAIL:-0}" = "1" ]; then
            printf '%s\n' "${RCLONE_FAIL_MSG:-Failed to check: connection error}" >&2
            exit "${RCLONE_FAIL_RC:-1}"
        fi
        exit 0
        ;;
    *"copy"*)
        if [ "${RCLONE_FAIL:-0}" = "1" ]; then
            printf '%s\n' "${RCLONE_FAIL_MSG:-Failed to copy: connection error}" >&2
            exit "${RCLONE_FAIL_RC:-1}"
        fi
        exit 0
        ;;
    *"lsd"*|*"lsf"*|*" ls "*|"ls "*)
        if [ "${RCLONE_FAIL:-0}" = "1" ]; then
            printf '%s\n' "${RCLONE_FAIL_MSG:-Failed to ls: connection error}" >&2
            exit "${RCLONE_FAIL_RC:-1}"
        fi
        printf ' 100 file.txt\n'
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "$stubs/rclone"

    export RCLONE_LOG="$sandbox/rclone.log"
    : > "$RCLONE_LOG"

    # Canned INI: maskable keys carry the sentinel, keep-keys stay verbatim.
    local INI
    INI="$(printf '[mydrive]\ntype = drive\nclient_id = keep-client-9f8a\ntoken = %s\nclient_secret = %s\npass = %s\nhost = keep-host-9f8a\n' "$SECRET" "$SECRET" "$SECRET")"
    local INI2
    INI2="$(printf '[other]\ntype = s3\ntoken = new-token-123\n')"

    local -a base=(PATH="$stubs:/usr/bin:/bin"
        RCLONE_CONFIG="$target" NOTIFY_PLATFORM=none)

    # ═══ A: deps + dispatch ═══
    # A1: no rclone on PATH → hard error. A symlink-only dir (bash+dirname for
    # the shebang/lib prologue, nothing else) is the only way to hide a real
    # rclone — still zero-dependency (ln -s).
    local hidestubs="$sandbox/hidestubs"
    mkdir -p "$hidestubs"
    ln -s "$(command -v bash)" "$hidestubs/bash"
    ln -s "$(command -v dirname)" "$hidestubs/dirname"
    test_run_env PATH="$hidestubs" RCLONE_CONFIG="$target" NOTIFY_PLATFORM=none \
        -- "$tool" status </dev/null
    check_rc "no rclone → nonzero exit" 1 "$TR_RC"
    check_contains "no rclone → names the dep" "rclone not found" "$TR_OUT"
    # A1b: guard sits BEFORE --help, so help also fails without the dep.
    test_run_env PATH="$hidestubs" RCLONE_CONFIG="$target" NOTIFY_PLATFORM=none \
        -- "$tool" --help </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  no rclone --help exits nonzero\n' \
                         || printf '  FAIL  no rclone --help exited 0\n'
    check_contains "no rclone --help names the dep" "rclone not found" "$TR_OUT"

    # A2: unknown command.
    test_run_env "${base[@]}" -- "$tool" frobnicate </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  unknown command exits nonzero\n' \
                         || printf '  FAIL  unknown command exited 0\n'
    check_contains "unknown command names it" "Unknown command 'frobnicate'" "$TR_OUT"

    # A3: --help → rc 0 + usage.
    test_run_env "${base[@]}" -- "$tool" --help </dev/null
    check_rc "--help → rc 0" 0 "$TR_RC"
    check_contains "--help prints usage" "Usage: pos share rclone" "$TR_OUT"

    # A4: per-sub --help prints the 3-line block.
    test_run_env "${base[@]}" -- "$tool" remotes --help </dev/null
    check_rc "remotes --help → rc 0" 0 "$TR_RC"
    check_contains "remotes --help usage" "Usage: pos share rclone remotes" "$TR_OUT"

    # ═══ B: import paste + file ═══
    # B1: piped-stdin paste writes target, mode 600, success lines.
    # NOTE: stdin comes from a herestring (same stdin-paste path as a pipe);
    # a real `printf | test_run_env` pipeline would run test_run_env in a
    # subshell and lose $TR_OUT/$TR_RC, so herestrings are used throughout.
    rm -f "$target"
    test_run_env "${base[@]}" -- "$tool" import <<<"$INI"
    check_rc "import paste → rc 0" 0 "$TR_RC"
    check_contains "import paste success line" "Imported 1 remote(s) to $target (mode 600)" "$TR_OUT"
    check_contains "import paste verify hint" "Verify: pos share rclone remotes" "$TR_OUT"
    check_file_exists "import paste writes target" "$target"
    check_eq "import paste mode 600" "600" "$(stat -c %a "$target")"
    check_contains "import paste persists section" "[mydrive]" "$(cat "$target")"

    # B2: --file import to a second path.
    local src="$sandbox/old-rclone.conf" target2="$sandbox/rclone2.conf"
    printf '%s\n' "$INI2" > "$src"
    rm -f "$target2"
    test_run_env "${base[@]}" -- "$tool" import --file "$src" --config "$target2" </dev/null
    check_rc "import --file → rc 0" 0 "$TR_RC"
    check_contains "import --file success line" "Imported 1 remote(s) to $target2 (mode 600)" "$TR_OUT"
    check_file_exists "import --file writes target" "$target2"
    check_eq "import --file mode 600" "600" "$(stat -c %a "$target2")"
    check_contains "import --file persists section" "[other]" "$(cat "$target2")"
    check_contains "import --config leaves default untouched" "[mydrive]" "$(cat "$target")"

    # ═══ C: parse-validation ═══
    # C1: stub `config show` rc!=0 → invalid-config error, nothing written.
    local bad="$sandbox/bad.conf" badtarget="$sandbox/bad-target.conf"
    printf '[mydrive]\ntype = drive\ntoken = x\n' > "$bad"
    rm -f "$badtarget"
    test_run_env "${base[@]}" RCLONE_CONFIG_SHOW_FAIL=1 \
        -- "$tool" import --file "$bad" --config "$badtarget" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  invalid config exits nonzero\n' \
                         || printf '  FAIL  invalid config exited 0\n'
    check_contains "invalid config error" "Invalid rclone config" "$TR_OUT"
    check_file_absent "invalid config writes nothing" "$badtarget"

    # C2: empty paste refused.
    test_run_env "${base[@]}" -- "$tool" import --config "$sandbox/empty-paste.conf" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  empty paste exits nonzero\n' \
                         || printf '  FAIL  empty paste exited 0\n'
    check_contains "empty paste error" "Empty paste" "$TR_OUT"

    # C3: empty file refused.
    local emptyf="$sandbox/empty.conf"
    : > "$emptyf"
    test_run_env "${base[@]}" -- "$tool" import --file "$emptyf" --config "$sandbox/empty-file-target.conf" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  empty file exits nonzero\n' \
                         || printf '  FAIL  empty file exited 0\n'
    check_contains "empty file error" "Empty file" "$TR_OUT"

    # C4: missing file refused.
    test_run_env "${base[@]}" -- "$tool" import --file "$sandbox/no-such.conf" --config "$sandbox/missing-target.conf" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  missing file exits nonzero\n' \
                         || printf '  FAIL  missing file exited 0\n'
    check_contains "missing file error" "File not found or unreadable" "$TR_OUT"

    # ═══ D: no-clobber + force ═══
    # D1: occupied target without --force (non-TTY: stdin /dev/null, so the
    # refusal path fires without a confirm prompt) → rc!=0, target untouched.
    local before
    before="$(cat "$target")"
    test_run_env "${base[@]}" -- "$tool" import <<<"$INI2"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  clobber without --force exits nonzero\n' \
                         || printf '  FAIL  clobber without --force exited 0\n'
    check_contains "clobber refusal warns" "not overwriting" "$TR_OUT"
    check_contains "clobber refusal points at --force" "import --force" "$TR_OUT"
    check_eq "clobber refusal leaves target untouched" "$before" "$(cat "$target")"

    # D2: --force overwrites with warning.
    test_run_env "${base[@]}" -- "$tool" import --force <<<"$INI2"
    check_rc "import --force → rc 0" 0 "$TR_RC"
    check_contains "--force warns overwrite" "Overwriting existing config" "$TR_OUT"
    check_contains "--force persists new section" "[other]" "$(cat "$target")"
    check_eq "--force target still 600" "600" "$(stat -c %a "$target")"
    # Restore the sentinel-bearing config for the masking groups below.
    test_run_env "${base[@]}" -- "$tool" import --force <<<"$INI" >/dev/null

    # D3: $DRY_RUN import writes nothing.
    rm -f "$sandbox/dry-import.conf"
    test_run_env "${base[@]}" DRY_RUN=1 \
        -- "$tool" import --config "$sandbox/dry-import.conf" <<<"$INI"
    check_rc "import DRY_RUN → rc 0" 0 "$TR_RC"
    check_contains "import DRY_RUN announces" "(dry-run) would import" "$TR_OUT"
    check_file_absent "import DRY_RUN writes nothing" "$sandbox/dry-import.conf"

    # ═══ E: masked show ═══
    # E1: whole-config show masks secrets, keeps type/client_id/host verbatim.
    test_run_env "${base[@]}" -- "$tool" show </dev/null
    check_rc "show → rc 0" 0 "$TR_RC"
    check_contains "show masks secrets" "(set, masked)" "$TR_OUT"
    check_not_contains "show leaks no sentinel" "$SECRET" "$TR_OUT"
    check_contains "show keeps type verbatim" "type = drive" "$TR_OUT"
    check_contains "show keeps client_id verbatim" "client_id = keep-client-9f8a" "$TR_OUT"
    check_contains "show keeps host verbatim" "host = keep-host-9f8a" "$TR_OUT"

    # E2: single-remote show is masked too.
    test_run_env "${base[@]}" -- "$tool" show mydrive </dev/null
    check_rc "show remote → rc 0" 0 "$TR_RC"
    check_contains "show remote masks" "(set, masked)" "$TR_OUT"
    check_not_contains "show remote leaks no sentinel" "$SECRET" "$TR_OUT"

    # E3: unknown remote → error hint.
    test_run_env "${base[@]}" -- "$tool" show nosuchremote </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  unknown remote exits nonzero\n' \
                         || printf '  FAIL  unknown remote exited 0\n'
    check_contains "unknown remote hint" "Unknown remote 'nosuchremote'" "$TR_OUT"
    check_contains "unknown remote points at remotes" "pos share rclone remotes" "$TR_OUT"

    # E4: empty-config show → hint rc!=0.
    test_run_env PATH="$stubs:/usr/bin:/bin" RCLONE_CONFIG="$sandbox/does-not-exist.conf" \
        NOTIFY_PLATFORM=none -- "$tool" show </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  empty show exits nonzero\n' \
                         || printf '  FAIL  empty show exited 0\n'
    check_contains "empty show hint" "No remotes configured" "$TR_OUT"

    # ═══ F: empty-config remotes/status ═══
    # F1: remotes on empty config → hint rc!=0.
    test_run_env PATH="$stubs:/usr/bin:/bin" RCLONE_CONFIG="$sandbox/does-not-exist.conf" \
        NOTIFY_PLATFORM=none -- "$tool" remotes </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  empty remotes exits nonzero\n' \
                         || printf '  FAIL  empty remotes exited 0\n'
    check_contains "empty remotes hint" "No remotes configured" "$TR_OUT"

    # F2: remotes lists the pasted remote.
    test_run_env "${base[@]}" -- "$tool" remotes </dev/null
    check_rc "remotes → rc 0" 0 "$TR_RC"
    check_contains "remotes lists mydrive" "mydrive" "$TR_OUT"

    # F3: status shows the 3-line layout; empty config adds the hint.
    test_run_env "${base[@]}" -- "$tool" status </dev/null
    check_rc "status → rc 0" 0 "$TR_RC"
    check_contains "status names config path" "Config: $target" "$TR_OUT"
    check_contains "status remote count" "Remotes: 1 (mydrive)" "$TR_OUT"
    check_contains "status rclone version" "rclone: " "$TR_OUT"
    test_run_env PATH="$stubs:/usr/bin:/bin" RCLONE_CONFIG="$sandbox/does-not-exist.conf" \
        NOTIFY_PLATFORM=none -- "$tool" status </dev/null
    check_rc "empty status → rc 0" 0 "$TR_RC"
    check_contains "empty status zero remotes" "Remotes: 0 ((none))" "$TR_OUT"
    check_contains "empty status hint" "Empty config" "$TR_OUT"

    # ═══ G: copy/ls forwarding + DRY_RUN ═══
    # G1: copy --dry-run forwards the flag to rclone.
    : > "$RCLONE_LOG"
    test_run_env "${base[@]}" -- "$tool" copy /srv/media mydrive:media --dry-run </dev/null
    check_rc "copy --dry-run → rc 0" 0 "$TR_RC"
    check_contains "copy --dry-run announces" "Dry run" "$TR_OUT"
    check_contains "copy forwards to rclone" "copy" "$(cat "$RCLONE_LOG")"
    check_contains "copy forwards --dry-run" "--dry-run" "$(cat "$RCLONE_LOG")"

    # G2: $DRY_RUN=1 short-circuits with no rclone invoke.
    : > "$RCLONE_LOG"
    test_run_env "${base[@]}" DRY_RUN=1 -- "$tool" copy /srv/media mydrive:media </dev/null
    check_rc "copy DRY_RUN → rc 0" 0 "$TR_RC"
    check_contains "copy DRY_RUN announces" "(dry-run) would copy" "$TR_OUT"
    check_eq "copy DRY_RUN invokes no rclone" "" "$(cat "$RCLONE_LOG")"

    # G3: ls failure surfaces the error + remotes hint.
    test_run_env "${base[@]}" RCLONE_FAIL=1 RCLONE_FAIL_MSG="Failed to ls: connection error" \
        -- "$tool" ls "mydrive:backups/" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  ls failure exits nonzero\n' \
                         || printf '  FAIL  ls failure exited 0\n'
    check_contains "ls failure prints error" "Failed to ls" "$TR_OUT"
    check_contains "ls failure points at remotes" "pos share rclone remotes" "$TR_OUT"

    # G4: check failure surfaces the error + remotes hint.
    test_run_env "${base[@]}" RCLONE_FAIL=1 RCLONE_FAIL_MSG="Failed to check: connection error" \
        -- "$tool" check /srv/media "mydrive:media" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  check failure exits nonzero\n' \
                         || printf '  FAIL  check failure exited 0\n'
    check_contains "check failure prints error" "Failed to check" "$TR_OUT"
    check_contains "check failure points at remotes" "pos share rclone remotes" "$TR_OUT"

    # ═══ H: export (raw by design) ═══
    local exp="$sandbox/export.conf"
    rm -f "$exp"
    test_run_env "${base[@]}" -- "$tool" export --file "$exp" </dev/null
    check_rc "export --file → rc 0" 0 "$TR_RC"
    check_file_exists "export writes file" "$exp"
    check_eq "export mode 600" "600" "$(stat -c %a "$exp")"
    check_contains "export is raw (keeps token)" "$SECRET" "$(cat "$exp")"

    # ═══ I: negative controls ═══
    # I1: the sentinel tripwire is proven LIVE — fed a planted leak, the same
    # helper the suite uses must report FAIL (so a real leak can never pass
    # silently as a vacuous check).
    local probe
    probe="$(check_not_contains "tripwire probe" "$SECRET" "pass=$SECRET")"
    check_contains "negative control: tripwire fires on a planted leak" "FAIL" "$probe"
    probe="$(check_not_contains "tripwire probe" "$SECRET" "pass=(set, masked)")"
    check_contains "negative control: tripwire passes masked text" "PASS" "$probe"
    # I2: fail-closed guards are present in the tool source (if Builder ever
    # drops one, the suite turns red here first).
    check_eq "guard: dep guard present" 1 \
        "$(grep -cF 'rclone not found' "$tool" || true)"
    check_eq "guard: no-clobber refusal present (TTY-decline + non-TTY paths)" 2 \
        "$(grep -cF 'not overwriting' "$tool" || true)"
    check_eq "guard: invalid-config error present" 1 \
        "$(grep -cF 'Invalid rclone config' "$tool" || true)"
    check_eq "guard: unknown-remote hint present" 1 \
        "$(grep -cF "Unknown remote" "$tool" || true)"
    check_eq "guard: empty-paste refusal present" 1 \
        "$(grep -cF 'Empty paste' "$tool" || true)"
    check_eq "guard: show masking present" 1 \
        "$(grep -cF '(set, masked)' "$tool" || true)"

    # ═══ J: infeasible TTY/menu cases ═══
    skip_case "interactive menu flows" "needs human/TTY — non-TTY harness cannot drive share_menu"
}
