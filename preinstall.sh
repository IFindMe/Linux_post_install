#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/ui.sh"

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
        *) ui_die "Unknown option: $1" ;;
    esac
done

PACKAGES=(
    git curl wget vim nano tmux tree jq
    unzip zip rsync htop btop telnet
    net-tools iputils-ping traceroute tcpdump nmap
    openssh-client openssh-server ufw fail2ban
    hostapd dnsmasq iptables iw
    ca-certificates gnupg lsb-release
    lm-sensors smartmontools nvme-cli hdparm
    sysstat iotop atop vnstat
    python3 python3-pip
    libqrencode4 libgtk-3-0
    xdotool xclip
)

timer_start

ui_info "Updating package index"
ui_run_step "apt update" sudo apt update

ui_info "Installing ${#PACKAGES[@]} packages (apt install -y)"
if [ "${UI_DEBUG:-0}" -eq 1 ]; then
    ui_info "Package list: ${PACKAGES[*]}"
fi
ui_run_step "Installing ${#PACKAGES[@]} packages" sudo apt install -y "${PACKAGES[@]}"

# Report the verified count, not just the requested one.
if [ "${DRY_RUN:-0}" -ne 1 ] && command -v dpkg-query >/dev/null 2>&1; then
    installed_count=$(dpkg-query -W -f='${Status}\n' "${PACKAGES[@]}" 2>/dev/null |
        grep -c '^install ok installed$' || true)
    if [ "$installed_count" -eq "${#PACKAGES[@]}" ]; then
        ui_success "$installed_count packages installed"
    else
        ui_warning "$installed_count of ${#PACKAGES[@]} packages present — see UI_DEBUG=1 for apt output"
    fi
fi

# ── Optional dependencies: cpufreq tools ──────────────────────
# cpufrequtils (Ubuntu) was removed in Debian trixie+; linux-cpupower
# (Debian) is absent in older Ubuntu — they are mutually exclusive, so
# try each in turn and tolerate a miss (both = warn only, never fail).
for pkg in cpufrequtils linux-cpupower; do
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        ui_warning "(dry-run) would try optional dependency $pkg"
        break
    fi
    if ui_run_step --optional --reason "not available on this Debian/Ubuntu release" \
        "Installing optional $pkg" sudo apt-get install -y "$pkg"; then
        break
    fi
done
#spawn "add user to sudo list" usermod -aG sudo $USER

ui_info "Verifying installations..."
for cmd in git; do
    if command -v "$cmd" >/dev/null 2>&1; then
        version_line=$("$cmd" --version 2>/dev/null || true)
        if [ -n "$version_line" ]; then
            ui_info "$version_line"
        fi
    fi
done

if [ "${DRY_RUN:-0}" -eq 1 ]; then
    ui_info "(dry-run) Pre-install plan complete" "$(timer_stop)"
else
    ui_success "Pre-install complete" "$(timer_stop)"
fi
