#!/usr/bin/env bash
set -euo pipefail

# Entertainment plugin: current weather via Open-Meteo (no API key).
# Emoji + em-dash layout for Telegram; day/night-aware for clear skies.
# POS_PLUGIN: weather
# POS_KEYS: WEATHER_LAT <latitude> (required)
# POS_KEYS: WEATHER_LON <longitude> (required)
# POS_KEYS: WEATHER_CITY <city label> (optional)
# Contract: stdout is the message sent by 'pos entertainment send weather'.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/entertainment-plugin-lib.sh" 2>/dev/null \
    || source "$(dirname "${BASH_SOURCE[0]}")/entertainment-plugin-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/../lib/entertainment-plugin-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/entertainment-plugin-lib.sh"

case "${1:-}" in
    -h|--help)
        cat <<EOF
Usage: pos entertainment send weather

Current weather via Open-Meteo (no API key).

Config: $plugin_config_file (chmod 600)
  WEATHER_LAT, WEATHER_LON   Required — coordinates
  WEATHER_CITY               Optional label (e.g. "Berlin")

Example:
  WEATHER_LAT=52.52 WEATHER_LON=13.41 pos entertainment send weather --print
EOF
        exit 0
        ;;
esac

plugin_have curl
plugin_have jq

plugin_load_config
plugin_require WEATHER_LAT
plugin_require WEATHER_LON
label="${WEATHER_CITY:-$WEATHER_LAT,$WEATHER_LON}"

json="$(plugin_http_json \
    "https://api.open-meteo.com/v1/forecast?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,is_day")"

temp="$(jq -r '.current.temperature_2m' <<<"$json")"
feels="$(jq -r '.current.apparent_temperature' <<<"$json")"
humidity="$(jq -r '.current.relative_humidity_2m' <<<"$json")"
code="$(jq -r '.current.weather_code' <<<"$json")"
wind="$(jq -r '.current.wind_speed_10m' <<<"$json")"
is_day="$(jq -r '.current.is_day' <<<"$json")"
unit_temp="$(jq -r '.current_units.temperature_2m' <<<"$json")"
unit_wind="$(jq -r '.current_units.wind_speed_10m' <<<"$json")"

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

emoji="$(wmo_emoji "$code" "$is_day")"

printf '%s %s · %s\n' "$emoji" "$(wmo_desc "$code")" "$label"
printf '🌡️  %s%s (feels like %s%s)\n' "$temp" "$unit_temp" "$feels" "$unit_temp"
printf '💧  Humidity %s%%\n' "$humidity"
printf '💨  Wind %s %s\n' "$wind" "$unit_wind"
