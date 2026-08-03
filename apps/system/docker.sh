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

uninstall_docker() {
    command -v docker &>/dev/null || { log "docker not installed"; return 0; }

    local pkgs=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose-v2)
    local installed=()
    for p in "${pkgs[@]}"; do
        dpkg -s "$p" &>/dev/null && installed+=("$p")
    done
    if [ "${#installed[@]}" -gt 0 ]; then
        spawn "Removing docker engine" sudo apt purge -y "${installed[@]}"
        spawn "Cleaning up dependencies" sudo apt autoremove -y
    fi
    spawn "Removing docker apt repo" sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg
    warn "Docker data remains in /var/lib/docker — remove manually if desired"
}

case "${1:-}" in
    uninstall) uninstall_docker ;;
    *) install_docker ;;
esac
