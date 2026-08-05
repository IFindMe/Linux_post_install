#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_tsui() {
    command -v tsui &>/dev/null && { log "tsui already installed"; return 0; }

    spawn "Installing tsui" bash -c "
        curl -fsSL https://neuralink.com/tsui/install.sh | bash
    "
    log "Run tsui: sudo tsui"
}

uninstall_tsui() {
    command -v tsui &>/dev/null || { log "tsui not installed"; return 0; }
    spawn "Removing tsui" sudo rm -f /usr/local/bin/tsui
}

case "${1:-}" in
    uninstall) uninstall_tsui ;;
    *) install_tsui ;;
esac
