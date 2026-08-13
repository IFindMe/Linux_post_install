#!/usr/bin/env bash
set -euo pipefail

# Entertainment plugin: random dad joke via icanhazdadjoke.com (no API key).
# POS_PLUGIN: joke
# Contract: stdout is the message sent by 'pos entertainment send joke'.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/entertainment-plugin-lib.sh" 2>/dev/null \
    || source "$(dirname "${BASH_SOURCE[0]}")/entertainment-plugin-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/../lib/entertainment-plugin-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/entertainment-plugin-lib.sh"

case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: pos entertainment send joke

Random dad joke from icanhazdadjoke.com (no API key).

Example:
  pos entertainment send joke --print
EOF
        exit 0
        ;;
esac

plugin_have curl
plugin_have jq

joke="$(plugin_http_json --key '.joke' -H 'Accept: application/json' "https://icanhazdadjoke.com/")"
[ -n "$joke" ] || plugin_err "No joke received"
printf '%s\n' "$joke"
