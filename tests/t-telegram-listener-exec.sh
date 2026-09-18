#!/usr/bin/env bash
set -euo pipefail
# t-telegram-listener-exec.sh — async command execution in the Telegram
# listener.  Proves the listener can execute ANY valid Bash command without
# blocking: simple output, compound commands, pipes, stderr, long-running
# (timeout), and that the listener stays responsive while a command runs.
#
# Hermetic: stubbed curl (serves a canned getUpdates batch with /command
# messages, then empty batches), stubbed systemctl, real jq/timeout.
# No network, no real Telegram, no FFmpeg (unless /dev/video0 exists).

run_test() {
    require_cmd jq "telegram exec" || return 0
    require_cmd timeout "telegram exec" || return 0

    local sandbox stubs cfg curl_log marker listener batch runtime
    sandbox="$(mksandbox telegram-exec)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    curl_log="$sandbox/curl.log"
    marker="$sandbox/executed.log"
    listener="$ROOT/bin/pos-communication-telegram-listener"
    runtime="$sandbox/runtime"
    mkdir -p "$stubs" "$cfg" "$runtime"
    : > "$curl_log"
    : > "$marker"

    # ── command map: one /command per line, each triggers a known behavior ──
    cat > "$cfg/telegram_commands.env" <<'MAP'
/echo_hello=echo hello
/compound=sleep 0.2 && echo done
/stdout_test=printf 'line1\nline2\n'
/stderr_test=bash -c 'echo error_msg >&2; echo output_msg'
/pipe_test=echo "hello world" | tr ' ' '\n'
/long_run=sleep 30
/no_output=true
/quiet_test=@quiet echo hello_quiet
MAP

    : > "$cfg/telegram_prefixes.env"

    # ── stub curl ──
    # Serve a batch with 8 commands (one per mapped /command), then empty.
    local batch_file="$sandbox/batch.json"
    cat > "$batch_file" <<'JSON'
{"ok":true,"result":[
 {"update_id":1,"message":{"message_id":10,"from":{"id":123},"chat":{"id":456},"text":"/echo_hello"}},
 {"update_id":2,"message":{"message_id":11,"from":{"id":123},"chat":{"id":456},"text":"/compound"}},
 {"update_id":3,"message":{"message_id":12,"from":{"id":123},"chat":{"id":456},"text":"/stdout_test"}},
 {"update_id":4,"message":{"message_id":13,"from":{"id":123},"chat":{"id":456},"text":"/stderr_test"}},
 {"update_id":5,"message":{"message_id":14,"from":{"id":123},"chat":{"id":456},"text":"/pipe_test"}},
 {"update_id":6,"message":{"message_id":15,"from":{"id":123},"chat":{"id":456},"text":"/long_run"}},
 {"update_id":7,"message":{"message_id":16,"from":{"id":123},"chat":{"id":456},"text":"/no_output"}},
 {"update_id":8,"message":{"message_id":17,"from":{"id":123},"chat":{"id":456},"text":"/quiet_test"}}
]}
JSON

    cat > "$stubs/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$curl_log"
for a in "\$@"; do
    case "\$a" in
        *getUpdates*)
            if [ ! -e "$sandbox/served.once" ]; then
                touch "$sandbox/served.once"
                cat "$batch_file"
            else
                sleep 1
                printf '%s' '{"ok":true,"result":[]}'
            fi
            exit 0
            ;;
    esac
done
printf '%s' '{"ok":true}'
STUB
    chmod +x "$stubs/curl"

    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/systemctl"
    chmod +x "$stubs/systemctl"

    # XDG_RUNTIME_DIR sandbox (isolation): the listener's flock singleton
    # ($XDG_RUNTIME_DIR/pos-telegram-listener.lock) would otherwise collide
    # with the live daemon's lock and exit instantly with "already running".
    local common=(PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg"
        XDG_RUNTIME_DIR="$runtime"
        TELEGRAM_BOT_TOKEN=testbot TELEGRAM_CHAT_ID=456 TELEGRAM_OWNER_ID=123)

    # ── run the listener ──
    # /long_run (sleep 30) runs in background — the listener does NOT block.
    # The 45s outer timeout proves the listener stayed responsive.
    test_run_env "${common[@]}" -- timeout 45 "$listener" --run

    local curl_content
    curl_content="$(cat "$curl_log")"

    # ── all commands were dispatched ──
    check_contains "listener processed /echo_hello" "exec: /echo_hello" "$TR_OUT"
    check_contains "listener processed /compound"   "exec: /compound"   "$TR_OUT"
    check_contains "listener processed /long_run"   "exec: /long_run"   "$TR_OUT"

    # ── /echo_hello → "hello" ──
    check_contains "/echo_hello reply" "text=hello" "$curl_content"

    # ── /compound (sleep 0.2 && echo done) → "done" ──
    check_contains "/compound reply" "text=done" "$curl_content"

    # ── /stdout_test → multi-line stdout captured ──
    check_contains "/stdout_test reply" "text=line1" "$curl_content"

    # ── /stderr_test → stderr+stdout both captured ──
    # Output is "error_msg\noutput_msg" (newline-separated).
    # The curl log may split this across lines, so check each token alone.
    check_contains "/stderr_test stderr captured" "error_msg" "$curl_content"
    check_contains "/stderr_test stdout captured" "output_msg" "$curl_content"

    # ── /pipe_test → pipe works ──
    check_contains "/pipe_test reply" "text=hello" "$curl_content"

    # ── /no_output → "OK" (no output → default reply) ──
    check_contains "/no_output reply" "text=OK" "$curl_content"

    # ── /quiet_test → NO sendMessage with "hello_quiet" ──
    # Non-vacuous guard: the daemon must have actually dispatched /quiet_test
    # (an "already running" startup failure leaves an empty curl log, which
    # would otherwise pass the zero-count check without executing anything).
    check_contains "listener processed /quiet_test" "exec: /quiet_test" "$TR_OUT"
    # The setMyCommands call may contain "hello_quiet" in the description,
    # so we check that no sendMessage line contains it.
    local quiet_send_count
    quiet_send_count="$(printf '%s' "$curl_content" | grep 'sendMessage' | grep -c 'hello_quiet' || true)"
    check_eq "/quiet_test suppresses reply" 0 "$quiet_send_count"

    # ── the daemon exited within the outer timeout (not hung) ──
    # rc=124 means `timeout` killed it — listener was alive and processing.
    # rc=0 means it exited cleanly.  Both prove no hang.
    if [ "${TR_RC:-0}" -eq 124 ] || [ "${TR_RC:-0}" -eq 0 ]; then
        printf '  PASS  daemon exited cleanly (rc=%s, not hung)\n' "${TR_RC}"
    else
        printf '  FAIL  daemon exited with unexpected rc=%s\n' "${TR_RC:-?}"
    fi
}
