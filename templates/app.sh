#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# TEMPLATE — new optional app installer
#
#  1. Copy:  cp templates/app.sh apps/<category>/<name>.sh
#     Categories: browsers, development, media, networking,
#     remote-access, system, utilities.
#  2. Fill in install_myapp() / uninstall_myapp() (rename to your app).
#  3. Docs:  add a row to the catalog table in DOC/APPS.md.
#
# Auto-appears in the `apps/install.sh` picker — no registration.
# Run as:   bash apps/install.sh <name>        (install)
#           bash apps/install.sh --uninstall <name>
# ────────────────────────────────────────────────────────────────

source "$(dirname "$0")/../../lib/common.sh"

install_myapp() {
    command -v myapp &>/dev/null && { log "myapp already installed"; return 0; }

    # Pick one method (see conventions below) and wrap it in spawn:
    spawn "Installing myapp" sudo apt install -y myapp

    log "Run myapp: myapp"
}

uninstall_myapp() {
    command -v myapp &>/dev/null || { log "myapp not installed"; return 0; }

    spawn "Removing myapp" sudo apt purge -y myapp
    spawn "Cleaning up dependencies" sudo apt autoremove -y
}

case "${1:-}" in
    uninstall) uninstall_myapp ;;
    *)         install_myapp ;;
esac

# ────────────────────────────────────────────────────────────────
# CONVENTIONS — pick the install method that fits:
#
#   APT package        sudo apt install -y myapp
#                      remove: sudo apt purge -y myapp + apt autoremove -y
#
#   Repo-based app     add the apt repo in install; in uninstall also
#                      remove the .list file and keyring:
#                      sudo rm -f /etc/apt/sources.list.d/myapp.list /usr/share/keyrings/...
#
#   Official script    spawn "Installing myapp" bash -c "curl -fsSL https://.../install.sh | sh"
#                      uninstall: remove the installed binary/files
#
#   Flatpak            sudo flatpak install -y flathub <app-id>
#                      remove: sudo flatpak uninstall -y <app-id>
#
#   .deb download      download to temp, sudo apt install -y ./file.deb
#
#   File/AppImage      install under /opt/<app>; in uninstall remove the
#                      files, symlinks, and desktop entries
#
#   usermod for groups sudo usermod -aG <group> "$USER" + print a
#                      re-login reminder
#
# Every app MUST be idempotent (guard install AND uninstall) and MUST
# provide uninstall_myapp() + the uninstall case dispatch above.
# ────────────────────────────────────────────────────────────────
