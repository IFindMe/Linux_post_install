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
    git curl wget aria2 vim nano tmux tree jq
    unzip zip rsync htop btop telnet
    net-tools iputils-ping traceroute tcpdump nmap
    openssh-client openssh-server ufw fail2ban
    nfs-common nfs-kernel-server
    samba cifs-utils smbclient
    hostapd dnsmasq iptables iw
    ca-certificates gnupg lsb-release
    lm-sensors smartmontools nvme-cli hdparm
    sysstat iotop atop vnstat
    python3 python3-pip rclone
    ffmpeg
    libqrencode4 libgtk-3-0 adb
    xdotool xclip
)

spawn "apt update" sudo apt update
log "Installing ${#PACKAGES[@]} packages (apt install -y):"
echo "    ${PACKAGES[*]}" | fold -s -w 80
spawn "Installing packages" sudo apt install -y "${PACKAGES[@]}"
# ── cpufreq tools ─────────────────────────────────────────────
# cpufrequtils (Ubuntu) was removed in Debian trixie+; linux-cpupower
# (Debian) is absent in older Ubuntu — they are mutually exclusive, so
# try each in turn and tolerate a miss (both = warn only, never fail).
for pkg in cpufrequtils linux-cpupower; do
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) would install $pkg (cpufreq tools)"
        break
    fi
    if sudo apt-get install -y "$pkg" >/dev/null 2>&1; then
        log "Installed $pkg (cpufreq tools)"
        break
    fi
    warn "no cpufreq package candidate ($pkg) — skipping, trying next"
done
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
