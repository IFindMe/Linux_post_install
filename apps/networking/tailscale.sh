#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_tailscale() {
    command -v tailscale &>/dev/null && { log "tailscale already installed"; return 0; }

    spawn "Installing tailscale" bash -c "
        curl -fsSL https://tailscale.com/install.sh | sh
    "
    log "Start tailscale: sudo tailscale up"
}

uninstall_tailscale() {
    command -v tailscale &>/dev/null || { log "tailscale not installed"; return 0; }
    spawn "Removing tailscale" sudo apt purge -y tailscale
    spawn "Cleaning up dependencies" sudo apt autoremove -y
    spawn "Removing tailscale apt repo" sudo rm -f /etc/apt/sources.list.d/tailscale.list /usr/share/keyrings/tailscale-archive-keyring.gpg
}

case "${1:-}" in
    uninstall) uninstall_tailscale ;;
    *) install_tailscale ;;
esac
