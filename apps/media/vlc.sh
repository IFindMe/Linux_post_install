#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_vlc() {
    command -v vlc &>/dev/null && { log "vlc already installed"; return 0; }
    spawn "Installing vlc" sudo apt install -y vlc
}

uninstall_vlc() {
    command -v vlc &>/dev/null || { log "vlc not installed"; return 0; }
    spawn "Removing vlc" sudo apt purge -y vlc
    spawn "Cleaning up dependencies" sudo apt autoremove -y
}

case "${1:-}" in
    uninstall) uninstall_vlc ;;
    *) install_vlc ;;
esac
