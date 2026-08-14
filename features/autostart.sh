#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# autostart feature — tiny boot-time log marker.
#
# Installed on demand with:  ./install.sh --feature
#   → copied to /usr/local/bin/autostart.sh (chmod 755)
#   → flag "autostart" is set
# ────────────────────────────────────────────────────────────────

# Robust flags.sh load — works from the repo checkout AND from
# /usr/local/bin after install.sh (which copies lib/flags.sh there).
source "$(dirname "$0")/../lib/flags.sh" 2>/dev/null || source "$(dirname "$0")/flags.sh"

# Self-name → matches the flag install.sh sets for this feature.
FEATURE_NAME="$(basename "$0")"
FEATURE_NAME="${FEATURE_NAME%.sh}"

usage() {
    cat <<EOF
Usage: autostart.sh [options]

Boot-time connectivity marker — appends a timestamped Network:
online/offline line to ~/.autostart.log (idempotent, safe to run
repeatedly).

Installed via:  ./install.sh --feature
Flag:           ${FEATURE_NAME}
Log:            ${HOME:-/root}/.autostart.log
EOF
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
esac

LOG="${HOME:-/root}/.autostart.log"

echo "[$(date)] autostart running" >> "$LOG" 2>/dev/null || true

# Check network connectivity
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "[$(date)] Network: online" >> "$LOG" 2>/dev/null || true
else
    echo "[$(date)] Network: offline" >> "$LOG" 2>/dev/null || true
fi

echo "[$(date)] autostart complete" >> "$LOG" 2>/dev/null || true
