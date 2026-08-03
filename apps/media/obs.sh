#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_obs() {
    command -v obs &>/dev/null && { log "obs-studio already installed"; return 0; }
    spawn "Installing obs-studio" sudo apt install -y obs-studio
}

uninstall_obs() {
    command -v obs &>/dev/null || { log "obs-studio not installed"; return 0; }
    spawn "Removing obs-studio" sudo apt purge -y obs-studio
    spawn "Cleaning up dependencies" sudo apt autoremove -y
}

case "${1:-}" in
    uninstall) uninstall_obs ;;
    *) install_obs ;;
esac
