#!/usr/bin/env bash
set -euo pipefail
# t-matrix-auth.sh — Matrix listener authorization (D2):
#   - with MATRIX_ROOM_ID[+MATRIX_USER_ID] set: ONLY the owner in the watched
#     room runs commands; other senders / other rooms are ignored;
#   - with MATRIX_ROOM_ID unset: fail-closed, no command ever runs;
#   - exactly one reply (m.room.message send) per authorized event.
# Stub curl serves the sync batch once then empty batches; timeout kills the
# daemon (TERM trap → exit 0).

run_test() {
    require_cmd jq "matrix auth" || return 0
    require_cmd timeout "matrix auth" || return 0

    local sandbox stubs cfg marker curl_log
    sandbox="$(mksandbox matrix-auth)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    marker="$sandbox/executed.ping"
    curl_log="$sandbox/curl.log"
    mkdir -p "$stubs" "$cfg"
    : > "$curl_log"

    local batch="$sandbox/batch.json"
    cat > "$batch" <<'JSON'
{"next_batch":"b1","rooms":{"join":{
 "!room:example.org":{"timeline":{"events":[
   {"type":"m.room.message","event_id":"evt1","sender":"@owner:example.org","content":{"msgtype":"m.text","body":"/ping"}},
   {"type":"m.room.message","event_id":"evt2","sender":"@other:example.org","content":{"msgtype":"m.text","body":"/ping"}}
 ]}},
 "!other:example.org":{"timeline":{"events":[
   {"type":"m.room.message","event_id":"evt3","sender":"@owner:example.org","content":{"msgtype":"m.text","body":"/ping"}},
   {"type":"m.room.message","event_id":"evt4","sender":"@other:example.org","content":{"msgtype":"m.text","body":"/ping"}}
 ]}}
}}}
JSON
    cat > "$stubs/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$curl_log"
for a in "\$@"; do
    case "\$a" in
        *sync*)
            if [ ! -e "$sandbox/served.once" ]; then
                touch "$sandbox/served.once"
                cat "$batch"
            else
                printf '%s' '{"next_batch":"b2"}'
            fi
            exit 0
            ;;
    esac
done
printf '%s' '{"ok":true}'
STUB
    chmod +x "$stubs/curl"

    : > "$cfg/matrix_commands.env"
    printf '/ping=touch %s\n' "$marker" >> "$cfg/matrix_commands.env"

    local listener="$ROOT/bin/pos-communication-matrix-listener"
    local common=(PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg"
        MATRIX_HOMESERVER=https://matrix.example.org MATRIX_ACCESS_TOKEN=secret
        MATRIX_USER_ID=@owner:example.org MATRIX_ROOM_ID=!room:example.org)

    # ── run 1: room + owner set → exactly one command runs ──
    rm -f "$sandbox/served.once" "$marker"; : > "$curl_log"
    # --preserve-status + --kill-after surface the daemon's own TERM-trap exit,
    # so a broken trap (daemon-hang regression → SIGKILL 137 / timeout 124)
    # genuinely fails the rc assert instead of passing vacuously. --kill-after
    # also bounds the wait so a hung daemon can't stall the whole suite.
    test_run_env "${common[@]}" -- timeout --preserve-status -k 2 5 "$listener" --run
    check_rc "daemon terminated via TERM trap, not killed (no hang)" 2 "$TR_RC"
    check_contains "authorized /ping in watched room ran" "exec: /ping" "$TR_OUT"
    check_file_exists "authorized command created marker" "$marker"
    check_eq "exactly one reply sent (no reply loop)" 1 "$(count_occurrences '/send/m.room.message' "$(cat "$curl_log")")"
    check_not_contains "no unknown-command reply for ignored events" "Unknown command" "$TR_OUT"

    # ── run 2: MATRIX_ROOM_ID unset → fail-closed, nothing runs ──
    rm -f "$sandbox/served.once" "$marker"; : > "$curl_log"
    test_run_env PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg" \
        MATRIX_HOMESERVER=https://matrix.example.org MATRIX_ACCESS_TOKEN=secret \
        MATRIX_USER_ID=@owner:example.org -- timeout --preserve-status -k 2 5 "$listener" --run
    check_rc "room-unset daemon terminated via TERM trap, not killed (no hang)" 2 "$TR_RC"
    check_contains "room-unset fail-closed warning" "MATRIX_ROOM_ID unset — refusing to run commands" "$TR_OUT"
    check_not_contains "no exec without MATRIX_ROOM_ID" "exec: /ping" "$TR_OUT"
    check_file_absent "no marker without MATRIX_ROOM_ID" "$marker"
    check_eq "no replies without MATRIX_ROOM_ID" 0 "$(count_occurrences '/send/m.room.message' "$(cat "$curl_log")")"
}