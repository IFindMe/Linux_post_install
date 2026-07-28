#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_btop() {
    command -v btop &>/dev/null && { log "btop already installed"; return 0; }
    spawn "Installing btop" sudo apt install -y btop
}

install_btop
