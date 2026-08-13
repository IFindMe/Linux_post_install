# lib/entertainment-plugin-lib.sh — message-safe helpers for entertainment
# plugins. Plugins MAY source this (unlike lib/common.sh, whose log/warn/ok
# chatter would leak into the sent message). Contract: this lib NEVER writes to
# stdout — helpers print errors to stderr and exit non-zero, so stdout stays the
# message. Defines only plugin_* names, so it can't collide with common.sh or a
# plugin's own helpers.
#
# Source pattern (works from the repo and from /usr/local/bin after install):
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/entertainment-plugin-lib.sh" 2>/dev/null \
#     || source "$(dirname "${BASH_SOURCE[0]}")/entertainment-plugin-lib.sh" 2>/dev/null \
#     || source "$(dirname "$0")/../lib/entertainment-plugin-lib.sh" 2>/dev/null \
#     || source "$(dirname "$0")/entertainment-plugin-lib.sh"

# Config file is the source of truth — read it like the pos tools do (never source it).
plugin_config_file="${PLUGIN_CONFIG_FILE:-$HOME/.config/linux_post_install/entertainment.env}"

plugin_err() { echo "ERROR: $*" >&2; exit 1; }

# Load KEY=VALUE pairs from entertainment.env into the environment.
# Env vars already set win (env precedence); quoted values are stripped;
# comments and blank lines skipped.
plugin_load_config() {
    [ -f "$plugin_config_file" ] || return 0
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
    done < <(grep -E '^[A-Z_]+=' "$plugin_config_file" || true)
}

# Fail unless the command is available.
plugin_have() {
    command -v "$1" >/dev/null 2>&1 || plugin_err "$1 not found — install it (see DOC/PREINSTALL.md or preinstall.sh PACKAGES)"
}

# Fail unless the config key is set (after plugin_load_config).
plugin_require() {
    [ -n "${!1:-}" ] || plugin_err "$1 not set — add it to $plugin_config_file"
}

# Fetch a URL as JSON with curl, retrying twice on transient failures, then
# extract the given jq key (optional). Everything is silent on stdout; errors
# go to stderr and exit non-zero.
plugin_http_json() {
    local key="" url="" json
    local -a headers=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --header|-H) headers+=(-H "$2"); shift 2 ;;
            *) url="$1"; shift ;;
        esac
    done
    [ -n "$url" ] || plugin_err "plugin_http_json: no URL given"
    json="$(curl -fsS --max-time 20 --retry 2 --retry-delay 2 "${headers[@]}" "$url")" || \
        plugin_err "Failed to fetch $url"
    if [ -n "$key" ]; then
        json="$(jq -r "$key" <<<"$json")" || plugin_err "Failed to parse '$key' from $url"
    fi
    printf '%s' "$json"
}
