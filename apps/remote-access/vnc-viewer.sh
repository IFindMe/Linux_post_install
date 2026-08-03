#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_vnc_viewer() {
    command -v vncviewer &>/dev/null && { log "tigervnc-viewer already installed"; return 0; }
    spawn "Installing tigervnc-viewer" sudo apt install -y tigervnc-viewer
}

uninstall_vnc_viewer() {
    command -v vncviewer &>/dev/null || { log "tigervnc-viewer not installed"; return 0; }
    spawn "Removing tigervnc-viewer" sudo apt purge -y tigervnc-viewer
    spawn "Cleaning up dependencies" sudo apt autoremove -y
}

case "${1:-}" in
    uninstall) uninstall_vnc_viewer ;;
    *) install_vnc_viewer ;;
esac
