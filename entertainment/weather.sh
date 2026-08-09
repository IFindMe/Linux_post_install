#!/usr/bin/env bash
set -euo pipefail

# Entertainment plugin: current weather via Open-Meteo (no API key).
# Emoji + em-dash layout for Telegram; day/night-aware for clear skies.
# POS_PLUGIN: weather
# POS_KEYS: WEATHER_LAT <latitude> (required)
# POS_KEYS: WEATHER_LON <longitude> (required)
# POS_KEYS: WEATHER_CITY <city label> (optional)
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

# First arg: weather code; second arg: is_day (1=day). Prints the emoji.
wmo_emoji() {
    case "$1" in
        0)      [ "${2:-1}" = "1" ] && echo "☀️" || echo "🌙" ;;
        1)      echo "🌤️" ;;
        2)      echo "⛅" ;;
        3)      echo "☁️" ;;
        45|48)  echo "🌫️" ;;
        51|53|55) echo "🌦️" ;;
        61|63|65) echo "🌧️" ;;
        71|73|75) echo "❄️" ;;
        80|81|82) echo "🌧️" ;;
        95|96|99) echo "⛈️" ;;
        *)      echo "🌡️" ;;
    esac
}

wmo_desc() {
    case "$1" in
        0)      echo "Clear sky" ;;
        1)      echo "Mainly clear" ;;
        2)      echo "Partly cloudy" ;;
        3)      echo "Overcast" ;;
        45|48)  echo "Fog" ;;
        51|53|55) echo "Drizzle" ;;
        61|63|65) echo "Rain" ;;
        71|73|75) echo "Snow" ;;
        80|81|82) echo "Rain showers" ;;
        95|96|99) echo "Thunderstorm" ;;
        *)      echo "Weather code $1" ;;
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
    "https://api.open-meteo.com/v1/forecast?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,is_day")"; then
    err "Failed to fetch weather from Open-Meteo"
fi

temp="$(jq -r '.current.temperature_2m' <<<"$json")"
feels="$(jq -r '.current.apparent_temperature' <<<"$json")"
humidity="$(jq -r '.current.relative_humidity_2m' <<<"$json")"
code="$(jq -r '.current.weather_code' <<<"$json")"
wind="$(jq -r '.current.wind_speed_10m' <<<"$json")"
is_day="$(jq -r '.current.is_day' <<<"$json")"
unit_temp="$(jq -r '.current_units.temperature_2m' <<<"$json")"
unit_wind="$(jq -r '.current_units.wind_speed_10m' <<<"$json")"

emoji="$(wmo_emoji "$code" "$is_day")"

printf '%s %s · %s\n' "$emoji" "$(wmo_desc "$code")" "$label"
printf '🌡️  %s%s (feels like %s%s)\n' "$temp" "$unit_temp" "$feels" "$unit_temp"
printf '💧  Humidity %s%%\n' "$humidity"
printf '💨  Wind %s %s\n' "$wind" "$unit_wind"
