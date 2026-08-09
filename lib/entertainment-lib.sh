# Shared library for the entertainment module (pos entertainment *).
# Sourced by the bin/pos-entertainment-* tools AFTER lib/common.sh.
# NOTE: plugins themselves must NOT source this — their stdout is the message.

CONFIG_DIR="$HOME/.config/linux_post_install"
CONFIG_FILE="$CONFIG_DIR/entertainment.env"
USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
TIMER_PREFIX="pos-entertainment"
DEFAULT_INTERVAL="daily"

# common.sh helpers (guarded so the lib is safe if common.sh wasn't loaded)
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F ok   >/dev/null || ok()   { echo "  OK $*"; }
declare -F log  >/dev/null || log()  { echo "[+] $*"; }

# ── Config file helpers (file is the source of truth, never sourced) ──
config_value() {
    local k="$1" v
    [ -f "$CONFIG_FILE" ] || return 0
    v="$(sed -n "s|^${k}=||p" "$CONFIG_FILE" | tail -1)"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
}

write_config_key() {
    local key="$1" val="$2" tmp
    mkdir -p "$CONFIG_DIR"
    tmp="$(mktemp)"
    grep -v "^${key}=" "$CONFIG_FILE" 2>/dev/null >"$tmp" || true
    printf '%s="%s"\n' "$key" "$val" >>"$tmp"
    mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

# ── Plugin lookup ──────────────────────────────────────────────────
plugin_dir() {
    if [ -n "${ENTERTAINMENT_DIR:-}" ]; then
        echo "$ENTERTAINMENT_DIR"
    elif [ -d "$(dirname "$0")/../entertainment" ]; then
        echo "$(cd "$(dirname "$0")/../entertainment" && pwd)"
    else
        echo "$(cd "$(dirname "$0")" && pwd)"
    fi
}

plugin_marker() {
    grep -m1 '^# POS_PLUGIN:' "$1" 2>/dev/null | sed 's/^# POS_PLUGIN:[[:space:]]*//;s/[[:space:]]*$//' || true
}

list_plugins() {
    local dir="$1" f name
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        name="$(plugin_marker "$f")"
        [ -n "$name" ] && echo "$name"
    done
}

plugin_exists() {
    local dir="$1" name="$2" f
    for f in "$dir/$name" "$dir/$name.sh"; do
        [ -f "$f" ] && [ -x "$f" ] && [ -n "$(plugin_marker "$f")" ] && return 0
    done
    return 1
}

resolve_plugin() {
    local dir="$1" name="$2" f
    [ -n "$name" ] || err "No plugin given"
    for f in "$dir/$name" "$dir/$name.sh"; do
        if [ -f "$f" ] && [ -x "$f" ]; then
            [ -n "$(plugin_marker "$f")" ] || err "'$f' is not an entertainment plugin (missing '# POS_PLUGIN:' header)"
            echo "$f"
            return 0
        fi
    done
    err "Plugin '$name' not found in $dir — try one of: $(list_plugins "$dir" | tr '\n' ' ')"
}

# ── Config keys declared by plugins ────────────────────────────────
# Pattern: each plugin documents the config keys it reads with
#   # POS_KEYS: <KEY> <description> (required|optional)
# on one or more lines (right after # POS_PLUGIN:). 'pos entertainment
# config' prints them in its Keys section; config set warns when a key is
# not declared by any installed plugin.

plugin_keys() {
    # Usage: plugin_keys <plugin-file>  → "KEY|description|required|optional"
    local file="$1" line key desc req
    grep '^# POS_KEYS:' "$file" 2>/dev/null | sed 's/^# POS_KEYS:[[:space:]]*//' | while IFS= read -r line; do
        key="${line%% *}"
        desc="${line#* }"
        case "$desc" in
            *\(required\)) req=required;  desc="${desc% (required)}" ;;
            *\(optional\)) req=optional;  desc="${desc% (optional)}" ;;
            *)            req="" ;;
        esac
        printf '%s|%s|%s\n' "$key" "$desc" "$req"
    done || true
}

config_keys() {
    # Usage: config_keys <plugin-dir>  → "KEY|plugin|description|required|optional"
    local dir="$1" f name line
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        name="$(plugin_marker "$f")"
        [ -n "$name" ] || continue
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            printf '%s|%s\n' "$name" "$line"
        done <<< "$(plugin_keys "$f")"
    done
}

config_key_known() {
    # Usage: config_key_known <plugin-dir> <KEY>  → true if ENABLED or declared by a plugin
    local dir="$1" key="$2"
    [ "$key" = "ENABLED" ] && return 0
    local line _plugin _key _rest
    while IFS= read -r line; do
        IFS='|' read -r _plugin _key _rest <<<"$line"
        [ "$_key" = "$key" ] && return 0
    done <<< "$(config_keys "$dir")"
    return 1
}

# ── ENABLED list parsing ──────────────────────────────────────────
# Format: comma/space-separated 'plugin[, interval]' pairs, e.g.
# 'weather, 5m gold, 1h'. Parsed name-aware: a token that resolves to a
# plugin starts a new entry; any other token is the current entry's interval.
# Custom OnCalendar= specs must not contain spaces (use the named intervals
# 5m 10m 15m 30m 45m hourly 2h 6h 12h daily weekly otherwise).
parse_enabled() {
    local raw="$1" token cur=""
    local -a toks=()
    ENABLED_ENTRIES=()
    [ -n "$raw" ] || return 0
    IFS=' ' read -ra toks <<<"$(printf '%s' "$raw" | tr ',' ' ')"
    for token in "${toks[@]}"; do
        [ -n "$token" ] || continue
        if plugin_exists "$(plugin_dir)" "$token"; then
            [ -n "$cur" ] && ENABLED_ENTRIES+=("$cur")
            cur="$token"
        elif [ -n "$cur" ]; then
            cur="$cur,$token"
        fi
    done
    [ -n "$cur" ] && ENABLED_ENTRIES+=("$cur")
}

render_enabled() {
    local out="" entry p i
    for entry in "$@"; do
        p="${entry%%,*}"; i="${entry##*,}"
        if [ "$i" = "$p" ]; then
            [ -z "$out" ] && out="$p" || out="$out $p"
        else
            [ -z "$out" ] && out="$p, $i" || out="$out $p, $i"
        fi
    done
    printf '%s' "$out"
}

enabled_upsert() {
    local plugin="$1" interval="${2:-}" raw entry p
    raw="$(config_value ENABLED)"
    local -a out=() found=0
    [ -n "$raw" ] && parse_enabled "$raw"
    for entry in "${ENABLED_ENTRIES[@]}"; do
        p="${entry%%,*}"
        if [ "$p" = "$plugin" ]; then
            found=1
            if [ -n "$interval" ]; then
                out+=("$plugin,$interval")
            else
                out+=("$entry")
            fi
        else
            out+=("$entry")
        fi
    done
    [ "$found" -eq 0 ] && out+=("$plugin${interval:+,$interval}")
    write_config_key ENABLED "$(render_enabled "${out[@]}")"
}

enabled_remove() {
    local plugin="$1" raw entry p
    raw="$(config_value ENABLED)"
    local -a out=()
    [ -n "$raw" ] && parse_enabled "$raw"
    for entry in "${ENABLED_ENTRIES[@]}"; do
        p="${entry%%,*}"
        [ "$p" = "$plugin" ] && continue
        out+=("$entry")
    done
    write_config_key ENABLED "$(render_enabled "${out[@]}")"
}

# ── Interval → systemd OnCalendar ─────────────────────────────────
interval_to_oncalendar() {
    local i="$1"
    case "$i" in
        OnCalendar=*) printf '%s' "${i#OnCalendar=}"; return 0 ;;
    esac
    if [[ "$i" =~ ^([0-9]+)m$ ]]; then
        local n="${BASH_REMATCH[1]}"
        [ "$n" -ge 1 ] && [ "$n" -le 59 ] || return 1
        printf '*:00/%s:00' "$n"; return 0
    fi
    if [[ "$i" =~ ^([0-9]+)h$ ]]; then
        local n="${BASH_REMATCH[1]}"
        [ "$n" -ge 1 ] && [ "$n" -le 23 ] || return 1
        printf '*-*-* 00/%s:00:00' "$n"; return 0
    fi
    case "$i" in
        hourly) printf '*-*-* *:00:00' ;;
        daily)  printf '*-*-* 08:00:00' ;;
        weekly) printf 'Mon *-*-* 08:00:00' ;;
        *) return 1 ;;
    esac
    return 0
}

interval_label() {
    case "$1" in
        daily)      echo "daily (08:00)" ;;
        weekly)     echo "weekly (Mon 08:00)" ;;
        hourly)     echo "hourly" ;;
        OnCalendar=*) echo "${1#OnCalendar=}" ;;
        *m|*h|*d)   echo "every $1" ;;
        *)          echo "$1" ;;
    esac
}

# ── systemd user timers ───────────────────────────────────────────
unit_name() { echo "${TIMER_PREFIX}-${1}"; }

write_units() {
    local plugin="$1" oncal="$2"
    local base="$USER_SYSTEMD_DIR/$(unit_name "$plugin")"
    local runner
    runner="$(command -v pos-entertainment-send 2>/dev/null || echo /usr/local/bin/pos-entertainment-send)"
    mkdir -p "$USER_SYSTEMD_DIR"
    cat >"$base.service" <<EOF
[Unit]
Description=pos entertainment send $plugin
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$runner $plugin

[Install]
WantedBy=timers.target
EOF
    cat >"$base.timer" <<EOF
[Unit]
Description=Schedule: pos entertainment send $plugin

[Timer]
OnCalendar=$oncal
Persistent=true

[Install]
WantedBy=timers.target
EOF
    chmod 644 "$base.service" "$base.timer"
}

ensure_linger() {
    local user
    user="$(id -un)"
    [ "$user" = "root" ] && { warn "running as root — enable linger for your real user: sudo loginctl enable-linger <user>"; return 0; }
    command -v loginctl >/dev/null 2>&1 || return 0
    if loginctl show-user "$user" 2>/dev/null | grep -q '^Linger=yes'; then
        return 0
    fi
    if sudo -n loginctl enable-linger "$user" 2>/dev/null; then
        ok "enabled linger for $user (timers fire without login)"
    else
        warn "run once so timers fire without login: sudo loginctl enable-linger $user"
    fi
}

# Reconcile the auto-trigger schedule with the ENABLED list in the config.
# Backend: systemd user timers (requires a reachable user systemd manager).
sync_timers() {
    if systemctl --user show-environment >/dev/null 2>&1; then
        sync_systemd
    else
        warn "no systemd user manager available — run 'pos entertainment send <plugin>' manually"
    fi
}

# ── Backend: systemd user timers ─────────────────────────────────
sync_systemd() {
    local raw entry plugin oncal
    raw="$(config_value ENABLED)"
    parse_enabled "$raw"

    local -A wanted=()
    for entry in "${ENABLED_ENTRIES[@]}"; do
        plugin="${entry%%,*}"; interval="${entry##*,}"
        [ "$interval" = "$plugin" ] && interval="$DEFAULT_INTERVAL"
        if ! plugin_exists "$(plugin_dir)" "$plugin"; then
            warn "plugin '$plugin' not installed — skipping"
            continue
        fi
        if ! oncal="$(interval_to_oncalendar "$interval")"; then
            warn "invalid interval '$interval' for '$plugin' — skipping"
            continue
        fi
        wanted["$plugin"]="$oncal"
    done

    local wrote=0 t n=0
    for plugin in "${!wanted[@]}"; do
        write_units "$plugin" "${wanted[$plugin]}"
        wrote=1; n=$((n + 1))
    done
    [ "$wrote" -eq 1 ] && systemctl --user daemon-reload >/dev/null 2>&1 || true

    [ "$n" -gt 0 ] && ensure_linger

    for plugin in "${!wanted[@]}"; do
        t="$(unit_name "$plugin").timer"
        if systemctl --user is-enabled "$t" >/dev/null 2>&1; then
            systemctl --user restart "$t" >/dev/null 2>&1 || true
        else
            systemctl --user enable --now "$t" >/dev/null 2>&1 || \
                warn "could not enable timer '$t' (is the user systemd manager running?)"
        fi
    done

    local f p removed=0
    for f in "$USER_SYSTEMD_DIR"/${TIMER_PREFIX}-*.timer; do
        [ -f "$f" ] || continue
        p="${f##*/}"; p="${p#${TIMER_PREFIX}-}"; p="${p%.timer}"
        if [ -z "${wanted[$p]:-}" ]; then
            systemctl --user disable --now "$(unit_name "$p").timer" >/dev/null 2>&1 || true
            rm -f "$USER_SYSTEMD_DIR/$(unit_name "$p").timer" "$USER_SYSTEMD_DIR/$(unit_name "$p").service"
            log "removed timer for '$p'"
            removed=1
        fi
    done
    [ "$removed" -eq 1 ] && systemctl --user daemon-reload >/dev/null 2>&1 || true
}

