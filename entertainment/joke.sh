#!/usr/bin/env bash
set -euo pipefail

# Entertainment plugin: random dad joke via icanhazdadjoke.com (no API key).
# Contract: stdout is the message sent by 'pos entertainment send joke'.

err() { echo "ERROR: $*" >&2; exit 1; }

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

command -v curl &>/dev/null || err "curl not found"
command -v jq &>/dev/null || err "jq not found"

if ! joke="$(curl -fsS --max-time 20 -H 'Accept: application/json' \
    https://icanhazdadjoke.com/ | jq -r '.joke')"; then
    err "Failed to fetch a joke from icanhazdadjoke.com"
fi

[ -n "$joke" ] || err "No joke received"
printf '%s\n' "$joke"
