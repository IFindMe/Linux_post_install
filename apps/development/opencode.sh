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

install_opencode
