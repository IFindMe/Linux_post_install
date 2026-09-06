#!/usr/bin/env bash
set -euo pipefail
# t-ai-hf-download.sh — `pos ai hf download` single-file path (D-C layout):
#   - success: target file + .hf-meta written, rc 0, honest summary line;
#   - failure: "Failed to download", NO .hf-meta (incomplete model is never
#     advertised as complete), rc != 0, honest (0 of N files) summary.
# curl is stubbed (no network): /tree/ + /models/ APIs return canned JSON,
# /resolve/ writes content or fails via HF_FAIL_DOWNLOAD.

run_test() {
    require_cmd jq "ai hf download" || return 0
    require_cmd timeout "ai hf download" || return 0

    local sandbox stubs dl tree_resp
    sandbox="$(mksandbox ai-hf-download)"
    stubs="$sandbox/stubs"
    dl="$sandbox/models"
    mkdir -p "$stubs" "$dl"

    local tree_resp="$sandbox/tree.json"
    printf '%s' '[{"type":"file","path":"model.gguf","size":12345}]' > "$tree_resp"

    cat > "$stubs/curl" <<STUB
#!/usr/bin/env bash
out=""
has_w=0
i=1
for (( ; i<=\$#; i++ )); do
    arg="\${!i}"
    case "\$arg" in
        -w) has_w=1 ;;
        -o|-D)
            n=\$((i+1))
            val="\${!n}"
            if [ "\$arg" = "-o" ]; then out="\$val"; else : > "\$val"; fi
            ;;
    esac
done
url="\${@: -1}"
case "\$url" in
    *"/tree/"*)
        [ "\$has_w" -eq 1 ] && printf '200'
        cat "\$TREE_RESP" > "\$out"
        ;;
    *"/models/"*)
        [ "\$has_w" -eq 1 ] && printf '200'
        printf '%s' '{"defaultBranch":null}' > "\$out"
        ;;
    *"/resolve/"*)
        if [ "\${HF_FAIL_DOWNLOAD:-0}" = "1" ]; then
            exit 1
        fi
        printf 'stub model binary content\n' > "\$out"
        ;;
    *)
        [ "\$has_w" -eq 1 ] && printf '200'
        ;;
esac
STUB
    chmod +x "$stubs/curl"

    local tool="$ROOT/bin/pos-ai-hf"
    local env_base=(PATH="$stubs:/usr/bin:/bin" HF_DOWNLOAD_DIR="$dl" TREE_RESP="$tree_resp")

    # ── 1. success ──
    test_run_env "${env_base[@]}" -- timeout 60 "$tool" download ns/test-model model.gguf
    check_rc "download succeeds" 0 "$TR_RC"
    check_contains "success summary names file" "Downloaded: ns/test-model/model.gguf" "$TR_OUT"
    check_file_exists "target model downloaded" "$dl/ns-test-model/model.gguf"
    check_file_exists "metadata written on full success" "$dl/ns-test-model/.hf-meta"
    check_contains "metadata records repo" "ns/test-model" "$(cat "$dl/ns-test-model/.hf-meta")"

    # ── 2. download failure → no metadata, rc != 0 ──
    rm -rf "$dl/ns-test-model"
    test_run_env "${env_base[@]}" HF_FAIL_DOWNLOAD=1 -- timeout 60 "$tool" download ns/test-model model.gguf
    check_contains "failure warns per file" "Failed to download model.gguf" "$TR_OUT"
    check_contains "failure refuses to write metadata" "Not writing .hf-meta" "$TR_OUT"
    check_contains "failure summary is honest (0 of 1)" "0 of 1 files, 1 failed" "$TR_OUT"
    check_file_absent "no .hf-meta on partial failure" "$dl/ns-test-model/.hf-meta"
    if [ "$TR_RC" -ne 0 ]; then
        printf '  PASS  download failure exits nonzero\n'
    else
        printf '  FAIL  download failure exited 0\n'
    fi
}