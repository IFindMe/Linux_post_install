#!/usr/bin/env bash
set -euo pipefail
# t-unsupported-flags.sh — unsupported-option handling (D4):
#   - CLI-explicit feature the model does not expose → hard error naming the
#     unsupported flag and the detected llama version,
#   - config-requested / env-requested unsupported flags → same hard error,
#   - unsupported *default* flags → silently dropped with a warning (start
#     still proceeds), never written into ExecStart,
#   - word-boundary matching: `--no-mmap` in help must NOT satisfy a request
#     for `--mmap` (the old grep -qF substring bug).

run_test() {
    local sandbox stubs cfg models
    sandbox="$(mksandbox unsupported-flags)"
    stubs="$sandbox/stubs"
    cfg="$sandbox/cfg"
    models="$sandbox/models"
    mkdir -p "$stubs" "$cfg" "$models"
    : > "$cfg/ai.env"
    touch "$models/my-model.gguf"

    local server="$ROOT/bin/pos-ai-server"
    local base_env=(PATH="$stubs:/usr/bin:/bin" DRY_RUN=1
        CONFIG_FILE="$cfg/ai.env" USER_SYSTEMD_DIR="$sandbox/userunits")

    # stub that omits --tensor-split (every default flag supported)
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
    chmod +x "$stubs/llama-server"
    # systemctl: succeed — F4's ensure_user_bus pre-flight must pass so these
    # flag-validation checks reach their intended outcome (unsupported-flag /
    # default-flag behavior). Bus-missing behavior lives in t-ai-server-bus.sh.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/systemctl"
    chmod +x "$stubs/systemctl"

    # 1. CLI-explicit unsupported flag → rc 1, names flag + model version
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf" --tensor-split 1:2:3
    check_contains "CLI unsupported --tensor-split: rc message" "does not expose" "$TR_OUT"
    check_contains "names the unsupported flag" "--tensor-split" "$TR_OUT"
    check_contains "names the detected model version" "1.2.3" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  CLI unsupported flag exits nonzero\n' || printf '  FAIL  CLI unsupported flag exits 0\n'

    # 2. unsupported flag requested from CONFIG → same hard error (config
    #    requested flags go through the same validation)
    printf 'LLAMACPP_PORT=9999\n' > "$cfg/ai.env"
    # stub without --port in help: config-requested --port is unsupported
    sed -i '/--port/d' "$stubs/llama-server"
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf"
    check_contains "config-requested unsupported flag: message" "does not expose" "$TR_OUT"
    check_contains "config-requested flag named" "--port" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  config-requested unsupported flag exits nonzero\n' || printf '  FAIL  config-requested unsupported flag exits 0\n'

    # 3. same via environment export (env feeds config-requested flags too)
    local envcfg="$sandbox/envcfg"
    mkdir -p "$envcfg"
    : > "$envcfg/ai.env"
    test_run_env PATH="$stubs:/usr/bin:/bin" DRY_RUN=1 \
        CONFIG_FILE="$envcfg/ai.env" USER_SYSTEMD_DIR="$sandbox/userunits" \
        LLAMACPP_PORT=9999 -- "$server" start "$models/my-model.gguf"
    check_contains "env-requested unsupported flag: message" "does not expose" "$TR_OUT"
    check_contains "env-requested flag named" "--port" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  env-requested unsupported flag exits nonzero\n' || printf '  FAIL  env-requested unsupported flag exits 0\n'

    # 4. unsupported default flag: start SUCCEEDS, warns, omits the flag
    #    (--threads absent from help; every other default supported)
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
  --mmap               memory mapping
HELP
        ;;
esac
STUB
    chmod +x "$stubs/llama-server"
    : > "$cfg/ai.env"
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf"
    check_rc "start succeeds with unsupported default" 0 "$TR_RC"
    check_contains "warns about dropped default flag" "--threads" "$TR_OUT"
    local exec_line
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_not_contains "dropped default never reaches ExecStart" "--threads" "$exec_line"
    check_contains "other defaults still emitted" "--n-gpu-layers 0" "$exec_line"

    # 5. word-boundary bug (D4): help advertises --no-mmap, NOT --mmap
    cat > "$stubs/llama-server" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) echo "llama.cpp 1.2.3" ;;
    --help)
        cat <<'HELP'
usage: llama-server [options]
options:
  --no-mmap            disable memory mapping
  --host <addr>        bind address
  --port <port>        server port
  --n-gpu-layers <n>   layers to offload
  --ctx-size <n>       context size
  --threads <n>        cpu threads
HELP
        ;;
esac
STUB
    chmod +x "$stubs/llama-server"
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf" --mmap
    check_contains "requested --mmap rejected (only --no-mmap in help)" "does not expose" "$TR_OUT"
    check_contains "rejection names --mmap" "--mmap" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  word-boundary: --no-mmap does not satisfy --mmap (rc != 0)\n' || printf '  FAIL  word-boundary: --no-mmap wrongly satisfied --mmap (rc 0)\n'

    # 6. control: full-support stub → all defaults + requested flags pass
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
    chmod +x "$stubs/llama-server"
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf" --mmap --tensor-split 1:2:3
    check_rc "control: full-support stub starts cleanly" 0 "$TR_RC"
    check_not_contains "control: no unsupported warning" "does not expose" "$TR_OUT"
}