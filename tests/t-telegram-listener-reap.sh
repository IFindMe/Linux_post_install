#!/usr/bin/env bash
set -euo pipefail
# t-telegram-listener-reap.sh — regression tests for the listener crash-loop:
#   (a) a background command exiting non-zero (254) must NOT kill the daemon.
#       The old code reaped via `wait "$pid"` under `set -e`, so any non-zero
#       child exit aborted the listener and systemd Restart=always crash-looped
#       it (offset reset to 0 → duplicate re-delivery).  Reply must carry the
#       real exit code.
#   (b) getUpdates offset persistence: resumed from the state file across
#       restarts (no duplicate burst after restart), invalid state falls back
#       to 0, and empty batches never rewrite the file.
#   (c) negative control: the OLD trap + `wait "$pid"` idiom still dies on 254
#       (proves the regression is real and the fix works).
# Hermetic: stubbed curl (no network), stubbed systemctl, real jq/flock/timeout.

run_test() {
    require_cmd jq "telegram reap" || return 0
    require_cmd timeout "telegram reap" || return 0

    local sandbox stubs cfg runtime home listener curl_log batch_file
    sandbox="$(mksandbox telegram-reap)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    runtime="$sandbox/runtime"
    home="$sandbox/home"
    listener="$ROOT/bin/pos-communication-telegram-listener"
    curl_log="$sandbox/curl.log"
    mkdir -p "$stubs" "$cfg" "$runtime" "$home"
    : > "$curl_log"

    # ── command map: two commands with non-zero exits, one with output ──
    cat > "$cfg/telegram_commands.env" <<'MAP'
/fail254=exit 254
/with_out=echo boom; false
MAP
    : > "$cfg/telegram_prefixes.env"

    # ── stub curl ──
    # Serve one batch with 2 commands, then empty batches (sleep keeps the
    # empty-poll loop from spinning while the daemon runs).
    batch_file="$sandbox/batch.json"
    cat > "$batch_file" <<'JSON'
{"ok":true,"result":[
 {"update_id":1,"message":{"message_id":10,"from":{"id":123},"chat":{"id":456},"text":"/fail254"}},
 {"update_id":2,"message":{"message_id":11,"from":{"id":123},"chat":{"id":456},"text":"/with_out"}}
]}
JSON

    cat > "$stubs/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$curl_log"
for a in "\$@"; do
    case "\$a" in
        *getUpdates*)
            if [ ! -e "$sandbox/reap.served" ]; then
                touch "$sandbox/reap.served"
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

    local common=(PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg"
        XDG_RUNTIME_DIR="$runtime" HOME="$home"
        TELEGRAM_BOT_TOKEN=testbot TELEGRAM_CHAT_ID=456 TELEGRAM_OWNER_ID=123)

    # ── (a) non-zero command exit must not kill the daemon ──
    # rc=124 → `timeout` killed an alive-and-polling daemon; rc=0 → clean exit.
    # With the old code the daemon itself died with 254, which is caught here.
    test_run_env "${common[@]}" -- timeout 10 "$listener" --run

    if [ "${TR_RC:-0}" -eq 124 ] || [ "${TR_RC:-0}" -eq 0 ]; then
        printf '  PASS  daemon survived child exit 254 (rc=%s)\n' "${TR_RC}"
    else
        printf '  FAIL  daemon died with rc=%s (crash-loop regression)\n' "${TR_RC:-?}"
    fi

    check_contains "/fail254 dispatched" "exec: /fail254" "${TR_OUT:-}"
    check_contains "/with_out dispatched" "exec: /with_out" "${TR_OUT:-}"

    local curl_content
    curl_content="$(cat "$curl_log")"
    # The stub logs curl's RAW argv (--data-urlencode passes text unencoded
    # to the wire, so the log shows "text=exit 254" with a real space).
    # /fail254 has no output → reply text is "exit 254\nOK".
    check_contains "/fail254 reply carries exit 254" "text=exit 254" "$curl_content"
    # /with_out → "exit 1\nboom" — output preserved alongside the exit code.
    check_contains "/with_out reply carries exit 1" "text=exit 1" "$curl_content"
    check_contains "/with_out reply preserves output" "boom" "$curl_content"

    # ── offset persistence: written after processing updates ──
    # update 1 → offset 2 persisted (both messages advance the offset).
    check_eq "offset persisted after processing" "3" "$(cat "$cfg/telegram-listener.state")"

    # ── (b) offset resumed from the state file across restarts ──
    # No state file → offset starts at 0; with one present it resumes from it.
    local sb2 stubs2 cfg2 curl2
    sb2="$sandbox/resume"
    stubs2="$sb2/stubs"
    cfg2="$sb2/cfg"
    curl2="$sb2/curl.log"
    mkdir -p "$stubs2" "$cfg2"
    : > "$curl2"
    printf '99\n' > "$cfg2/telegram-listener.state"
    : > "$cfg2/telegram_commands.env"
    : > "$cfg2/telegram_prefixes.env"

    cat > "$stubs2/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$curl2"
for a in "\$@"; do
    case "\$a" in
        *getUpdates*)
            sleep 1
            printf '%s' '{"ok":true,"result":[]}'
            exit 0
            ;;
    esac
done
printf '%s' '{"ok":true}'
STUB
    chmod +x "$stubs2/curl"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs2/systemctl"
    chmod +x "$stubs2/systemctl"

    local common2=(PATH="$stubs2:/usr/bin:/bin" CONFIG_DIR="$cfg2"
        XDG_RUNTIME_DIR="$sb2/rt" HOME="$sb2/home"
        TELEGRAM_BOT_TOKEN=testbot TELEGRAM_CHAT_ID=456 TELEGRAM_OWNER_ID=123)
    mkdir -p "$sb2/rt" "$sb2/home"

    test_run_env "${common2[@]}" -- timeout 3 "$listener" --run
    check_contains "offset resumed from persisted state file" "offset=99" "$(cat "$curl2")"
    # Empty batches never rewrite the state file.
    check_eq "empty batches do not rewrite state" "99" "$(cat "$cfg2/telegram-listener.state")"

    # invalid state file → fall back to 0
    printf 'garbage\n' > "$cfg2/telegram-listener.state"
    : > "$curl2"
    test_run_env "${common2[@]}" -- timeout 3 "$listener" --run
    check_contains "invalid state file falls back to offset 0" "offset=0" "$(cat "$curl2")"

    # ── (c) negative control: the OLD trap + `wait "$pid"` idiom still dies ──
    local old_rc old_out
    set +e
    old_out="$(bash -s 2>&1 <<'INNER'
set -euo pipefail
declare -A _EXIT_CODES=()
trap 'while _p=$(wait -n 2>/dev/null); do _EXIT_CODES[$_p]=$?; done' CHLD
exit 254 & pid=$!
sleep 0.3
wait "$pid" 2>/dev/null; rc=$?
echo "still-alive rc=$rc"
INNER
)"
    old_rc=$?
    set -e
    check_not_contains "old trap+wait idiom does not survive 254" "still-alive" "$old_out"
    check_rc "old trap+wait idiom dies with 254" 254 "$old_rc"
}