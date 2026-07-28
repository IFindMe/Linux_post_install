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

install_tailscale
