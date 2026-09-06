#!/usr/bin/env bash
set -euo pipefail
# t-ai-server-model.sh — F3: `resolve_model` directory expansion regression.
# The HF downloader writes weights as `$HF_DOWNLOAD_DIR/<repo-slug>/<file>.gguf`,
# but the old resolve_model accepted only FILE paths, so the user's
# `pos ai server start Qwen-Qwen3-1.7B-GGUF` failed with "Model not found".
# F3 adds: dir with exactly one .gguf → resolve; multiple → err listing each
# as `<dir>/<file>` + "pick one"; zero → fall through to not-found. It also
# accepts the `<name>/<file>.gguf` slug/file form. Flat-file + absolute paths
# must keep working (backward compatibility).
#
# Unit level: call the REAL shipped resolve_model / resolve_gguf_in_dir with a
# sandbox HF_DOWNLOAD_DIR. Integration level: `start` DRY_RUN resolves the
# user's real dir name.

# extract_fn <source-file> <fnname> — print one brace-delimited function body.
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

run_test() {
    source "$ROOT/lib/common.sh"   # err/log for resolve_model

    local sandbox models aid
    sandbox="$(mksandbox ai-server-model)"
    models="$sandbox/models"
    mkdir -p "$models"
    aid="$ROOT/bin/pos-ai-server"

    # Extract the REAL model-resolution functions.
    local fn_file="$sandbox/fns.sh" com="$ROOT/lib/common.sh"
    {
        extract_fn "$aid" resolve_gguf_in_dir
        extract_fn "$aid" resolve_model
    } > "$fn_file"

    # ── Fixtures (mirror the user's real layout) ──
    # single-gguf dir (the reported case): Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf
    mkdir -p "$models/Qwen-Qwen3-1.7B-GGUF"
    touch "$models/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf"
    # multi-gguf dir
    mkdir -p "$models/multi"
    touch "$models/multi/q1.gguf" "$models/multi/q2.gguf"
    # empty dir
    mkdir -p "$models/empty"
    # flat-file legacy form
    touch "$models/flat.gguf"
    # absolute file
    touch "$models/abs.gguf"

    # ── F3 unit cases (direct function calls) ──
    # 1. single-gguf dir resolves to the inner file
    test_run_env HF_DOWNLOAD_DIR="$models" -- bash -c "source '$com'; source '$fn_file'; resolve_model 'Qwen-Qwen3-1.7B-GGUF'"
    check_rc "F3 single-gguf dir resolves (rc 0)" 0 "$TR_RC"
    check_eq "F3 resolves to inner gguf" "$models/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf" "$TR_OUT"

    # 2. multi-gguf dir errors listing each as <dir>/<file> + "pick one"
    test_run_env HF_DOWNLOAD_DIR="$models" -- bash -c "source '$com'; source '$fn_file'; resolve_model 'multi'"
    check_rc "F3 multi-gguf dir errors (rc 1)" 1 "$TR_RC"
    check_contains "F3 multi lists q1" "multi/q1.gguf" "$TR_OUT"
    check_contains "F3 multi lists q2" "multi/q2.gguf" "$TR_OUT"
    check_contains "F3 multi says pick one" "pick one" "$TR_OUT"

    # 3. zero-gguf dir → falls through to today's not-found
    test_run_env HF_DOWNLOAD_DIR="$models" -- bash -c "source '$com'; source '$fn_file'; resolve_model 'empty'"
    check_rc "F3 empty dir errors (rc 1)" 1 "$TR_RC"
    check_contains "F3 empty dir -> Model not found" "Model not found" "$TR_OUT"

    # 4. slug/file form <name>/<file>.gguf resolves
    test_run_env HF_DOWNLOAD_DIR="$models" -- bash -c "source '$com'; source '$fn_file'; resolve_model 'Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf'"
    check_rc "F3 slug/file form resolves (rc 0)" 0 "$TR_RC"
    check_eq "F3 slug/file resolves to inner gguf" "$models/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf" "$TR_OUT"

    # 5. flat-file legacy form still works
    test_run_env HF_DOWNLOAD_DIR="$models" -- bash -c "source '$com'; source '$fn_file'; resolve_model 'flat.gguf'"
    check_rc "F3 flat file resolves (rc 0)" 0 "$TR_RC"
    check_eq "F3 flat file stays flat (backward compat)" "$models/flat.gguf" "$TR_OUT"

    # 6. absolute file path still works
    test_run_env HF_DOWNLOAD_DIR="$models" -- bash -c "source '$com'; source '$fn_file'; resolve_model '$models/abs.gguf'"
    check_rc "F3 absolute file resolves (rc 0)" 0 "$TR_RC"
    check_eq "F3 absolute file unchanged" "$models/abs.gguf" "$TR_OUT"

    # ── F3 integration: `start <dir>` DRY_RUN resolves through the full CLI ──
    local stubs="$sandbox/stubs"
    mkdir -p "$stubs"
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
esac
STUB
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stubs/nvidia-smi"
    chmod +x "$stubs/llama-server" "$stubs/nvidia-smi"

    local server="$ROOT/bin/pos-ai-server"
    test_run_env PATH="$stubs:/usr/bin:/bin" DRY_RUN=1 \
        HF_DOWNLOAD_DIR="$models" USER_SYSTEMD_DIR="$sandbox/userunits" -- \
        "$server" start Qwen-Qwen3-1.7B-GGUF --no-unit
    check_rc "F3 CLI start with dir arg exits 0" 0 "$TR_RC"
    check_contains "F3 CLI resolves dir to inner file" \
        "-m \"$models/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf\"" "$TR_OUT"

    # multi-gguf via CLI → clean err naming pick-one, rc 1
    test_run_env PATH="$stubs:/usr/bin:/bin" DRY_RUN=1 \
        HF_DOWNLOAD_DIR="$models" USER_SYSTEMD_DIR="$sandbox/userunits" -- \
        "$server" start multi --no-unit
    check_rc "F3 CLI multi-gguf start errors (rc 1)" 1 "$TR_RC"
    check_contains "F3 CLI multi-gguf says pick one" "pick one" "$TR_OUT"
}
