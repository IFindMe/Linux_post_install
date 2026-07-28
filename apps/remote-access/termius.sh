#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_termius() {
    command -v termius &>/dev/null && { log "termius already installed"; return 0; }

    spawn "Downloading Termius .deb" bash -c "
        curl -fsSL -o /tmp/termius.deb 'https://www.termius.com/download/linux/Termius.deb'
    "

    spawn "Installing Termius" bash -c "
        sudo dpkg -i /tmp/termius.deb || sudo apt-get install -f -y
        rm -f /tmp/termius.deb
    "

    log "Termius installed — launch with 'termius'"
}

install_termius
