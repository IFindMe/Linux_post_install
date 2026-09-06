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