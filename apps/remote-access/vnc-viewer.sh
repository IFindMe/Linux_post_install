#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_vnc_viewer() {
    command -v vncviewer &>/dev/null && { log "tigervnc-viewer already installed"; return 0; }
    spawn "Installing tigervnc-viewer" sudo apt install -y tigervnc-viewer
}

install_vnc_viewer
