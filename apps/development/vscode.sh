#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_vscode() {
    command -v code &>/dev/null && { log "vscode already installed"; return 0; }

    spawn "Adding vscode apt repo" bash -c "
        sudo curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
            | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
        echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main' \
            | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    "
    spawn "Updating apt" sudo apt update -qq
    spawn "Installing code" sudo apt install -y code
}

install_vscode
