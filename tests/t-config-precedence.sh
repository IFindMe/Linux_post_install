#!/usr/bin/env bash
set -euo pipefail
# t-config-precedence.sh — canonical config loader + full precedence contract:
#   CLI flags > environment > config file > defaults
# Part A: load_env_file (lib/config-ui.sh) contract — parsing, quotes, CRLF,
#         comments, env-wins, missing-file no-op, basename under CONFIG_DIR.
# Part B: pos-ai-server behavioral dry-run (defaults → file → env → CLI).
# Part C: pos-communication-telegram-sender observable send URL (file/env/CLI).
# Part D: static guards — every migrated tool uses the shared loader; no
#         hand-rolled load_system_env remains.

run_test() {
    local sandbox cfg stubs
    sandbox="$(mksandbox config-precedence)"
    cfg="$sandbox/cfg"
    stubs="$sandbox/stubs"
    mkdir -p "$cfg" "$stubs"

    # ═══ Part A: load_env_file contract ═══
    source "$ROOT/lib/config-ui.sh"

    local f="$sandbox/loader.env"
    : > "$f"

    # A1: missing file = quiet no-op (rc 0, nothing exported)
    unset MISSING_KEY || true
    test_run load_env_file "$sandbox/does-not-exist.env"
    check_rc "missing file is a quiet no-op" 0 "$TR_RC"
    if [ -z "${MISSING_KEY:-}" ]; then
        printf '  PASS  missing file exports nothing\n'
    else
        printf '  FAIL  missing file exported something\n'
    fi

    # A2: KEY=VALUE parsed and exported, key registered in LOADED_ENV_KEYS
    printf 'FOO=fileval\n' > "$f"
    LOADED_ENV_KEYS=()
    unset FOO || true
    load_env_file "$f"
    check_eq "file value exported" "fileval" "${FOO:-}"
    check_contains "key registered in LOADED_ENV_KEYS" "FOO" "${LOADED_ENV_KEYS[*]}"

    # A3: environment wins over file (and file key NOT registered). The export
    # must already exist in the environment when the loader runs — a temp
    # `FOO=envval func` assignment would vanish with the call.
    (
        unset FOO || true
        export FOO=envval
        LOADED_ENV_KEYS=()
        load_env_file "$f"
        printf '%s' "${FOO:-}" > "$sandbox/a3.val"
        printf '%s' "${LOADED_ENV_KEYS[*]}" > "$sandbox/a3.keys"
    )
    check_eq "environment beats file (env-wins)" "envval" "$(cat "$sandbox/a3.val")"
    check_not_contains "env-won key not registered as file-loaded" "FOO" "$(cat "$sandbox/a3.keys")"

    # A4: CRLF line endings stripped
    printf 'BAR=crlfvalue\r\n' > "$f"
    LOADED_ENV_KEYS=()
    unset BAR || true
    load_env_file "$f"
    check_eq "CRLF stripped" "crlfvalue" "${BAR:-}"

    # A5: surrounding quotes stripped (double and single)
    printf 'BQ="doubleq"\nSQ='"'"'singleq'"'"'\n' > "$f"
    LOADED_ENV_KEYS=()
    unset BQ SQ || true
    load_env_file "$f"
    check_eq "double-quoted value unquoted" "doubleq" "${BQ:-}"
    check_eq "single-quoted value unquoted" "singleq" "${SQ:-}"

    # A6: comments and blank lines skipped
    printf '# COM=skipme\n\nREAL=yes\n' > "$f"
    LOADED_ENV_KEYS=()
    unset COM REAL || true
    load_env_file "$f"
    check_eq "non-comment key parsed" "yes" "${REAL:-}"
    if [ -z "${COM:-}" ]; then
        printf '  PASS  comment key skipped\n'
    else
        printf '  FAIL  comment key was loaded\n'
    fi

    # A7: bare basename resolves under CONFIG_DIR
    printf 'FROM_BASE=resolved\n' > "$cfg/ai.env"
    LOADED_ENV_KEYS=()
    unset FROM_BASE || true
    CONFIG_DIR="$cfg" load_env_file "ai.env"
    check_eq "basename resolved under CONFIG_DIR" "resolved" "${FROM_BASE:-}"

    # A8: only keys of the form KEY=VALUE (grep filter) are read
    printf 'NOEQUALS\n=novalue\nOK=yes\n' > "$f"
    LOADED_ENV_KEYS=()
    unset NOEQUALS OK || true
    load_env_file "$f"
    check_eq "line without '=' ignored, valid line loaded" "yes" "${OK:-}"
    if [ -z "${NOEQUALS:-}" ]; then
        printf '  PASS  bare line ignored\n'
    else
        printf '  FAIL  bare line loaded\n'
    fi

    # ═══ Part B: pos-ai-server behavioral precedence (dry-run ExecStart) ═══
    # llama-server stub (deps guard + flag validation) and nvidia-smi stub
    # (forces CPU path → deterministic --n-gpu-layers 0).
    cat > "$stubs/llama-server" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) echo "llama.cpp 1.2.3" ;;
    --help)
        cat <<'HELP'
usage: llama-server [options]
options:
  --host <addr>        bind address
  --port <port>        server port
  --n-gpu-layers <n>   layers to offload
  --ctx-size <n>       context size
  --threads <n>        cpu threads
  --mmap               memory mapping
HELP
        ;;
esac
STUB
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/nvidia-smi"
    # systemctl: succeed — F4's ensure_user_bus pre-flight must pass so Part B's
    # dry-run reaches the ExecStart output it asserts on (bus-missing behavior
    # lives in t-ai-server-bus.sh, not here).
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/systemctl"
    chmod +x "$stubs/llama-server" "$stubs/nvidia-smi" "$stubs/systemctl"

    local models="$sandbox/models"
    mkdir -p "$models"
    touch "$models/my-model.gguf"
    local server="$ROOT/bin/pos-ai-server"
    local base_env=(PATH="$stubs:/usr/bin:/bin" DRY_RUN=1 CONFIG_FILE="$cfg/ai.env")
    local exec_line
    : > "$cfg/ai.env"

    # B1: default when nothing set
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "default port 8088 (no config/env/CLI)" "--port 8088" "$exec_line"

    # B2: config file beats default
    printf 'LLAMACPP_PORT=9999\n' > "$cfg/ai.env"
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "config file value used" "--port 9999" "$exec_line"

    # B3: env beats config file
    test_run_env "${base_env[@]}" LLAMACPP_PORT=7777 -- "$server" start "$models/my-model.gguf"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "environment beats file" "--port 7777" "$exec_line"
    check_not_contains "file value suppressed by env" "--port 9999" "$exec_line"

    # B4: CLI beats env (and therefore file + default)
    test_run_env "${base_env[@]}" LLAMACPP_PORT=7777 -- "$server" start "$models/my-model.gguf" --port 5555
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "CLI beats env" "--port 5555" "$exec_line"
    check_not_contains "env value suppressed by CLI" "--port 7777" "$exec_line"

    # ═══ Part C: telegram-sender observable send URL ═══
    local curl_log="$sandbox/curl.log"
    : > "$curl_log"
    cat > "$stubs/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$curl_log"
printf '%s' '{"ok":true,"result":{"message_id":1}}'
STUB
    chmod +x "$stubs/curl"
    local sender="$ROOT/bin/pos-communication-telegram-sender"
    local s_env=(PATH="$stubs:/usr/bin:/bin" CONFIG_DIR="$cfg")

    # C1: no token anywhere → fail-closed, no send
    : > "$cfg/telegram.env"
    test_run_env "${s_env[@]}" -- "$sender" send hello --chat-id 456
    check_contains "no token → hard error" "No bot token" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  no token exits nonzero\n' || printf '  FAIL  no token exited 0\n'

    # C2: config file token used
    printf 'TELEGRAM_BOT_TOKEN=FILE_TOKEN\n' > "$cfg/telegram.env"
    test_run_env "${s_env[@]}" -- "$sender" send hello --chat-id 456
    check_rc "send succeeds from file config" 0 "$TR_RC"
    check_contains "file token in send URL" "/botFILE_TOKEN/sendMessage" "$(cat "$curl_log")"

    # C3: env beats file
    : > "$curl_log"
    test_run_env "${s_env[@]}" TELEGRAM_BOT_TOKEN=ENV_TOKEN -- "$sender" send hello --chat-id 456
    check_contains "env token in send URL" "/botENV_TOKEN/sendMessage" "$(cat "$curl_log")"
    check_not_contains "file token not used when env set" "/botFILE_TOKEN/sendMessage" "$(cat "$curl_log")"

    # C4: CLI flag beats env
    : > "$curl_log"
    test_run_env "${s_env[@]}" TELEGRAM_BOT_TOKEN=ENV_TOKEN -- "$sender" send hello --chat-id 456 --token CLI_TOKEN
    check_contains "CLI token in send URL" "/botCLI_TOKEN/sendMessage" "$(cat "$curl_log")"
    check_not_contains "env token suppressed by CLI" "/botENV_TOKEN/sendMessage" "$(cat "$curl_log")"

    # ═══ Part D: static migration guards ═══
    # every config-consuming tool must use the shared loader (D-D part 1)
    local tool
    for tool in pos-ai pos-ai-hf pos-ai-server pos-communication-matrix-listener \
                 pos-communication-matrix-sender pos-communication-scrcpy \
                 pos-communication-telegram-listener pos-communication-telegram-sender \
                 pos-media-grab pos-network-download; do
        if grep -q "load_env_file" "$ROOT/bin/$tool"; then
            printf '  PASS  %s uses shared load_env_file\n' "$tool"
        else
            printf '  FAIL  %s does not use load_env_file\n' "$tool"
        fi
    done
    # the three legacy load_system_env callers are DELIBERATE (documented in
    # lib/config-ui.sh's loader NOTE) — assert no OTHER tool uses the legacy
    # loader and the legacy function still exists for them.
    local legacy
    legacy="$(grep -l "load_system_env" "$ROOT"/bin/pos-* 2>/dev/null || true)"
    local legacy_set
    legacy_set="$(printf '%s\n' "$legacy" | grep -c . || true)"
    check_eq "exactly the 3 documented legacy loaders remain" "3" "$legacy_set"
    local lf
    for lf in $legacy; do
        case "$lf" in
            */pos-media-sync|*/pos-system-backup|*/pos-system-health)
                printf '  PASS  legacy loader allowed: %s\n' "$(basename "$lf")" ;;
            *)
                printf '  FAIL  unexpected legacy loader: %s\n' "$lf" ;;
        esac
    done
    if grep -q "load_system_env()" "$ROOT/lib/common.sh"; then
        printf '  PASS  load_system_env still defined for the legacy callers\n'
    else
        printf '  FAIL  load_system_env definition missing from lib/common.sh\n'
    fi
}