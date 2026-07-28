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

install_zerotier
