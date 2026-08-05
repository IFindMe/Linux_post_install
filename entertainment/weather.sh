#!/usr/bin/env bash
set -euo pipefail

# Entertainment plugin: current weather via Open-Meteo (no API key).
# Contract: stdout is the message sent by 'pos entertainment send weather'.

err() { echo "ERROR: $*" >&2; exit 1; }

CONFIG_FILE="$HOME/.config/linux_post_install/entertainment.env"

load_config() {
    [ -f "$CONFIG_FILE" ] || return 0
    local k v
    while IFS='=' read -r k v; do
        [ -n "$k" ] || continue
        case "$k" in
            \#*) continue ;;
        esac
        v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
        if [ -z "${!k:-}" ]; then
            export "$k"="$v"
        fi
    done < <(grep -E '^[A-Z_]+=' "$CONFIG_FILE" || true)
}

wmo_desc() {
    case "$1" in
        0)      echo "clear sky" ;;
        1)      echo "mainly clear" ;;
        2)      echo "partly cloudy" ;;
        3)      echo "overcast" ;;
        45|48)  echo "fog" ;;
        51|53|55) echo "drizzle" ;;
        61|63|65) echo "rain" ;;
        71|73|75) echo "snow" ;;
        80|81|82) echo "rain showers" ;;
        95|96|99) echo "thunderstorm" ;;
        *)      echo "weather code $1" ;;
    esac
}

case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: pos entertainment send weather

Current weather via Open-Meteo (no API key).

Config: $CONFIG_FILE (chmod 600)
  WEATHER_LAT, WEATHER_LON   Required — coordinates
  WEATHER_CITY               Optional label (e.g. "Berlin")

Example:
  WEATHER_LAT=52.52 WEATHER_LON=13.41 pos entertainment send weather --print
EOF
        exit 0
        ;;
esac

command -v curl &>/dev/null || err "curl not found"
command -v jq &>/dev/null || err "jq not found"

load_config

[ -n "${WEATHER_LAT:-}" ] || err "WEATHER_LAT not set — add it to $CONFIG_FILE"
[ -n "${WEATHER_LON:-}" ] || err "WEATHER_LON not set — add it to $CONFIG_FILE"
label="${WEATHER_CITY:-$WEATHER_LAT,$WEATHER_LON}"

if ! json="$(curl -fsS --max-time 20 \
    "https://api.open-meteo.com/v1/forecast?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m")"; then
    err "Failed to fetch weather from Open-Meteo"
fi

temp="$(jq -r '.current.temperature_2m' <<<"$json")"
feels="$(jq -r '.current.apparent_temperature' <<<"$json")"
humidity="$(jq -r '.current.relative_humidity_2m' <<<"$json")"
code="$(jq -r '.current.weather_code' <<<"$json")"
wind="$(jq -r '.current.wind_speed_10m' <<<"$json")"
unit_temp="$(jq -r '.current_units.temperature_2m' <<<"$json")"
unit_wind="$(jq -r '.current_units.wind_speed_10m' <<<"$json")"

printf 'Weather in %s: %s, %s%s (feels like %s%s), humidity %s%%, wind %s%s\n' \
    "$label" "$(wmo_desc "$code")" "$temp" "$unit_temp" "$feels" "$unit_temp" "$humidity" "$wind" "$unit_wind"
