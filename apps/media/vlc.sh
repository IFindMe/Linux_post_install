#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_vlc() {
    command -v vlc &>/dev/null && { log "vlc already installed"; return 0; }
    spawn "Installing vlc" sudo apt install -y vlc
}

install_vlc
