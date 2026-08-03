#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_btop() {
    command -v btop &>/dev/null && { log "btop already installed"; return 0; }
    spawn "Installing btop" sudo apt install -y btop
}

uninstall_btop() {
    command -v btop &>/dev/null || { log "btop not installed"; return 0; }
    spawn "Removing btop" sudo apt purge -y btop
    spawn "Cleaning up dependencies" sudo apt autoremove -y
}

case "${1:-}" in
    uninstall) uninstall_btop ;;
    *) install_btop ;;
esac
