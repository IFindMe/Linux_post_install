#!/usr/bin/env bash
set -euo pipefail
# t-ai-llama-detect.sh — `pos ai-server status` behavior:
#   - prints the detected llama-server version from `--version`,
#   - "unknown" when the stub omits a parseable version,
#   - fails cleanly (rc != 0, actionable message) when the binary is missing.

run_test() {
    require_cmd timeout "ai-server status runs" || return 0

    local sandbox stubs
    sandbox="$(mksandbox ai-llama-detect)"
    stubs="$sandbox/stubs"
    mkdir -p "$stubs"

    # stub systemctl: everything inactive/disabled; nvidia-smi: no GPU →
    # deterministic CPU path.
    cat > "$stubs/systemctl" <<'STUB'
#!/usr/bin/env bash
# any subcommand: act like service is inactive/disabled
exit 1
STUB
    cat > "$stubs/nvidia-smi" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    cat > "$stubs/llama-server" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) echo "llama.cpp build 1.2.3 (abcdef)" ;;
    --help)    echo "usage: llama-server [options]" ;;
esac
STUB
    chmod +x "$stubs/systemctl" "$stubs/nvidia-smi" "$stubs/llama-server"

    local server="$ROOT/bin/pos-ai-server"
    local env_base=(PATH="$stubs:/usr/bin:/bin" USER_SYSTEMD_DIR="$sandbox/userunits")

    # 1. version detected from `--version`
    test_run_env "${env_base[@]}" -- timeout 20 "$server" status
    check_rc "status exits 0" 0 "$TR_RC"
    check_contains "detects stub version 1.2.3" "1.2.3" "$TR_OUT"
    check_contains "reports CPU backend (no GPU)" "gpu:       CPU" "$TR_OUT"
    check_not_contains "no GPU layers offload on CPU-only box" "gpu:       GPU" "$TR_OUT"

    # 2. version not parseable → "unknown" (never a lie / never a crash)
    cat > "$stubs/llama-server" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) echo "custom llama build" ;;
    --help)    echo "usage: llama-server [options]" ;;
esac
STUB
    chmod +x "$stubs/llama-server"
    test_run_env "${env_base[@]}" -- timeout 20 "$server" status
    check_rc "status exits 0 with unparseable version" 0 "$TR_RC"
    check_contains "reports unknown version honestly" "unknown" "$TR_OUT"

    # 3. binary missing → clean, actionable failure (rc != 0, no hang)
    local nopath="$sandbox/nopath"
    mkdir -p "$nopath"
    cp "$stubs/systemctl" "$nopath/systemctl"
    cp "$stubs/nvidia-smi" "$nopath/nvidia-smi"
    chmod +x "$nopath/systemctl" "$nopath/nvidia-smi"
    test_run_env PATH="$nopath:/usr/bin:/bin" USER_SYSTEMD_DIR="$sandbox/userunits" -- timeout 20 "$server" status
    check_contains "missing-binary status fails" "llama-server" "$TR_OUT"
    check_contains "missing-binary error is actionable" "not found" "$TR_OUT"
    # rc must be nonzero OR the message must clearly refuse (fail-closed)
    if [ "$TR_RC" -eq 0 ]; then
        printf '  FAIL  status rc nonzero when llama-server missing (got rc 0)\n'
    else
        printf '  PASS  status rc nonzero when llama-server missing\n'
    fi
}