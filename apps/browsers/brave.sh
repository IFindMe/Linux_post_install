#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_brave() {
    command -v brave-browser &>/dev/null && { log "brave already installed"; return 0; }

    spawn "Adding brave apt repo" bash -c "
        sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
            https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
        echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main' \
            | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
    "
    spawn "Installing brave-browser" sudo apt update -qq
    spawn "Installing brave-browser" sudo apt install -y brave-browser
}

uninstall_brave() {
    command -v brave-browser &>/dev/null || { log "brave not installed"; return 0; }
    spawn "Removing brave-browser" sudo apt purge -y brave-browser
    spawn "Cleaning up dependencies" sudo apt autoremove -y
    spawn "Removing brave apt repo" sudo rm -f /etc/apt/sources.list.d/brave-browser-release.list /usr/share/keyrings/brave-browser-archive-keyring.gpg
}

case "${1:-}" in
    uninstall) uninstall_brave ;;
    *) install_brave ;;
esac
