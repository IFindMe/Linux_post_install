#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_obs() {
    command -v obs &>/dev/null && { log "obs-studio already installed"; return 0; }
    spawn "Installing obs-studio" sudo apt install -y obs-studio
}

install_obs
