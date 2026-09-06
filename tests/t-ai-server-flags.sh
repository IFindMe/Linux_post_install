#!/usr/bin/env bash
set -euo pipefail
# t-ai-server-flags.sh — pos-ai-server argument generation: flag set from
# CLI-explicit vs config vs defaults; dedupe; every emitted flag comes from a
# validated source. Behavior asserted through the tool's own dry-run ExecStart
# output (no unit write, no systemd).

run_test() {
    local sbin sandbox stubs cfg models
    sandbox="$(mksandbox ai-server-flags)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    models="$sandbox/models"
    mkdir -p "$stubs" "$cfg" "$models"
    : > "$cfg/ai.env"
    touch "$models/my-model.gguf"

    # ── stub llama-server: version + full help; nvidia-smi forced to fail so
    # GPU detection deterministically resolves to "cpu" → --n-gpu-layers 0.
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
  --tensor-split <n>   tensor split
HELP
        ;;
esac
STUB
    cat > "$stubs/nvidia-smi" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    chmod +x "$stubs/llama-server" "$stubs/nvidia-smi"

    local server="$ROOT/bin/pos-ai-server"
    local base_env=(PATH="$stubs:/usr/bin:/bin" DRY_RUN=1
        CONFIG_FILE="$cfg/ai.env" USER_SYSTEMD_DIR="$sandbox/userunits")

    # 1. defaults: no CLI flags, no config → the always-emitted default set.
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf"
    check_rc "start with no flags exits 0" 0 "$TR_RC"
    local exec_line
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "dry-run ExecStart printed" "ExecStart:" "$TR_OUT"
    check_contains "default --port 8088" "--port 8088" "$exec_line"
    check_contains "default --host 127.0.0.1" "--host 127.0.0.1" "$exec_line"
    check_contains "default --n-gpu-layers 0 (cpu)" "--n-gpu-layers 0" "$exec_line"
    check_contains "default --ctx-size 4096" "--ctx-size 4096" "$exec_line"
    check_contains "default --threads emitted" "--threads" "$exec_line"
    check_contains "model path present via -m" "-m \"$models/my-model.gguf\"" "$exec_line"

    # 2. CLI-explicit flags override defaults and are emitted.
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf" --port 9090 --ctx-size 2048
    check_rc "start with CLI flags exits 0" 0 "$TR_RC"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "CLI --port 9090 emitted" "--port 9090" "$exec_line"
    check_contains "CLI --ctx-size 2048 emitted" "--ctx-size 2048" "$exec_line"
    check_not_contains "CLI --port wins over default 8088" "--port 8088" "$exec_line"

    # 3. dedupe: --ctx and --ctx-size map to the same canonical flag → one token
    #    (validate_requested_flags dedupes alias-mapped flags).
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf" --ctx 1024 --ctx-size 2048
    check_rc "start with alias pair exits 0" 0 "$TR_RC"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_eq "--ctx-size emitted exactly once after dedupe" 1 "$(count_token --ctx-size "$exec_line")"
    check_contains "dedupe keeps last value 2048" "--ctx-size 2048" "$exec_line"

    # 4. config-sourced values are emitted (no CLI).
    printf 'LLAMACPP_CTX_SIZE=512\nLLAMACPP_PORT=9999\n' > "$cfg/ai.env"
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf"
    check_rc "start with config exits 0" 0 "$TR_RC"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "config LLAMACPP_CTX_SIZE=512 emitted" "--ctx-size 512" "$exec_line"
    check_contains "config LLAMACPP_PORT=9999 emitted" "--port 9999" "$exec_line"

    # 5. CLI beats config (precedence contract: CLI > env > file > defaults).
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf" --port 1234
    check_rc "start with CLI over config exits 0" 0 "$TR_RC"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "CLI --port 1234 beats config 9999" "--port 1234" "$exec_line"
    check_not_contains "config port 9999 omitted when CLI given" "--port 9999" "$exec_line"

    # 6. only validated flags emitted: every default + requested flag appears
    #    exactly once in ExecStart.
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf" --mmap
    check_rc "start with --mmap exits 0" 0 "$TR_RC"
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_eq "--port exactly once" 1 "$(count_token --port "$exec_line")"
    check_eq "--host exactly once" 1 "$(count_token --host "$exec_line")"
    check_eq "--n-gpu-layers exactly once" 1 "$(count_token --n-gpu-layers "$exec_line")"
    check_eq "--ctx-size exactly once" 1 "$(count_token --ctx-size "$exec_line")"
    check_eq "--threads exactly once" 1 "$(count_token --threads "$exec_line")"
    check_eq "--mmap exactly once" 1 "$(count_token --mmap "$exec_line")"
}