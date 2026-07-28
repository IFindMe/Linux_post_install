#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_localsend() {
    if flatpak list 2>/dev/null | grep -q org.localsend.localsend_app; then
        log "localsend already installed"
        return 0
    fi

    if ! command -v flatpak &>/dev/null; then
        spawn "Installing flatpak" sudo apt install -y flatpak
    fi

    spawn "Adding flathub remote" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    spawn "Installing localsend" sudo flatpak install -y flathub org.localsend.localsend_app
}

install_localsend
