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

install_netbird
