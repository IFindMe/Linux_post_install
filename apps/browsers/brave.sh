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

install_brave
