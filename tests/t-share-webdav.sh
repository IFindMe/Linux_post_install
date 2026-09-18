#!/usr/bin/env bash
set -euo pipefail
# t-share-webdav.sh — zero-dependency regression tests for bin/pos-share-webdav
# (rclone serve-webdav share/unshare/list/enable/disable/status).
#
# Behaviour contract under test:
#   deps/dispatch: no rclone → err rc!=0 · unknown cmd → err · --help → rc 0 ·
#     share/enable/unshare without path → usage err
#   paths: relative → "Path must be absolute" · missing dir → "Path not found"
#   flags: --port needs numeric value · unknown/-bogus → "unknown option" ·
#     stray positional → "unexpected argument" · --cert/--key must pair and exist
#   auth (non-TTY, stdin /dev/null): no user → err · user but no pass → err ·
#     empty pass → err · --user beats env · env beats webdav.env · file beats prompt
#   share/enable DRY_RUN: rc 0, masked password, addr precedence
#     (--addr > --port > WEBDAV_ADDR), --no-auth ANY-client warn, --read-only,
#     TLS advisory (wildcard warns; loopback/Tailscale/cert silent)
#   status/list: empty serves/units, masked defaults, webdav.env origin,
#     ufw advisory (inactive → ok; active w/o rule → warn; active w/ rule → ok)
#   units (USER_SYSTEMD_DIR seam): enable writes 644 unit (network-online,
#     EnvironmentFile, ${VAR} secret refs — never the literal secret) + 600
#     webdav.env · bus pre-flight aborts BEFORE writing (no orphaned unit) ·
#     disable idempotent (path + all)
#   live daemon (real pgrep + /proc, fake sleeping rclone): spawn proof +
#     masked list + re-share restart (single daemon, no duplicate) +
#     unshare-stop (daemon reaped) — regression cover for WEBDAV-01
#     (webdav_pids_for path-first argv match; see retest report)
#   negative controls: sentinel secret absent from EVERY captured output +
#     the tripwire is proven live against a planted leak; fail-closed guards
#     asserted present in the tool source.
#
# Strategy: stub-PATH fakes (rclone/sleeping-daemon, systemctl, sudo→exec, ufw
# fixture, loginctl, pgrep-noop) + env-seam sandbox dirs (CONFIG_DIR,
# USER_SYSTEMD_DIR, WEBDAV_*, DRY_RUN, NOTIFY_PLATFORM=none). No network, no
# sudo, no system changes. Every tool invocation redirects stdin from /dev/null
# so NOTHING can block on a TTY prompt even when the suite runs in a terminal.
# NOTE: a whitespace-only WEBDAV_PASS (" ") is REFUSED by the tool
# (resolve_auth rejects blank after space-stripping) — asserted in group D;
# see the Tester reports (2026-09-18_webdav-tests.md, 2026-09-18_webdav-retest.md).

run_test() {
    local sandbox stubs stubs_nopgrep cfg units tool
    sandbox="$(mksandbox share-webdav)"
    stubs="$sandbox/stubs"
    stubs_nopgrep="$sandbox/stubs-nopgrep"
    cfg="$sandbox/cfg"
    units="$sandbox/units"
    mkdir -p "$stubs" "$stubs_nopgrep" "$cfg" "$units"
    tool="$ROOT/bin/pos-share-webdav"

    # Sentinel secret: unique, grep-safe; must NEVER appear in tool output.
    local SECRET="wdv-s3cr3t-sentinel-9f8a"

    # ── stubs ──
    # Fake rclone: the deps guard only needs `command -v` to succeed; when
    # actually spawned (live group) it stays alive with the daemon's argv, so
    # real pgrep + /proc discovery sees a genuine "rclone serve webdav <path>"
    # command line. TERM trap reaps the sleeper (no orphans).
    cat > "$stubs/rclone" <<'STUB'
#!/usr/bin/env bash
printf 'rclone %s\n' "$*" >> "${RCLONE_LOG:-/dev/null}"
sleep "${FAKE_RCLONE_SLEEP:-30}" & _sp=$!
trap 'kill "$_sp" 2>/dev/null; exit 0' TERM INT
wait "$_sp"
STUB
    # Fake systemctl: user bus reachable; units start inactive/disabled; every
    # invocation logged for enable/disable assertions. SYSTEMCTL_BUS_FAIL=1
    # simulates the headless-SSH bus failure (pre-flight must abort).
    cat > "$stubs/systemctl" <<'STUB'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${SYSTEMCTL_LOG:-/dev/null}"
case "$*" in
    *show-environment*)
        [ "${SYSTEMCTL_BUS_FAIL:-0}" = "1" ] && exit 1
        exit 0 ;;
    *is-active*|*is-enabled*) exit 1 ;;
    *) exit 0 ;;
esac
STUB
    # Fake sudo: log then exec (lets `sudo ufw status` reach the ufw stub).
    cat > "$stubs/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${SUDO_LOG:-/dev/null}"
exec "$@"
STUB
    # Fake ufw: canned status from $UFW_STATUS_FILE, else inactive.
    cat > "$stubs/ufw" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "status" ] && [ -n "${UFW_STATUS_FILE:-}" ] && [ -f "$UFW_STATUS_FILE" ]; then
    cat "$UFW_STATUS_FILE"
else
    printf 'Status: inactive\n'
fi
STUB
    # Fake loginctl: active session WITHOUT Linger → linger warning fires.
    cat > "$stubs/loginctl" <<'STUB'
#!/usr/bin/env bash
printf 'UID=1000\nState=active\n'
STUB
    # pgrep-noop: deterministic "no serves" for every group except the live one.
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs_nopgrep/pgrep"
    chmod +x "$stubs/rclone" "$stubs/systemctl" "$stubs/sudo" \
        "$stubs/ufw" "$stubs/loginctl" "$stubs_nopgrep/pgrep"

    export RCLONE_LOG="$sandbox/rclone.log"
    export SYSTEMCTL_LOG="$sandbox/systemctl.log"
    export SUDO_LOG="$sandbox/sudo.log"
    : > "$RCLONE_LOG"; : > "$SYSTEMCTL_LOG"; : > "$SUDO_LOG"

    local data="$sandbox/data"
    mkdir -p "$data"

    # Base env: deterministic PATH (real ufw/loginctl hidden — only stubs),
    # sandbox seams, dry-run, notifications sinked, auth from env.
    # NOTE: never `export` WEBDAV_* here — test_run_env inherits the caller
    # environment, so each case passes exactly the auth it means to test.
    local -a base=(PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin"
        CONFIG_DIR="$cfg" USER_SYSTEMD_DIR="$units"
        DRY_RUN=1 NOTIFY_PLATFORM=none
        WEBDAV_USER=bob "WEBDAV_PASS=$SECRET")

    # ═══ A: deps + dispatch ═══
    # A1: no rclone on PATH → hard error. /usr/bin holds a real rclone, so a
    # symlink-only dir (bash+dirname for the shebang/lib prologue, nothing
    # else) is the only way to hide it — still zero-dependency (ln -s).
    local hidestubs="$sandbox/hidestubs"
    mkdir -p "$hidestubs"
    ln -s "$(command -v bash)" "$hidestubs/bash"
    ln -s "$(command -v dirname)" "$hidestubs/dirname"
    test_run_env PATH="$hidestubs" CONFIG_DIR="$cfg" USER_SYSTEMD_DIR="$units" \
        -- "$tool" status </dev/null
    check_rc "no rclone → nonzero exit" 1 "$TR_RC"
    check_contains "no rclone → names the dep" "rclone not found" "$TR_OUT"

    # A2: unknown command.
    test_run_env "${base[@]}" -- "$tool" frobnicate </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  unknown command exits nonzero\n' \
                        || printf '  FAIL  unknown command exited 0\n'
    check_contains "unknown command names it" "Unknown command 'frobnicate'" "$TR_OUT"

    # A3: --help → rc 0 + usage.
    test_run_env "${base[@]}" -- "$tool" --help </dev/null
    check_rc "--help → rc 0" 0 "$TR_RC"
    check_contains "--help prints usage" "Usage: pos share webdav" "$TR_OUT"

    # A4/A5: missing path args → usage errors.
    test_run_env "${base[@]}" -- "$tool" share </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  share without path errors\n' \
                        || printf '  FAIL  share without path exited 0\n'
    check_contains "share without path hints usage" "share <path>" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" enable </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  enable without path errors\n' \
                        || printf '  FAIL  enable without path exited 0\n'
    test_run_env "${base[@]}" -- "$tool" unshare </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  unshare without path errors\n' \
                        || printf '  FAIL  unshare without path exited 0\n'

    # ═══ B: path validation ═══
    test_run_env "${base[@]}" -- "$tool" share relative/path </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  share relative path errors\n' \
                        || printf '  FAIL  share relative path exited 0\n'
    check_contains "share relative → absolute-path error" "Path must be absolute" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" share "$sandbox/no-such-dir" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  share missing dir errors\n' \
                        || printf '  FAIL  share missing dir exited 0\n'
    check_contains "share missing → not-found error" "Path not found" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" unshare relative/path </dev/null
    check_contains "unshare relative → absolute-path error" "Path must be absolute" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  unshare relative exits nonzero\n' \
                        || printf '  FAIL  unshare relative exited 0\n'
    test_run_env "${base[@]}" -- "$tool" enable relative/path </dev/null
    check_contains "enable relative → absolute-path error" "Path must be absolute" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  enable relative exits nonzero\n' \
                        || printf '  FAIL  enable relative exited 0\n'

    # ═══ C: serve-flag parsing failures (parse runs before auth, but auth is
    # set anyway so each failure is proven to come from the flag, not auth) ═══
    test_run_env "${base[@]}" -- "$tool" share "$data" --port abc </dev/null
    check_contains "--port abc → numeric error" "--port must be numeric" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  --port abc exits nonzero\n' \
                        || printf '  FAIL  --port abc exited 0\n'
    test_run_env "${base[@]}" -- "$tool" share "$data" --port </dev/null
    check_contains "bare --port → needs-a-value" "--port needs a value" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  bare --port exits nonzero\n' \
                        || printf '  FAIL  bare --port exited 0\n'
    test_run_env "${base[@]}" -- "$tool" share "$data" --bogus </dev/null
    check_contains "--bogus → unknown option" "unknown option '--bogus'" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  --bogus exits nonzero\n' \
                        || printf '  FAIL  --bogus exited 0\n'
    test_run_env "${base[@]}" -- "$tool" share "$data" straypositional </dev/null
    check_contains "stray positional → unexpected argument" "unexpected argument" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  stray positional exits nonzero\n' \
                        || printf '  FAIL  stray positional exited 0\n'
    # --cert without --key must fail (fail-closed: never silently serve HTTP).
    touch "$sandbox/cert.pem"
    test_run_env "${base[@]}" -- "$tool" share "$data" --cert "$sandbox/cert.pem" </dev/null
    check_contains "--cert alone → must-be-together" "--cert and --key must be given together" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  --cert alone exits nonzero\n' \
                        || printf '  FAIL  --cert alone exited 0\n'
    test_run_env "${base[@]}" -- "$tool" share "$data" --cert "$sandbox/missing.pem" \
        --key "$sandbox/missing-key.pem" </dev/null
    check_contains "missing cert → not-found" "cert not found" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  missing cert exits nonzero\n' \
                        || printf '  FAIL  missing cert exited 0\n'

    # ═══ D: auth resolution (non-TTY: stdin is /dev/null, never a prompt) ═══
    # D1: no user anywhere → err.
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        -- "$tool" share "$data" </dev/null
    check_contains "no user → auth error" "WebDAV auth needs a user" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  no user exits nonzero\n' \
                        || printf '  FAIL  no user exited 0\n'
    # D2: user but no password, non-interactive → err (never hangs on prompt).
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        WEBDAV_USER=bob -- "$tool" share "$data" </dev/null
    check_contains "no password non-TTY → password error" "no WebDAV password" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  no password exits nonzero\n' \
                        || printf '  FAIL  no password exited 0\n'
    # D3: empty password → refused (blank-password fail-closed).
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        WEBDAV_USER=bob WEBDAV_PASS="" -- "$tool" share "$data" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  empty password exits nonzero\n' \
                        || printf '  FAIL  empty password exited 0\n'
    check_contains "empty password → password error" "password" "$TR_OUT"
    # D4: whitespace-only password → refused (WEBDAV-02: blank check strips
    # spaces, so " " is blank too — same fail-closed message as D3).
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        WEBDAV_USER=bob WEBDAV_PASS=" " -- "$tool" share "$data" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  whitespace-only password exits nonzero\n' \
                        || printf '  FAIL  whitespace-only password exited 0\n'
    check_contains "whitespace-only password → blank-password error" "empty WebDAV password" "$TR_OUT"

    # ═══ E: DRY_RUN happy paths ═══
    # E1: basic share — rc 0, masked password, no daemon spawned.
    : > "$RCLONE_LOG"
    test_run_env "${base[@]}" -- "$tool" share "$data" </dev/null
    check_rc "share dry-run → rc 0" 0 "$TR_RC"
    check_contains "share dry-run announces serve" "(dry-run) would serve $data on :8080" "$TR_OUT"
    check_contains "share dry-run serving line masks password" "password masked" "$TR_OUT"
    check_contains "share dry-run names user" "user=bob" "$TR_OUT"
    check_not_contains "share dry-run leaks no secret" "$SECRET" "$TR_OUT"
    check_eq "share dry-run spawns no daemon" "" "$(cat "$RCLONE_LOG")"
    check_file_absent "share dry-run writes no log file" "$cfg/webdav-tmp-"*

    # E2: --no-auth warns ANY-client and serves without user.
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        -- "$tool" share "$data" --no-auth </dev/null
    check_rc "--no-auth dry-run → rc 0" 0 "$TR_RC"
    check_contains "--no-auth warns ANY-client" "ANY network client" "$TR_OUT"
    check_contains "--no-auth serving line" "Serving (no auth)" "$TR_OUT"

    # E3: --read-only accepted.
    test_run_env "${base[@]}" -- "$tool" share "$data" --read-only </dev/null
    check_rc "--read-only dry-run → rc 0" 0 "$TR_RC"
    check_contains "--read-only serving line" "Serving:" "$TR_OUT"
    check_not_contains "--read-only leaks no secret" "$SECRET" "$TR_OUT"

    # E4: addr precedence — --addr > --port > WEBDAV_ADDR seam.
    test_run_env "${base[@]}" -- "$tool" share "$data" --port 9999 </dev/null
    check_rc "--port dry-run → rc 0" 0 "$TR_RC"
    check_contains "--port derives addr" "on :9999" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" share "$data" --addr 127.0.0.1:9999 </dev/null
    check_contains "--addr wins verbatim" "on 127.0.0.1:9999" "$TR_OUT"
    test_run_env "${base[@]}" WEBDAV_ADDR="100.70.1.2:7777" \
        -- "$tool" share "$data" </dev/null
    check_contains "WEBDAV_ADDR seam used" "on 100.70.1.2:7777" "$TR_OUT"
    test_run_env "${base[@]}" WEBDAV_ADDR="100.70.1.2:7777" \
        -- "$tool" share "$data" --port 9999 </dev/null
    check_contains "--port beats WEBDAV_ADDR seam" "on :9999" "$TR_OUT"

    # E5: TLS advisory matrix.
    test_run_env "${base[@]}" -- "$tool" share "$data" </dev/null
    check_contains "wildcard HTTP warns plain-HTTP" "plain HTTP on :8080" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" share "$data" --addr 127.0.0.1:8080 </dev/null
    check_not_contains "loopback HTTP is silent" "plain HTTP" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" share "$data" --addr 100.70.1.2:8080 </dev/null
    check_not_contains "Tailscale HTTP is silent" "plain HTTP" "$TR_OUT"
    touch "$sandbox/key.pem"
    test_run_env "${base[@]}" -- "$tool" share "$data" \
        --cert "$sandbox/cert.pem" --key "$sandbox/key.pem" </dev/null
    check_rc "TLS pair dry-run → rc 0" 0 "$TR_RC"
    check_not_contains "TLS serve is silent" "plain HTTP" "$TR_OUT"
    check_not_contains "TLS leaks no secret" "$SECRET" "$TR_OUT"

    # E6: enable DRY_RUN prints the unit without writing anything.
    : > "$SYSTEMCTL_LOG"
    test_run_env "${base[@]}" -- "$tool" enable "$data" </dev/null
    check_rc "enable dry-run → rc 0" 0 "$TR_RC"
    check_contains "enable dry-run announces unit" "(dry-run) would install unit" "$TR_OUT"
    check_contains "enable dry-run ExecStart serves webdav" "serve webdav" "$TR_OUT"
    check_contains "enable dry-run references env user var" '${WEBDAV_USER}' "$TR_OUT"
    check_contains "enable dry-run references env pass var" '${WEBDAV_PASS}' "$TR_OUT"
    check_contains "enable dry-run EnvironmentFile line" "EnvironmentFile=" "$TR_OUT"
    check_not_contains "enable dry-run leaks no secret" "$SECRET" "$TR_OUT"
    check_eq "enable dry-run writes no unit" "" "$(ls "$units" 2>/dev/null || true)"
    check_file_absent "enable dry-run writes no env file" "$cfg/webdav.env"
    check_eq "enable dry-run touches no systemctl" "" "$(cat "$SYSTEMCTL_LOG")"

    # E7: enable --no-auth DRY_RUN carries no EnvironmentFile.
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        -- "$tool" enable "$data" --no-auth </dev/null
    check_rc "enable --no-auth dry-run → rc 0" 0 "$TR_RC"
    check_not_contains "enable --no-auth has no EnvironmentFile" "EnvironmentFile=" "$TR_OUT"
    check_contains "enable --no-auth warns ANY-client" "ANY network client" "$TR_OUT"

    # ═══ F: status / list ═══
    # F1: list with no serves.
    test_run_env "${base[@]}" -- "$tool" list </dev/null
    check_rc "list empty → rc 0" 0 "$TR_RC"
    check_contains "list empty message" "No WebDAV serves" "$TR_OUT"

    # F2: status shows units/defaults/firewall, passwords masked.
    test_run_env "${base[@]}" -- "$tool" status </dev/null
    check_rc "status → rc 0" 0 "$TR_RC"
    check_contains "status Serves section" "Serves" "$TR_OUT"
    check_contains "status units section" "Persistent units" "$TR_OUT"
    check_contains "status masks header" "passwords masked" "$TR_OUT"
    check_contains "status user from environment" "user: bob (environment)" "$TR_OUT"
    check_contains "status pass set via environment" "pass: (set via environment, masked)" "$TR_OUT"
    check_contains "status firewall ok (ufw inactive)" "no active ufw blocking port 8080" "$TR_OUT"
    check_not_contains "status leaks no secret" "$SECRET" "$TR_OUT"
    check_contains "sudo probed ufw" "sudo ufw status" "$(cat "$SUDO_LOG")"

    # F3: webdav.env origin — file values used, origin labelled, still masked.
    printf 'WEBDAV_USER=filebob\nWEBDAV_PASS=filepass\n' > "$cfg/webdav.env"
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        -- "$tool" status </dev/null
    check_contains "status user from webdav.env" "user: filebob (webdav.env)" "$TR_OUT"
    check_contains "status pass set via webdav.env" "pass: (set via webdav.env, masked)" "$TR_OUT"
    check_not_contains "status leaks no file secret" "filepass" "$TR_OUT"
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=1 NOTIFY_PLATFORM=none \
        -- "$tool" share "$data" </dev/null
    check_rc "share works from webdav.env auth alone" 0 "$TR_RC"
    check_contains "share uses file user" "user=filebob" "$TR_OUT"
    check_not_contains "share leaks no file secret" "filepass" "$TR_OUT"
    rm -f "$cfg/webdav.env"

    # F4: ufw advisory — active without rule warns; with rule stays quiet.
    printf 'Status: active\nTo  Action  From\n--  ------  ----\n22/tcp  ALLOW  Anywhere\n' \
        > "$sandbox/ufw-active-norule.txt"
    test_run_env "${base[@]}" UFW_STATUS_FILE="$sandbox/ufw-active-norule.txt" \
        -- "$tool" status </dev/null
    check_contains "ufw active w/o rule warns" "has no rule for port 8080" "$TR_OUT"
    printf 'Status: active\nTo  Action  From\n--  ------  ----\n8080/tcp  ALLOW  Anywhere\n' \
        > "$sandbox/ufw-active-rule.txt"
    test_run_env "${base[@]}" UFW_STATUS_FILE="$sandbox/ufw-active-rule.txt" \
        -- "$tool" status </dev/null
    check_not_contains "ufw active with rule is quiet" "has no rule" "$TR_OUT"
    check_contains "ufw active with rule ok" "no active ufw blocking port 8080" "$TR_OUT"

    # ═══ G: persistent units (USER_SYSTEMD_DIR seam, real enable path) ═══
    # G1: enable writes a 644 unit + 600 webdav.env; secret only as ${VAR} refs.
    local spaced="$sandbox/my share"
    mkdir -p "$spaced"
    : > "$SYSTEMCTL_LOG"
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=0 NOTIFY_PLATFORM=none \
        WEBDAV_USER=bob "WEBDAV_PASS=$SECRET" \
        -- "$tool" enable "$spaced" --port 8888 </dev/null
    check_rc "enable real → rc 0" 0 "$TR_RC"
    check_not_contains "enable real leaks no secret" "$SECRET" "$TR_OUT"
    check_contains "enable real linger advisory" "enable linger" "$TR_OUT"
    local -a unit_files=("$units"/pos-share-webdav-*.service)
    # NOTE: nullglob is off, so a no-match glob stays literal — derive the
    # count from ls|wc (trimmed: wc pads) and only then index the array.
    local unit_count
    unit_count="$(ls "$units"/pos-share-webdav-*.service 2>/dev/null | wc -l | tr -d ' ')"
    check_eq "exactly one unit written" 1 "$unit_count"
    local unit_file=""
    [ "$unit_count" -eq 1 ] && unit_file="${unit_files[0]}"
    [ -n "$unit_file" ] || unit_file="$units/__no-unit-written__"
    check_contains "unit name escapes the space" "_" "$(basename "$unit_file")"
    check_not_contains "unit name holds no space" " " "$(basename "$unit_file")"
    check_eq "unit mode 644" "644" "$(stat -c %a "$unit_file")"
    check_contains "unit orders after network" "After=network-online.target" "$(cat "$unit_file")"
    check_contains "unit references env file" "EnvironmentFile=$cfg/webdav.env" "$(cat "$unit_file")"
    check_contains "unit ExecStart serves the dir" "serve webdav" "$(cat "$unit_file")"
    check_contains "unit ExecStart quotes the spaced path" "\"$spaced\"" "$(cat "$unit_file")"
    check_contains "unit ExecStart uses user var" '${WEBDAV_USER}' "$(cat "$unit_file")"
    check_contains "unit ExecStart uses pass var" '${WEBDAV_PASS}' "$(cat "$unit_file")"
    check_not_contains "unit file holds no literal secret" "$SECRET" "$(cat "$unit_file")"
    check_file_exists "webdav.env written" "$cfg/webdav.env"
    check_eq "webdav.env mode 600" "600" "$(stat -c %a "$cfg/webdav.env")"
    check_not_contains "env file absent from unit display" "filepass" "$(cat "$unit_file")"
    check_contains "daemon-reload ran" "daemon-reload" "$(cat "$SYSTEMCTL_LOG")"
    check_contains "unit enabled --now" "enable --now" "$(cat "$SYSTEMCTL_LOG")"

    # G2: disable <path> removes the unit; second call is idempotent rc 0.
    : > "$SYSTEMCTL_LOG"
    test_run_env "${base[@]}" DRY_RUN=0 -- "$tool" disable "$spaced" </dev/null
    check_rc "disable path → rc 0" 0 "$TR_RC"
    check_contains "disable path announces removal" "Removed persistent WebDAV serve" "$TR_OUT"
    check_file_absent "unit removed" "$unit_file"
    check_contains "disable calls systemctl" "disable --now" "$(cat "$SYSTEMCTL_LOG")"
    test_run_env "${base[@]}" DRY_RUN=0 -- "$tool" disable "$spaced" </dev/null
    check_rc "disable again → rc 0 (idempotent)" 0 "$TR_RC"
    check_contains "disable again warns nothing-there" "No persistent WebDAV unit" "$TR_OUT"

    # G3: disable (no path) removes ALL units; empty set is idempotent rc 0.
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=0 NOTIFY_PLATFORM=none \
        WEBDAV_USER=bob "WEBDAV_PASS=$SECRET" \
        -- "$tool" enable "$data" </dev/null >/dev/null
    local second="$sandbox/second"
    mkdir -p "$second"
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=0 NOTIFY_PLATFORM=none \
        WEBDAV_USER=bob "WEBDAV_PASS=$SECRET" \
        -- "$tool" enable "$second" </dev/null >/dev/null
    check_eq "two units present" 2 "$(ls "$units"/pos-share-webdav-*.service 2>/dev/null | wc -l | tr -d ' ')"
    test_run_env "${base[@]}" DRY_RUN=0 -- "$tool" disable </dev/null
    check_rc "disable all → rc 0" 0 "$TR_RC"
    check_eq "all units removed" 0 "$(ls "$units"/pos-share-webdav-*.service 2>/dev/null | wc -l | tr -d ' ')"
    test_run_env "${base[@]}" DRY_RUN=0 -- "$tool" disable </dev/null
    check_rc "disable all when empty → rc 0" 0 "$TR_RC"
    check_contains "disable all when empty warns" "No persistent WebDAV units" "$TR_OUT"

    # G4: unshare idempotent — nothing serving → rc 0, no kill attempted.
    : > "$RCLONE_LOG"
    test_run_env "${base[@]}" DRY_RUN=0 -- "$tool" unshare "$data" </dev/null
    check_rc "unshare idle → rc 0 (idempotent)" 0 "$TR_RC"
    check_contains "unshare idle warns nothing-serving" "Nothing serving $data" "$TR_OUT"

    # G5: bus pre-flight — unreachable user bus aborts BEFORE any unit write
    # (no orphaned unit). If the write ever moved above the check, the
    # unit-present assertion below turns red.
    test_run_env PATH="$stubs_nopgrep:$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        USER_SYSTEMD_DIR="$units" DRY_RUN=0 NOTIFY_PLATFORM=none \
        WEBDAV_USER=bob "WEBDAV_PASS=$SECRET" SYSTEMCTL_BUS_FAIL=1 \
        -- "$tool" enable "$data" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  bus failure exits nonzero\n' \
                        || printf '  FAIL  bus failure exited 0\n'
    check_contains "bus failure explains remediation" "user systemd bus" "$TR_OUT"
    check_eq "bus failure writes no unit (no orphan)" 0 \
        "$(ls "$units"/pos-share-webdav-*.service 2>/dev/null | wc -l | tr -d ' ')"

    # ═══ H: live daemon (real pgrep + /proc against the fake rclone) ═══
    # Regression cover for WEBDAV-01 (fixed: webdav_pids_for now matches the
    # tool's own path-first daemon argv `rclone serve webdav <path> --addr
    # ...`, so share discovers its daemon, re-share restarts instead of
    # duplicating, and unshare stops it). Previously these discovery-dependent
    # cases were skip_case'd as BLOCKED — now asserted live, never faked.
    if command -v pgrep >/dev/null 2>&1 && command -v setsid >/dev/null 2>&1; then
        local livedir="$sandbox/livedata"
        mkdir -p "$livedir"
        local -a live=(PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg"
            USER_SYSTEMD_DIR="$units" DRY_RUN=0 NOTIFY_PLATFORM=none
            WEBDAV_USER=bob "WEBDAV_PASS=$SECRET" FAKE_RCLONE_SLEEP=25)
        : > "$RCLONE_LOG"
        test_run_env "${live[@]}" -- "$tool" share "$livedir" --port 18080 </dev/null
        check_rc "live share → rc 0" 0 "$TR_RC"
        check_contains "live share announces Serving" "Serving:" "$TR_OUT"
        check_contains "live share masks password" "password masked" "$TR_OUT"
        check_not_contains "live share leaks no secret" "$SECRET" "$TR_OUT"
        check_contains "live share spawns the daemon argv" \
            "serve webdav $livedir --addr :18080" "$(cat "$RCLONE_LOG")"
        check_file_exists "live share creates the CONFIG_DIR log file" \
            "$cfg/webdav-tmp-"*"livedata.log"
        local live_pids=""
        live_pids="$(pgrep -f "serve webdav $livedir" 2>/dev/null || true)"
        check_contains "live daemon visible to pgrep" "$livedir" \
            "$(tr '\0' ' ' <"/proc/$(printf '%s' "$live_pids" | head -1)/cmdline" 2>/dev/null || true)"
        test_run_env "${live[@]}" -- "$tool" list </dev/null
        check_contains "live list shows path" "$livedir" "$TR_OUT"
        check_contains "live list shows addr" ":18080" "$TR_OUT"
        check_contains "live list masks password" "pass=(set, masked)" "$TR_OUT"
        check_not_contains "live list leaks no secret" "$SECRET" "$TR_OUT"
        # Re-share the same path: discovery must fire (no duplicate daemon).
        test_run_env "${live[@]}" -- "$tool" share "$livedir" --port 18080 </dev/null
        check_rc "live re-share → rc 0" 0 "$TR_RC"
        check_contains "live re-share restarts" "Already serving" "$TR_OUT"
        check_not_contains "live re-share leaks no secret" "$SECRET" "$TR_OUT"
        check_eq "live re-share keeps a single daemon (no duplicate)" 1 \
            "$(pgrep -f "serve webda[v] $livedir" 2>/dev/null | wc -l | tr -d ' ')"
        # Unshare stops the daemon (no "Nothing serving" false-negative).
        test_run_env "${live[@]}" -- "$tool" unshare "$livedir" </dev/null
        check_rc "live unshare → rc 0" 0 "$TR_RC"
        check_contains "live unshare stops" "Stopped serving:" "$TR_OUT"
        check_eq "live unshare leaves no daemon" "" \
            "$(pgrep -f "serve webda[v] $livedir" 2>/dev/null || true)"
        # Cleanup: reap the spawned fake daemon(s) holding this sandbox path.
        # Bracket-trick pattern so pgrep can never match this shell itself.
        local stray
        for stray in $(pgrep -f "serve webda[v] $livedir" 2>/dev/null || true); do
            kill "$stray" 2>/dev/null || true
        done
        sleep 1
        for stray in $(pgrep -f "serve webda[v] $livedir" 2>/dev/null || true); do
            kill -9 "$stray" 2>/dev/null || true
        done
        check_eq "live daemons reaped" "" \
            "$(pgrep -f "serve webda[v] $livedir" 2>/dev/null || true)"
    else
        skip_case "live daemon share/list" "pgrep or setsid not available"
    fi

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
    # drops one of these validations, the suite turns red here first).
    check_eq "guard: blank-password refusal present" 1 \
        "$(grep -cF 'empty WebDAV password' "$tool" || true)"
    check_eq "guard: cert/key pairing present" 1 \
        "$(grep -cF -- '--cert and --key must be given together' "$tool" || true)"
    check_eq "guard: missing-password error present" 1 \
        "$(grep -cF 'no WebDAV password' "$tool" || true)"
    check_eq "guard: missing-user error present" 1 \
        "$(grep -cF 'WebDAV auth needs a user' "$tool" || true)"
    check_eq "guard: bus pre-flight before unit write" 1 \
        "$(grep -cF 'ensure_user_bus' "$tool" || true)"

    # ═══ J: auth precedence (flags > env > file) ═══
    # J1: --user beats WEBDAV_USER.
    test_run_env "${base[@]}" -- "$tool" share "$data" --user clibob </dev/null
    check_contains "CLI user beats env" "user=clibob" "$TR_OUT"
    check_not_contains "env user suppressed by CLI" "user=bob" "$TR_OUT"
    # J2: env beats webdav.env.
    printf 'WEBDAV_USER=filebob\nWEBDAV_PASS=filepass\n' > "$cfg/webdav.env"
    test_run_env "${base[@]}" -- "$tool" share "$data" </dev/null
    check_contains "env user beats file" "user=bob" "$TR_OUT"
    check_not_contains "file secret unused when env set" "filepass" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" status </dev/null
    check_contains "status labels env origin" "user: bob (environment)" "$TR_OUT"
    rm -f "$cfg/webdav.env"

    # ═══ K: non-TTY menu refusal ═══
    test_run_env "${base[@]}" -- "$tool" </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  bare invocation without TTY exits nonzero\n' \
                        || printf '  FAIL  bare invocation without TTY exited 0\n'
    check_contains "bare invocation needs a terminal" "needs a terminal" "$TR_OUT"
    test_run_env "${base[@]}" -- "$tool" menu </dev/null
    [ "$TR_RC" -ne 0 ] && printf '  PASS  menu without TTY exits nonzero\n' \
                        || printf '  FAIL  menu without TTY exited 0\n'
    check_contains "menu needs a terminal" "needs a terminal" "$TR_OUT"
}
