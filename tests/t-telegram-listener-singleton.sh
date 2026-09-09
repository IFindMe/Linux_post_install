#!/usr/bin/env bash
set -euo pipefail
# t-telegram-listener-singleton.sh — single-instance guard for the Telegram
# listener daemon (flock on ${XDG_RUNTIME_DIR:-/tmp}/pos-telegram-listener.lock):
#   (a) the first --run acquires the lock and reaches its poll loop;
#   (b) a second --run on the same runtime dir fails fast (exit 1) with the
#       exact single-instance message — no 409/getUpdates race;
#   (c) the flock auto-releases when the first instance exits, so the next
#       --run starts cleanly (systemd Restart=always path);
#   (d) --status reports the lock through the same primitives.
# Hermetic: stubbed curl (no network) + systemctl (no user bus), real
# jq/flock/timeout, sandboxed XDG_RUNTIME_DIR + CONFIG_DIR.

run_test() {
    require_cmd jq "telegram singleton guard" || return 0
    require_cmd flock "telegram singleton guard" || return 0
    require_cmd timeout "telegram singleton guard" || return 0

    local sandbox stubs cfg runtime home listener curl_log marker first_log
    sandbox="$(mksandbox telegram-singleton)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    runtime="$sandbox/runtime"
    home="$sandbox/home"
    listener="$ROOT/bin/pos-communication-telegram-listener"
    curl_log="$sandbox/curl.log"
    marker="$sandbox/loop.started"
    first_log="$sandbox/first.log"
    mkdir -p "$stubs" "$cfg" "$runtime" "$home"
    : > "$curl_log"

    # Stub curl: never touches the network. getUpdates serves an empty batch
    # forever (first call touches $marker so the test knows the daemon reached
    # its poll loop — which only happens AFTER the lock was acquired and the
    # config checks passed); everything else returns {ok:true}. The small
    # sleep keeps the empty-poll loop from spinning while the test runs.
    cat > "$stubs/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$curl_log"
for a in "\$@"; do
    case "\$a" in
        *getUpdates*)
            touch "$marker"
            sleep 1
            printf '%s' '{"ok":true,"result":[]}'
            exit 0
            ;;
    esac
done
printf '%s' '{"ok":true}'
STUB
    chmod +x "$stubs/curl"

    # Stub systemctl: deterministic exit 1 — --status must not reach the real
    # user bus; the autostart line is not what this test asserts.
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/systemctl"
    chmod +x "$stubs/systemctl"

    : > "$cfg/telegram_commands.env"
    : > "$cfg/telegram_prefixes.env"

    local common=(PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg"
        XDG_RUNTIME_DIR="$runtime" HOME="$home"
        TELEGRAM_BOT_TOKEN=testbot TELEGRAM_CHAT_ID=456 TELEGRAM_OWNER_ID=123)

    # ── (a) first instance acquires the lock and runs ──
    rm -f "$marker"
    env "${common[@]}" timeout 10 "$listener" --run >"$first_log" 2>&1 &
    local first_pid=$!

    local waited=0
    until [ -e "$marker" ]; do
        sleep 0.1
        waited=$((waited + 1))
        if [ "$waited" -ge 100 ]; then
            printf '  FAIL  first listener never reached the poll loop (log below)\n'
            cat "$first_log"
            kill "$first_pid" 2>/dev/null || true
            wait "$first_pid" 2>/dev/null || true
            return 0
        fi
    done
    printf '  PASS  first listener acquired lock and reached the poll loop\n'

    test_run_env "${common[@]}" -- "$listener" --status
    check_rc "status while daemon up exits 0" 0 "$TR_RC"
    check_contains "status reports lock held while running" \
        "listener:  running (single instance lock held)" "$TR_OUT"

    # ── (b) second instance fails fast with the exact message ──
    test_run_env "${common[@]}" -- timeout 3 "$listener" --run
    check_rc "second instance fails fast (exit 1)" 1 "$TR_RC"
    check_contains "second instance prints exact single-instance message" \
        "ERROR: listener already running (single instance) — check: systemctl --user status pos-telegram-listener" \
        "$TR_OUT"

    # ── (c) lock releases when the first instance ends ──
    kill "$first_pid" 2>/dev/null || true
    wait "$first_pid" 2>/dev/null || true

    test_run_env "${common[@]}" -- "$listener" --status
    check_contains "status reports not running after first exits" \
        "listener:  not running" "$TR_OUT"

    rm -f "$marker"
    env "${common[@]}" timeout 10 "$listener" --run >"$sandbox/third.log" 2>&1 &
    local third_pid=$!

    waited=0
    until [ -e "$marker" ]; do
        sleep 0.1
        waited=$((waited + 1))
        if [ "$waited" -ge 100 ]; then
            printf '  FAIL  third listener never reached the poll loop (log below)\n'
            cat "$sandbox/third.log"
            kill "$third_pid" 2>/dev/null || true
            wait "$third_pid" 2>/dev/null || true
            return 0
        fi
    done
    printf '  PASS  third listener starts cleanly after the lock was released\n'

    kill "$third_pid" 2>/dev/null || true
    wait "$third_pid" 2>/dev/null || true

    test_run_env "${common[@]}" -- "$listener" --status
    check_contains "status reports not running after third exits" \
        "listener:  not running" "$TR_OUT"
}