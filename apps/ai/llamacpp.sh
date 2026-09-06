#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

# llama.cpp — Local LLM inference server (llama-server) + CLI tools.
#
# Asset-naming note (probed live 2026-09-06): the vX.Y.Z milestone
# releases carry NO binary assets (only nightly-tag.txt); the prebuilt
# Ubuntu binaries ship on the nightly bNNNNN releases as
#   llama-<tag>-bin-ubuntu-x64.tar.gz    /    llama-<tag>-bin-ubuntu-arm64.tar.gz
# so we scan the newest releases for the first one that ships our arch
# instead of hitting /releases/latest.
RELEASES_URL="https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=10"

# Test seam for the post-install sanity (defaults to the real install target);
# PATH must still contain the dir for the `command -v` check.
LLAMACPP_BIN_DIR="${LLAMACPP_BIN_DIR:-/usr/local/bin}"

# Post-install sanity (F7): fail fast on a genuinely broken install — missing
# shared lib (binary won't execute) or a truncated archive (dangling symlink) —
# with one clear err, instead of "version unknown / flags rejected" on the
# first `pos ai server start`.
llamacpp_sanity() {
    local bin="$LLAMACPP_BIN_DIR/llama-server"
    [ -e "$bin" ] \
        || err "llama.cpp install sanity failed: $bin is missing or a dangling symlink (truncated archive?)"
    command -v llama-server >/dev/null 2>&1 \
        || err "llama.cpp install sanity failed: llama-server not on PATH — check that $LLAMACPP_BIN_DIR is in PATH"
    # llama.cpp prints --version to STDERR (common/build-info.h), so 2>&1 is
    # required to actually exercise the stream the tool chain reads.
    llama-server --version >/dev/null 2>&1 \
        || err "llama.cpp install sanity failed: 'llama-server --version' did not run — missing shared library or truncated archive"
    llama-server --help >/dev/null 2>&1 \
        || err "llama.cpp install sanity failed: 'llama-server --help' did not run — missing shared library or truncated archive"
    log "llama.cpp sanity OK — llama-server runs (version/help readable, symlink target present)"
}

install_llamacpp() {
    command -v llama-server &>/dev/null && { log "llama.cpp already installed"; return 0; }

    local arch
    case "$(uname -m)" in
        x86_64)  arch="x64" ;;
        aarch64) arch="arm64" ;;
        *) err "Unsupported architecture: $(uname -m) (llama.cpp publishes x64/arm64 Ubuntu builds)" ;;
    esac

    spawn "Fetching latest llama.cpp release info" bash -c "
        curl -fsSL '$RELEASES_URL' -o /tmp/llamacpp-releases.json
    "

    local tag asset_url
    if ! { read -r tag && read -r asset_url; } < <(python3 -c "
import json, sys
rels = json.load(open('/tmp/llamacpp-releases.json'))
suffix = '-bin-ubuntu-$arch.tar.gz'
for r in rels:
    for a in r['assets']:
        if a['name'].endswith(suffix):
            print(r['tag_name'])
            print(a['browser_download_url'])
            sys.exit(0)
sys.exit(1)
" 2>/dev/null); then
        rm -f /tmp/llamacpp-releases.json
        err "No llama.cpp Ubuntu $arch binary release found — see https://github.com/ggml-org/llama.cpp/releases"
    fi

    spawn "Installing llama.cpp $tag ($arch)" bash -c "
        install_dir=/usr/local/lib/llama.cpp-$tag
        curl -fsSL '$asset_url' -o /tmp/llamacpp.tar.gz
        sudo rm -rf \$install_dir
        sudo mkdir -p \$install_dir
        sudo tar xzf /tmp/llamacpp.tar.gz -C \$install_dir --strip-components=1
        for bin in \$install_dir/llama*; do
            [ -f \"\$bin\" ] && [ -x \"\$bin\" ] || continue
            sudo ln -sf \"\$bin\" /usr/local/bin/\$(basename \"\$bin\")
        done
        rm -f /tmp/llamacpp.tar.gz /tmp/llamacpp-releases.json
    "

    llamacpp_sanity

    log "llama.cpp $tag installed — run the server with 'pos ai server start <model.gguf>'"
}

uninstall_llamacpp() {
    command -v llama-server &>/dev/null || { log "llama.cpp not installed"; return 0; }

    spawn "Removing llama.cpp files" sudo rm -rf /usr/local/lib/llama.cpp-*

    # Remove only the symlinks we created (targets inside the install dir);
    # unrelated /usr/local/bin/llama* files are left alone.
    spawn "Removing llama.cpp symlinks" bash -c "
        for link in /usr/local/bin/llama*; do
            [ -L \"\$link\" ] || continue
            target=\$(readlink \"\$link\")
            case \"\$target\" in
                /usr/local/lib/llama.cpp-*) sudo rm -f \"\$link\" ;;
            esac
        done
    "

    log "llama.cpp removed"
}

case "${1:-}" in
    uninstall) uninstall_llamacpp ;;
    *)         install_llamacpp ;;
esac