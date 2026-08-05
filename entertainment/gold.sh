#!/usr/bin/env bash
set -euo pipefail

# Entertainment plugin: gold spot price (XAU/USD) via goldprice.dev (no API key).
# POS_PLUGIN: gold
# Contract: stdout is the message sent by 'pos entertainment send gold'.

err() { echo "ERROR: $*" >&2; exit 1; }

case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: pos entertainment send gold

Gold spot price (XAU/USD) from goldprice.dev (no API key, free anonymous tier).

Example:
  pos entertainment send gold --print
EOF
        exit 0
        ;;
esac

command -v curl &>/dev/null || err "curl not found"
command -v jq &>/dev/null || err "jq not found"

if ! json="$(curl -fsS --max-time 20 \
    "https://api.goldprice.dev/v1/prices?symbol=XAU-USD-SPOT")"; then
    err "Failed to fetch gold price from goldprice.dev"
fi

symbol="$(jq -r '.symbols[0].symbol' <<<"$json")"
price="$(jq -r '.symbols[0].price' <<<"$json")"
bid="$(jq -r '.symbols[0].bid' <<<"$json")"
ask="$(jq -r '.symbols[0].ask' <<<"$json")"
unit="$(jq -r '.symbols[0].unit' <<<"$json")"
when="$(jq -r '.symbols[0].computed_at' <<<"$json")"
when="${when/T/ }"; when="${when%Z}"

[ -n "$price" ] || err "No price received"

printf 'Gold spot (%s/USD): %s USD/%s\nBid %s · Ask %s\nas of %s UTC\n' \
    "$symbol" "$price" "$unit" "$bid" "$ask" "$when"
