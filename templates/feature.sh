#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# TEMPLATE — new feature script
#
#  1. Copy:  cp templates/feature.sh features/<name>.sh
#  2. Docs:  DOC/AGENT_Context_Project.md file table line counts.
#
# Installed on demand with:  ./install.sh --feature
#   → copied to /usr/local/bin/<name>.sh (chmod 755)
#   → flag "<name>" is set (basename of the file, minus .sh)
# Features are user-customizable — install.sh never overwrites an
# existing /usr/local/bin copy without asking.
#
# If a systemd service depends on this feature, gate it in
# postinstall.sh's systemd loop:
#   if [ "$svc_name" = "<name>.service" ] && ! flag_is_set <name>; then
#       warn "<name> feature not installed — skipping <name>.service"
#       continue
#   fi
# ────────────────────────────────────────────────────────────────

# Robust flags.sh load — works from the repo checkout AND from
# /usr/local/bin after install.sh (which copies lib/flags.sh there).
source "$(dirname "$0")/../lib/flags.sh" 2>/dev/null || source "$(dirname "$0")/flags.sh"

# Self-name → matches the flag install.sh sets for this feature.
FEATURE_NAME="$(basename "$0")"
FEATURE_NAME="${FEATURE_NAME%.sh}"

usage() {
    cat <<EOF
Usage: ${FEATURE_NAME}.sh [options]

<describe what this feature does>

Installed via:  ./install.sh --feature
Flag:           ${FEATURE_NAME}
EOF
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
esac

# ── script logic ────────────────────────────────────────────────
# Feature scripts may run repeatedly (e.g. at every boot via a
# systemd service), so keep them idempotent.
#
#   flag_is_set "$FEATURE_NAME" || exit 0      # bail when not installed
#   v=$(flag_value "$FEATURE_NAME")            # read an optional value
#   flag_clear "$FEATURE_NAME"                 # uninstall behavior
