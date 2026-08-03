#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_qemu() {
    command -v qemu-system-x86_64 &>/dev/null && { log "qemu already installed"; return 0; }

    spawn "Installing qemu and libvirt" sudo apt install -y \
        qemu-system qemu-utils qemu-kvm \
        libvirt-daemon-system libvirt-clients \
        bridge-utils virt-manager

    spawn "Adding user to libvirt group" sudo usermod -aG libvirt "$USER"
    spawn "Adding user to kvm group" sudo usermod -aG kvm "$USER"
    warn "Log out and back in for libvirt/kvm groups to take effect"
}

uninstall_qemu() {
    command -v qemu-system-x86_64 &>/dev/null || { log "qemu not installed"; return 0; }
    spawn "Removing qemu and libvirt" sudo apt purge -y \
        qemu-system qemu-utils qemu-kvm \
        libvirt-daemon-system libvirt-clients \
        bridge-utils virt-manager
    spawn "Cleaning up dependencies" sudo apt autoremove -y
}

case "${1:-}" in
    uninstall) uninstall_qemu ;;
    *) install_qemu ;;
esac
