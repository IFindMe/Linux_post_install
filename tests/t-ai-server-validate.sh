#!/usr/bin/env bash
set -euo pipefail
# t-ai-server-validate.sh — F1/F2/F5/F6 regression for `pos ai server`:
#   F1 detect_llama_version reads llama.cpp's version string from STDERR
#      (real builds print `version: 0.4.0-dev (build 10822, …)` to stderr),
#      and falls back to "unknown" (no errexit) when unreadable/missing.
#   F2 flag validation is pipe-less (no printf|grep -q SIGPIPE/rc=141 race):
#      validate_default_flags / validate_requested_flags are deterministic —
#      all 5 defaults kept every run on a real-shaped ~59 KB help, and a
#      requested flag is always accepted/rejected the same way.
#   F5 find_llamacpp no longer matches an unrelated bare `server` binary.
#   F6 --port $PORT (and the 4 other defaults) always appear in ExecStart.
#
# Strategy: F1/F5/F2-internals call the REAL shipped functions directly
# (brace-matching extraction, so production logic is never re-typed); F6
# exercises the full CLI with the real-shaped help fixture.

# extract_fn <source-file> <fnname> — print one brace-delimited function body.
# Used to unit-test a self-contained function that lives in a thick script
# whose dispatch we must not trigger.
extract_fn() {
    local file="$1" fn="$2"
    awk -v fn="$fn" '
        BEGIN { found=0; depth=0 }
        {
            if (!found && $0 ~ ("^" fn "\\(\\)")) { found=1; depth=0 }
            if (found) {
                n_open  = gsub(/\{/, "{")
                n_close = gsub(/\}/, "}")
                depth = depth + n_open - n_close
                print
                if (depth <= 0) exit
            }
        }
    ' "$file"
}

# ── F1/F2 help fixture: 732-line ~59 KB body carrying the 5 defaults at the
#    REAL llama.cpp line offsets (7/25/140/503/506) — the shape that used to
#    trip the printf|grep -q SIGPIPE race under pipefail.
build_real_help() {
    local total=732 i
    for ((i = 1; i <= total; i++)); do
        case "$i" in
            7)   printf '%s\n' '  -t,    --threads N' ;;
            25)  printf '%s\n' '  -c,    --ctx-size N' ;;
            140) printf '%s\n' ' -ngl,  --gpu-layers, --n-gpu-layers N' ;;
            503) printf '%s\n' '--host HOST' ;;
            506) printf '%s\n' '--port PORT' ;;
            *)
                if [ "$i" -le 2 ]; then
                    printf 'usage: llama-server [options]\n'
                else
                    printf '  --general-option-%04d <arg>      example option number %d with a longish description\n' "$i" "$i"
                fi
                ;;
        esac
    done
}

new_stub() { # new_stub <dir> — full-support llama-server stub (stderr version)
    local dir="$1" help_fixture
    help_fixture="$(build_real_help)"
    cat > "$dir/llama-server" <<STUB
#!/usr/bin/env bash
case "\$1" in
    --version) printf 'version: 0.4.0-dev (build 10822, commit c457e3bf7)\n' >&2 ;;
    --help)
        cat <<'EOF_HELP'
$help_fixture
EOF_HELP
        ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "$dir/llama-server"
}

run_test() {
    source "$ROOT/lib/common.sh"   # err/warn/log for the extracted functions

    local sandbox stubs
    sandbox="$(mksandbox ai-server-validate)"
    stubs="$sandbox/stubs"
    mkdir -p "$stubs"

    local aid="$ROOT/bin/pos-ai-server"
    local fn_file="$sandbox/fns.sh"

    # ═══ F1: detect_llama_version (STDERR capture + "unknown" guard) ═══
    extract_fn "$aid" detect_llama_version > "$fn_file"
    source "$fn_file"

    cat > "$stubs/f1-stderr" <<'STUB'
#!/usr/bin/env bash
printf 'version: 0.4.0-dev (build 10822, commit c457e3bf7)\n' >&2
STUB
    chmod +x "$stubs/f1-stderr"
    test_run detect_llama_version "$stubs/f1-stderr"
    check_rc "F1 stderr semver -> rc 0" 0 "$TR_RC"
    check_eq "F1 stderr semver resolved (not unknown)" "0.4.0" "$TR_OUT"

    cat > "$stubs/f1-build" <<'STUB'
#!/usr/bin/env bash
printf 'version: build 10822\n' >&2
STUB
    chmod +x "$stubs/f1-build"
    test_run detect_llama_version "$stubs/f1-build"
    check_rc "F1 build-only -> rc 0" 0 "$TR_RC"
    check_eq "F1 build 10822 -> 10822" "10822" "$TR_OUT"

    cat > "$stubs/f1-b" <<'STUB'
#!/usr/bin/env bash
printf 'version: b10822\n' >&2
STUB
    chmod +x "$stubs/f1-b"
    test_run detect_llama_version "$stubs/f1-b"
    check_eq "F1 b10822 -> b10822" "b10822" "$TR_OUT"

    # missing binary → "unknown", rc 0, NO errexit.
    test_run detect_llama_version "$sandbox/does-not-exist-llama-server"
    check_rc "F1 missing binary -> rc 0 (no errexit)" 0 "$TR_RC"
    check_eq "F1 missing binary -> unknown" "unknown" "$TR_OUT"

    # binary exists but --version prints nothing parseable → unknown.
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/f1-noop"
    chmod +x "$stubs/f1-noop"
    test_run detect_llama_version "$stubs/f1-noop"
    check_eq "F1 unreadable version -> unknown" "unknown" "$TR_OUT"

    # ═══ F5: find_llamacpp candidate narrowing ═══
    extract_fn "$aid" find_llamacpp > "$fn_file"
    source "$fn_file"

    local onlyserver="$sandbox/onlyserver"
    mkdir -p "$onlyserver"
    ln -s /usr/bin/false "$onlyserver/server"
    (
        PATH="$onlyserver:/usr/bin:/bin"
        test_run find_llamacpp
        printf '%s' "$TR_RC" > "$sandbox/f5.rc"
        printf '%s' "$TR_OUT" > "$sandbox/f5.out"
    )
    check_rc "F5 bare 'server' alone NOT found (rc != 0)" 1 "$(cat "$sandbox/f5.rc")"
    check_eq "F5 'server' candidate yields nothing" "" "$(cat "$sandbox/f5.out")"

    # llama-server IS a legitimate candidate; found first (rc 0 name).
    local havebin="$sandbox/havebin"
    mkdir -p "$havebin"
    new_stub "$havebin"
    (
        PATH="$havebin:/usr/bin:/bin"
        test_run find_llamacpp
        printf '%s' "$TR_RC" > "$sandbox/f5b.rc"
        printf '%s' "$TR_OUT" > "$sandbox/f5b.out"
    )
    check_rc "F5 llama-server present -> found (rc 0)" 0 "$(cat "$sandbox/f5b.rc")"
    check_eq "F5 returns llama-server (not server)" "llama-server" "$(cat "$sandbox/f5b.out")"

    # ═══ F2: deterministic flag validation (pipe-less, no rc=141) ═══
    # Extract both validation functions; they use err/warn from common.sh.
    {
        extract_fn "$aid" validate_requested_flags
        extract_fn "$aid" validate_default_flags
    } > "$fn_file"
    local com="$ROOT/lib/common.sh"

    # Default-flag determinism: 25 runs over the real-shaped help; every run
    # must keep all 5 defaults (the pre-fix SIGPIPE race dropped a random
    # subset per run). Run in a subshell sourcing the exact function bodies +
    # common.sh, capturing the globals it sets.
    local run stable=1 gvals run_rc
    for run in $(seq 1 25); do
        gvals="$(bash -c "
            source '$com'
            source '$fn_file'
            validate_default_flags '$havebin/llama-server' 0.4.0 ''
            printf '%s|%s|%s|%s|%s' \"\${DEFAULT_PORT_OK}\" \"\${DEFAULT_HOST_OK}\" \\
                \"\${DEFAULT_GPU_OK}\" \"\${DEFAULT_CTX_OK}\" \"\${DEFAULT_THREADS_OK}\"
        " 2>/dev/null)"
        run_rc=$?
        if [ "$run_rc" -ne 0 ]; then
            stable=0
            printf '  FAIL  F2 default-flag validation run %s: whole invocation rc=%s (possible rc=141 SIGPIPE component)\n' "$run" "$run_rc"
            break
        fi
        if [ "$gvals" != "1|1|1|1|1" ]; then
            stable=0
            printf '  FAIL  F2 run %s dropped a default (globals=%s)\n' "$run" "$gvals"
            break
        fi
    done
    [ "$stable" -eq 1 ] && printf '  PASS  F2 validate_default_flags keeps all 5 defaults across 25 pipefail runs (whole-invocation rc=0 every run)\n'

    # Requested-flag determinism (20+ runs each): supported always rc 0,
    # unsupported always hard-errors (never a flaky pass).
    local ok=0 bad=0
    for run in $(seq 1 20); do
        if bash -c "source '$com'; source '$fn_file'; validate_requested_flags '$havebin/llama-server' 0.4.0 --port" 2>/dev/null; then
            ok=$((ok + 1))
        fi
        if bash -c "source '$com'; source '$fn_file'; validate_requested_flags '$havebin/llama-server' 0.4.0 --tensor-split 1" 2>/dev/null; then
            bad=$((bad + 1))
        fi
    done
    check_eq "F2 requested supported --port accepted every run" 20 "$ok"
    check_eq "F2 no flaky pass on unsupported requested flag" 0 "$bad"

    test_run bash -c "source '$com'; source '$fn_file'; validate_requested_flags '$havebin/llama-server' 0.4.0 --tensor-split 1"
    check_rc "F2 unsupported requested flag exits 1" 1 "$TR_RC"
    check_contains "F2 unsupported requested flag names it" "--tensor-split" "$TR_OUT"
    check_contains "F2 unsupported requested flag is version-aware" "0.4.0" "$TR_OUT"

    # ═══ F6: full CLI — port pinning + version not "unknown" ═══
    local models="$sandbox/models"
    mkdir -p "$models"
    touch "$models/my-model.gguf"
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/nvidia-smi"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/systemctl"
    # curl stub: fail-fast probe so a future config leak can't stall the suite
    # (~20s per real probe to a filtered IP). Returns healthy JSON.
    printf '#!/usr/bin/env bash\nprintf "%%s" '"'"'{"status":"ok"}'"'"'\n' > "$stubs/curl"
    chmod +x "$stubs/nvidia-smi" "$stubs/systemctl" "$stubs/curl"

    # Hermetic config seam (isolation): live ~/.config/.../ai.env pins
    # LLAMACPP_HOST/PORT via flags>env>file precedence; sandbox CONFIG_FILE
    # keeps the 8088/127.0.0.1 default asserts hermetic.
    local empty_env="$sandbox/empty.env"
    : > "$empty_env"

    local server="$ROOT/bin/pos-ai-server"
    local base_env=(-u LLAMACPP_PORT -u LLAMACPP_HOST
        PATH="$havebin:$stubs:/usr/bin:/bin" DRY_RUN=1
        CONFIG_FILE="$empty_env"
        USER_SYSTEMD_DIR="$sandbox/userunits")
    test_run_env "${base_env[@]}" -- "$server" start "$models/my-model.gguf"
    check_rc "F6 DRY_RUN start exits 0" 0 "$TR_RC"
    local exec_line
    exec_line="$(printf '%s\n' "$TR_OUT" | grep 'dry-run) ExecStart:' | sed 's/.*ExecStart: //')"
    check_contains "F6 --port 8088 pinned in ExecStart" "--port 8088" "$exec_line"
    check_contains "F6 --host present" "--host 127.0.0.1" "$exec_line"
    check_contains "F6 --n-gpu-layers present" "--n-gpu-layers 0" "$exec_line"
    check_contains "F6 --ctx-size present" "--ctx-size 4096" "$exec_line"
    check_contains "F6 --threads present" "--threads" "$exec_line"

    # Version via the same b10822-shaped stub: status shows 0.4.0, never
    # "unknown" (F1 proven through the real CLI on a real-shaped build).
    # timeout: fail-fast guard so a future leak stalls seconds, not minutes.
    test_run_env "${base_env[@]}" -- timeout 10 "$server" status
    check_rc "F1 CLI status exits 0" 0 "$TR_RC"
    check_contains "F1 CLI status resolves version 0.4.0" "version:   0.4.0" "$TR_OUT"
    check_not_contains "F1 CLI status version is NOT unknown" "version:   unknown" "$TR_OUT"
}
