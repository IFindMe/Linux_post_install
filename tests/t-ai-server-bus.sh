#!/usr/bin/env bash
set -euo pipefail
# t-ai-server-bus.sh — F4 + E2E regression for the user systemd-bus pre-flight.
#
# F4 contract:
#   - `pos ai server start` (unit path) calls ensure_user_bus BEFORE the unit
#     is written; with no user bus (SSH/headless: XDG_RUNTIME_DIR and
#     DBUS_SESSION_BUS_ADDRESS unset, systemctl --user fails) it errs with BOTH
#     remediation lines and leaves NO orphaned unit file.
#   - with a reachable bus the command proceeds past the pre-flight.
#   - `--no-unit` is the bus-less escape hatch: it skips the pre-flight, runs
#     llama-server directly under nohup with a pidfile, and stop/status can
#     find it via the pidfile.
#
# E2E regression (the reported user scenario):
#   - install-shaped stubs + working bus: `start Qwen-Qwen3-1.7B-GGUF` resolves
#     the model dir (F3), writes a correct unit (F6: all 5 flags + --port
#     8088), reports a resolvable version (F1: 0.4.0, not "unknown"), and the
#     unit passes `systemd-analyze verify`.
#   - SSH-shaped no-bus env: clean pre-flight err, remediation lines, NO unit.

run_test() {
    local sandbox stubs models unitdir runtime
    sandbox="$(mksandbox ai-server-bus)"
    stubs="$sandbox/stubs"
    models="$sandbox/models"
    unitdir="$sandbox/userunits"
    runtime="$sandbox/runtime"
    mkdir -p "$stubs" "$models" "$unitdir" "$runtime"

    # ── User's real HF layout (F3 fixture) ──
    mkdir -p "$models/Qwen-Qwen3-1.7B-GGUF"
    touch "$models/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf"

    # ── Stubs ──
    # llama-server: b10822-shaped (version → stderr, full-support help).
    cat > "$stubs/llama-server" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) printf 'version: 0.4.0-dev (build 10822, commit c457e3bf7)\n' >&2 ;;
    --help)
        cat <<'HELP'
usage: llama-server [options]
options:
  --host <addr>        bind address
  --port <port>        server port
  --n-gpu-layers <n>   layers to offload
  --ctx-size <n>       context size
  --threads <n>        cpu threads
HELP
        ;;
    *) exit 0 ;;
esac
STUB
    # systemctl: FAILS exactly like the real bus-missing case (SSH).
    cat > "$stubs/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "Failed to connect to user scope bus via local transport: \$DBUS_SESSION_BUS_ADDRESS and \$XDG_RUNTIME_DIR not defined" >&2
exit 1
STUB
    # nvidia-smi: no GPU → deterministic CPU path.
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/nvidia-smi"
    # curl: healthy JSON (health + models probes).
    printf '#!/usr/bin/env bash\nprintf "%%s" '"'"'{"status":"ok"}'"'"'\n' > "$stubs/curl"
    # loginctl: Linger=no (so the linger warn path is deterministic).
    printf '#!/usr/bin/env bash\nprintf "Linger=no\\n"\n' > "$stubs/loginctl"
    chmod +x "$stubs/llama-server" "$stubs/systemctl" "$stubs/nvidia-smi" "$stubs/curl" "$stubs/loginctl"

    local server="$ROOT/bin/pos-ai-server"
    local nobus_env=(-u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS
        PATH="$stubs:/usr/bin:/bin" HF_DOWNLOAD_DIR="$models"
        USER_SYSTEMD_DIR="$unitdir" NO_UNIT_PIDFILE="$sandbox/pos-ai-server.pid"
        NO_UNIT_LOG="$sandbox/pos-ai-server.log")
    local bus_env=(-u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS
        PATH="$stubs:/usr/bin:/bin" HF_DOWNLOAD_DIR="$models"
        USER_SYSTEMD_DIR="$unitdir" XDG_RUNTIME_DIR="$runtime"
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus"
        NO_UNIT_PIDFILE="$sandbox/pos-ai-server.pid" NO_UNIT_LOG="$sandbox/pos-ai-server.log")

    # ═══ F4 pre-flight: bus missing → err + remediation + NO unit ═══
    test_run_env "${nobus_env[@]}" -- timeout 30 "$server" start Qwen-Qwen3-1.7B-GGUF
    check_contains "F4 bus-missing start names the bus problem" "user systemd bus" "$TR_OUT"
    check_contains "F4 remediation: export XDG_RUNTIME_DIR" "export XDG_RUNTIME_DIR=/run/user/" "$TR_OUT"
    check_contains "F4 remediation: sudo loginctl enable-linger" "sudo loginctl enable-linger" "$TR_OUT"
    check_contains "F4 states no unit was written" "no unit was written" "$TR_OUT"
    [ "$TR_RC" -ne 0 ] && printf '  PASS  F4 bus-missing start exits nonzero\n' || printf '  FAIL  F4 bus-missing start exited 0\n'
    check_file_absent "F4 no orphaned unit written" "$unitdir/pos-ai-server.service"

    # ═══ F4 pre-flight: bus present → proceeds past pre-flight (DRY_RUN) ═══
    # Replace the failing systemctl with a succeeding one.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/systemctl"
    chmod +x "$stubs/systemctl"
    test_run_env "${bus_env[@]}" DRY_RUN=1 -- timeout 30 "$server" start Qwen-Qwen3-1.7B-GGUF
    check_rc "F4 bus-present DRY_RUN start exits 0" 0 "$TR_RC"
    check_contains "F4 bus-present proceeds past pre-flight (ExecStart)" "ExecStart:" "$TR_OUT"

    # ═══ F4 --no-unit escape hatch (bus-less direct run) ═══
    # A real --no-unit start must skip the bus check and launch the stub under
    # nohup with a pidfile; status finds it; stop kills it. The stub sleeps via
    # `exec sleep` so the recorded pid IS the sleeper (no orphan children).
    cat > "$stubs/llama-server" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) printf 'version: 0.4.0-dev (build 10822, commit c457e3bf7)\n' >&2 ;;
    --help)
        cat <<'HELP'
usage: llama-server [options]
options:
  --host <addr>        bind address
  --port <port>        server port
  --n-gpu-layers <n>   layers to offload
  --ctx-size <n>       context size
  --threads <n>        cpu threads
HELP
        ;;
    *) exec sleep 300 ;;
esac
STUB
    chmod +x "$stubs/llama-server"

    # failing systemctl stub again: --no-unit must NOT care.
    cat > "$stubs/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "no bus" >&2
exit 1
STUB
    chmod +x "$stubs/systemctl"

    test_run_env "${nobus_env[@]}" -- timeout 30 "$server" start Qwen-Qwen3-1.7B-GGUF --no-unit
    check_rc "F4 --no-unit bus-less start exits 0" 0 "$TR_RC"
    check_file_exists "F4 --no-unit writes pidfile" "$sandbox/pos-ai-server.pid"
    check_contains "F4 --no-unit prints log path hint" "log:" "$TR_OUT"
    local direct_pid
    direct_pid="$(cat "$sandbox/pos-ai-server.pid" 2>/dev/null || true)"
    if [[ "$direct_pid" =~ ^[0-9]+$ ]] && kill -0 "$direct_pid" 2>/dev/null; then
        printf '  PASS  F4 --no-unit launched a live server process (pid %s)\n' "$direct_pid"
    else
        printf '  FAIL  F4 --no-unit pid %s not alive\n' "${direct_pid:-EMPTY}"
    fi

    # status via the pidfile reports running (deps + curl stubs present).
    test_run_env "${nobus_env[@]}" -- timeout 30 "$server" status
    check_rc "F4 status exits 0 after --no-unit start" 0 "$TR_RC"
    check_contains "F4 status finds direct-run server running" "service:   running" "$TR_OUT"

    # stop kills the pid and removes the pidfile.
    test_run_env "${nobus_env[@]}" -- timeout 30 "$server" stop
    check_rc "F4 --no-unit stop exits 0" 0 "$TR_RC"
    check_file_absent "F4 stop removes pidfile" "$sandbox/pos-ai-server.pid"
    if [[ "$direct_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$direct_pid" 2>/dev/null; then
        printf '  PASS  F4 stop killed the direct-run process\n'
    else
        printf '  FAIL  F4 direct-run process still alive after stop\n'
    fi

    # ═══ E2E positive: user scenario with a working bus ═══
    # Restore full-support stub + succeeding systemctl.
    cat > "$stubs/llama-server" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    --version) printf 'version: 0.4.0-dev (build 10822, commit c457e3bf7)\n' >&2 ;;
    --help)
        cat <<'HELP'
usage: llama-server [options]
options:
  --host <addr>        bind address
  --port <port>        server port
  --n-gpu-layers <n>   layers to offload
  --ctx-size <n>       context size
  --threads <n>        cpu threads
HELP
        ;;
    *) exit 0 ;;
esac
STUB
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/systemctl"
    chmod +x "$stubs/llama-server" "$stubs/systemctl"

    test_run_env "${bus_env[@]}" -- timeout 60 "$server" start Qwen-Qwen3-1.7B-GGUF
    check_rc "E2E user scenario start exits 0" 0 "$TR_RC"
    check_file_exists "E2E unit written" "$unitdir/pos-ai-server.service"

    local unit="$unitdir/pos-ai-server.service"
    local unit_exec
    unit_exec="$(grep '^ExecStart=' "$unit")"
    check_contains "E2E unit: model expanded from dir" "Qwen3-1.7B-Q8_0.gguf" "$unit_exec"
    check_contains "E2E unit: --port 8088 pinned" "--port 8088" "$unit_exec"
    check_contains "E2E unit: --host present" "--host 127.0.0.1" "$unit_exec"
    check_contains "E2E unit: --n-gpu-layers present" "--n-gpu-layers 0" "$unit_exec"
    check_contains "E2E unit: --ctx-size present" "--ctx-size 4096" "$unit_exec"
    check_contains "E2E unit: --threads present" "--threads" "$unit_exec"

    # Version resolvable through the real CLI on the same run's stub.
    test_run_env "${bus_env[@]}" -- timeout 30 "$server" status
    check_contains "E2E version is resolvable (0.4.0)" "version:   0.4.0" "$TR_OUT"
    check_not_contains "E2E version is NOT unknown" "version:   unknown" "$TR_OUT"

    # Unit must pass systemd-analyze verify.
    if command -v systemd-analyze >/dev/null 2>&1; then
        test_run systemd-analyze verify "$unit"
        check_rc "E2E systemd-analyze verify accepts unit" 0 "$TR_RC"
    else
        skip_case "E2E systemd-analyze verify" "systemd-analyze not available"
    fi

    # stop cleans up (unit removed).
    test_run_env "${bus_env[@]}" -- timeout 30 "$server" stop
    check_rc "E2E stop exits 0" 0 "$TR_RC"
    check_file_absent "E2E stop removes unit" "$unitdir/pos-ai-server.service"

    # ═══ E2E SSH-shaped: no bus → clean pre-flight err, remediation, NO unit ═══
    cat > "$stubs/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "Failed to connect to user scope bus via local transport: \$DBUS_SESSION_BUS_ADDRESS and \$XDG_RUNTIME_DIR not defined" >&2
exit 1
STUB
    chmod +x "$stubs/systemctl"
    test_run_env "${nobus_env[@]}" -- timeout 30 "$server" start Qwen-Qwen3-1.7B-GGUF
    check_rc "E2E SSH-shaped start exits nonzero" 1 "$TR_RC"
    check_contains "E2E SSH-shaped: bus problem named" "user systemd bus" "$TR_OUT"
    check_contains "E2E SSH-shaped: export XDG_RUNTIME_DIR remediation" "export XDG_RUNTIME_DIR=/run/user/" "$TR_OUT"
    check_contains "E2E SSH-shaped: loginctl enable-linger remediation" "sudo loginctl enable-linger" "$TR_OUT"
    check_contains "E2E SSH-shaped: no unit was written" "no unit was written" "$TR_OUT"
    check_file_absent "E2E SSH-shaped: no orphaned unit" "$unitdir/pos-ai-server.service"
}