#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_docker() {
    command -v docker &>/dev/null && { log "docker already installed"; return 0; }

    spawn "Installing docker engine" bash -c "
        curl -fsSL https://get.docker.com | sh
    "
    spawn "Adding user to docker group" sudo usermod -aG docker "$USER"
    warn "Log out and back in for docker group to take effect"
}

install_docker
