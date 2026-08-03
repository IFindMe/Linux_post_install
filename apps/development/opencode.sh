#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_opencode() {
    command -v opencode &>/dev/null && { log "opencode already installed"; return 0; }

    spawn "Installing opencode" bash -c "
        curl -fsSL https://opencode.ai/install | bash
    "
    spawn "source bashrc" source ~/.bashrc
    log "opencode installed to ~/.opencode/bin"
    log "Add to PATH: export PATH=\"\$HOME/.opencode/bin:\$PATH\""
}

uninstall_opencode() {
    [ -d "$HOME/.opencode" ] || { log "opencode not installed"; return 0; }
    spawn "Removing opencode" rm -rf "$HOME/.opencode"
    warn "Config/data remains in ~/.config/opencode — remove manually if desired"
}

case "${1:-}" in
    uninstall) uninstall_opencode ;;
    *) install_opencode ;;
esac
