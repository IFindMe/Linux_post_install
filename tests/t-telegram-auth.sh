#!/usr/bin/env bash
set -euo pipefail
# t-telegram-auth.sh — Telegram listener authorization (D1):
#   - chat ID AND sender ID must both match (previously chat-OR-sender);
#   - unset TELEGRAM_OWNER_ID → fail-closed, no command ever runs;
#   - authorized message runs the mapped command exactly once;
#   - exactly one sendMessage for the authorized message (no reply loop).
# jq is a hard dep of the listener; stub curl serves a canned getUpdates batch
# once, then empty batches forever; timeout kills the daemon.

run_test() {
    require_cmd jq "telegram auth" || return 0
    require_cmd timeout "telegram auth" || return 0

    local sandbox stubs cfg marker curl_log
    sandbox="$(mksandbox telegram-auth)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    marker="$sandbox/executed.ping"
    curl_log="$sandbox/curl.log"
    mkdir -p "$stubs" "$cfg"
    : > "$curl_log"

    # ── stub curl: log argv; serve one getUpdates batch then empty; answer
    # sendMessage/setMyCommands with {ok:true}.
    local batch="$sandbox/batch.json"
    cat > "$batch" <<'JSON'
{"ok":true,"result":[
 {"update_id":1,"message":{"message_id":10,"from":{"id":123,"is_bot":false},"chat":{"id":456,"type":"private"},"date":0,"text":"/ping"}},
 {"update_id":2,"message":{"message_id":11,"from":{"id":999,"is_bot":false},"chat":{"id":456,"type":"private"},"date":0,"text":"/ping"}},
 {"update_id":3,"message":{"message_id":12,"from":{"id":123,"is_bot":false},"chat":{"id":789,"type":"private"},"date":0,"text":"/ping"}},
 {"update_id":4,"message":{"message_id":13,"from":{"id":999,"is_bot":false},"chat":{"id":789,"type":"private"},"date":0,"text":"/ping"}}
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
                cat "$batch"
            else
                printf '%s' '{"ok":true,"result":[]}'
            fi
            exit 0
            ;;
    esac
done
printf '%s' '{"ok":true}'
STUB
    chmod +x "$stubs/curl"

    : > "$cfg/telegram_commands.env"
    printf '/ping=touch %s\n' "$marker" >> "$cfg/telegram_commands.env"

    local listener="$ROOT/bin/pos-communication-telegram-listener"

    # ── run 1: all 4 authorization cases in one batch ──
    local common=(PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg"
        TELEGRAM_BOT_TOKEN=testbot TELEGRAM_CHAT_ID=456 TELEGRAM_OWNER_ID=123)
    rm -f "$sandbox/served.once" "$marker"; : > "$curl_log"
    test_run_env "${common[@]}" -- timeout 5 "$listener" --run
    check_contains "authorized /ping from owner chat ran" "exec: /ping" "$TR_OUT"
    check_file_exists "authorized command created marker" "$marker"
    check_eq "exactly one sendMessage (no reply loop)" 1 "$(count_occurrences sendMessage "$(cat "$curl_log")")"
    check_eq "three unauthorized messages warned" 3 "$(count_occurrences 'ignoring message in chat' "$TR_OUT")"
    check_not_contains "no unknown-command reply (wrong-chat/from msgs never handled)" "Unknown command" "$TR_OUT"

    # ── run 2: owner id unset → fail-closed, nothing runs, no sends ──
    rm -f "$sandbox/served.once" "$marker"; : > "$curl_log"
    test_run_env PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        TELEGRAM_BOT_TOKEN=testbot TELEGRAM_CHAT_ID=456 -- \
        timeout 5 "$listener" --run
    check_contains "owner-unset fail-closed warning" "TELEGRAM_OWNER_ID unset — ignoring command" "$TR_OUT"
    check_file_absent "no marker without owner id" "$marker"
    check_eq "no sendMessage without owner id" 0 "$(count_occurrences sendMessage "$(cat "$curl_log")")"
}