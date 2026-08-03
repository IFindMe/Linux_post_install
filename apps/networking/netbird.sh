#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_netbird() {
    command -v netbird &>/dev/null && { log "netbird already installed"; return 0; }

    spawn "Installing netbird" bash -c "
        curl -fsSL https://pkgs.netbird.io/install.sh | sh
    "
    log "Join a network: sudo netbird up --setup-key <key>"
}

uninstall_netbird() {
    command -v netbird &>/dev/null || { log "netbird not installed"; return 0; }
    spawn "Removing netbird" sudo apt purge -y netbird
    spawn "Cleaning up dependencies" sudo apt autoremove -y
    spawn "Removing netbird apt repo" sudo rm -f /etc/apt/sources.list.d/netbird.list
}

case "${1:-}" in
    uninstall) uninstall_netbird ;;
    *) install_netbird ;;
esac
