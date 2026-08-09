#!/usr/bin/env bash
set -euo pipefail

# Entertainment plugin: gold spot price (XAU/USD) via goldprice.dev (no API key).
# Headline price is USD per gram; the ounce quote is shown as reference.
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

price="$(jq -r '.symbols[0].price' <<<"$json")"
bid="$(jq -r '.symbols[0].bid' <<<"$json")"
ask="$(jq -r '.symbols[0].ask' <<<"$json")"
when="$(jq -r '.symbols[0].computed_at' <<<"$json")"
when="${when:0:19}"
when="${when/T/ }"

[ -n "$price" ] || err "No price received"

# XAU spot is quoted per troy ounce (31.1034768 g) — convert to USD/gram.
per_g="$(awk -v p="$price" -v o="31.1034768" 'BEGIN{printf "%.2f", p/o}')"

printf '🪙  Gold (XAU/USD)\n'
printf '💰  1 gram  $%s\n' "$per_g"
printf '⚖️  1 oz    $%s\n' "$price"
printf '📉  Bid $%s  ·  📈 Ask $%s\n' "$bid" "$ask"
printf '🕐  %s UTC\n' "$when"
