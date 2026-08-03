#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_zerotier() {
    command -v zerotier-one &>/dev/null && { log "zerotier already installed"; return 0; }

    spawn "Installing zerotier" bash -c "
        curl -s https://install.zerotier.com | sudo bash
    "
    log "Join a network: sudo zerotier-cli join <network-id>"
}

uninstall_zerotier() {
    command -v zerotier-one &>/dev/null || { log "zerotier not installed"; return 0; }
    spawn "Removing zerotier" sudo apt purge -y zerotier-one
    spawn "Cleaning up dependencies" sudo apt autoremove -y
    spawn "Removing zerotier apt repo" sudo rm -f /etc/apt/sources.list.d/zerotier.list
}

case "${1:-}" in
    uninstall) uninstall_zerotier ;;
    *) install_zerotier ;;
esac
