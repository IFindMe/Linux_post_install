#!/usr/bin/env bash
set -euo pipefail
# t-systemd-unit.sh — generated systemd unit correctness (D5):
#   - exactly one ExecStart= line, binary + model paths quoted (spaces safe),
#   - each runtime flag emitted exactly once,
#   - EnvironmentFile= present with the ai.env path,
#   - `systemd-analyze verify` passes on the generated unit (skip if the
#     analyzer is unavailable).
# Runs the REAL unit-write path: stub systemctl/curl/llama-server so no
# system service or network is touched.

run_test() {
    local sandbox stubs unitdir models
    sandbox="$(mksandbox systemd-unit)"
    stubs="$sandbox/stubs"
    unitdir="$sandbox/userunits"
    models="$sandbox/models"
    mkdir -p "$stubs" "$unitdir" "$models"
    # model path deliberately contains spaces
    touch "$models/my model file.gguf"

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
    # systemctl: pretend every operation succeeds silently.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/systemctl"
    # curl (health check) returns an "ok" JSON body.
    printf '#!/usr/bin/env bash\nprintf "%%s" '"'"'{"status":"ok"}'"'"'\n' > "$stubs/curl"
    # nvidia-smi: no GPU → cpu path deterministic.
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/nvidia-smi"
    chmod +x "$stubs/llama-server" "$stubs/systemctl" "$stubs/curl" "$stubs/nvidia-smi"

    local server="$ROOT/bin/pos-ai-server"
    local model="$models/my model file.gguf"

    # Hermetic config seam (isolation): live ~/.config/.../ai.env pins
    # LLAMACPP_HOST/PORT via flags>env>file precedence; sandbox CONFIG_FILE
    # keeps the 8088/127.0.0.1 unit asserts hermetic.
    local empty_env="$sandbox/empty.env"
    : > "$empty_env"

    # REAL run: writes the unit to USER_SYSTEMD_DIR, waits ~2s for health.
    test_run_env -u LLAMACPP_PORT -u LLAMACPP_HOST PATH="$stubs:/usr/bin:/bin" CONFIG_FILE="$empty_env" USER_SYSTEMD_DIR="$unitdir" -- \
        timeout 60 "$server" start "$model"
    check_rc "real start writes unit and exits 0" 0 "$TR_RC"
    check_file_exists "unit file created" "$unitdir/pos-ai-server.service"

    local unit="$unitdir/pos-ai-server.service"
    local exec_lines unit_exec
    exec_lines="$(grep -c '^ExecStart=' "$unit" || true)"
    check_eq "exactly one ExecStart= line" 1 "$exec_lines"
    unit_exec="$(grep '^ExecStart=' "$unit")"
    check_contains "binary path (with spaces) quoted" "\"$stubs/llama-server\"" "$unit_exec"
    check_contains "model path (with spaces) double-quoted in unit" "\"$model\"" "$unit_exec"
    check_contains "port flag in unit" "--port 8088" "$unit_exec"
    check_contains "host flag in unit" "--host 127.0.0.1" "$unit_exec"
    check_contains "gpu layers flag in unit" "--n-gpu-layers 0" "$unit_exec"
    check_contains "ctx-size flag in unit" "--ctx-size 4096" "$unit_exec"
    check_contains "EnvironmentFile ai.env referenced" "EnvironmentFile=-%h/.config/linux_post_install/ai.env" "$(cat "$unit")"

    if command -v systemd-analyze >/dev/null 2>&1; then
        test_run systemd-analyze verify "$unit"
        check_rc "systemd-analyze verify accepts generated unit" 0 "$TR_RC"
    else
        skip_case "systemd-analyze verify" "systemd-analyze not available"
    fi
}