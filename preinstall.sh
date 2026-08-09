#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

DRY_RUN="${DRY_RUN:-0}"

usage() {
    cat <<EOF
Usage: preinstall.sh [OPTIONS]

Install system packages and tools.

Options:
  --dry-run    Show what would be done without executing
  -h, --help   Show this help message
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1" ;;
    esac
done

PACKAGES=(
    git curl wget vim nano tmux tree jq
    unzip zip rsync htop btop telnet
    net-tools iputils-ping traceroute tcpdump nmap
    openssh-client openssh-server ufw fail2ban
    nfs-common nfs-kernel-server
    hostapd dnsmasq iptables iw
    ca-certificates gnupg lsb-release
    lm-sensors smartmontools nvme-cli hdparm
    sysstat iotop atop cpufrequtils vnstat
    python3 python3-pip rclone
    libqrencode4 libgtk-3-0
)

spawn "apt update" sudo apt update
spawn "Installing packages" sudo apt install -y "${PACKAGES[@]}"
#spawn "add user to sudo list" usermod -aG sudo $USER
spawn "Installing yt-dlp" sudo curl -L \
    https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -o /usr/local/bin/yt-dlp
run sudo chmod a+rx /usr/local/bin/yt-dlp

log "Verifying installations..."
for cmd in git yt-dlp; do
    if command -v "$cmd" &>/dev/null; then
        run "$cmd" --version
    fi
done

log "Pre-install completed."
