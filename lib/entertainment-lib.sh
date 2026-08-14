# Shared library for the entertainment module (pos entertainment *).
# Sourced by the bin/pos-entertainment-* tools AFTER lib/common.sh
# (which defines CONFIG_DIR). NOTE: plugins themselves must NOT source
# this — their stdout is the message.

CONFIG_FILE="$CONFIG_DIR/entertainment.env"
TIMER_PREFIX="pos-entertainment"
DEFAULT_INTERVAL="daily"

# common.sh helpers (guarded so the lib is safe if common.sh wasn't loaded)
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F ok   >/dev/null || ok()   { echo "  OK $*"; }
declare -F log  >/dev/null || log()  { echo "[+] $*"; }

# Shared systemd **user** timer machinery (interval→OnCalendar mapping, unit
# pair writer, linger bootstrap) — the same lib the system scheduler uses, so
# the two unit templates never drift apart. Defines USER_SYSTEMD_DIR + ut_*.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/user-timers-lib.sh" 2>/dev/null \
    || source "$(dirname "${BASH_SOURCE[0]}")/user-timers-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/../lib/user-timers-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/user-timers-lib.sh"

# Per-plugin last-run state (rc + timestamp + first output line).
LAST_RUN_DIR="${LAST_RUN_DIR:-$HOME/.local/share/linux_post_install/entertainment/last}"

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
    val="${val//$'\r'/}"
    val="${val%%$'\n'*}"
    mkdir -p "$CONFIG_DIR"
    if [ "$val" = "-" ]; then
        [ -f "$CONFIG_FILE" ] || return 0
        tmp="$(mktemp)"
        grep -v "^${key}=" "$CONFIG_FILE" >"$tmp" || true
        mv "$tmp" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        return 0
    fi
    tmp="$(mktemp)"
    grep -v "^${key}=" "$CONFIG_FILE" 2>/dev/null >"$tmp" || true
    printf '%s="%s"\n' "$key" "$val" >>"$tmp"
    mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

# ── Plugin lookup ──────────────────────────────────────────────────
ent_plugin_dir() {
    if [ -n "${ENTERTAINMENT_DIR:-}" ]; then
        echo "$ENTERTAINMENT_DIR"
    elif [ -d "$(dirname "$0")/../entertainment" ]; then
        echo "$(cd "$(dirname "$0")/../entertainment" && pwd)"
    else
        echo "$(cd "$(dirname "$0")" && pwd)"
    fi
}

ent_plugin_marker() {
    grep -m1 '^# POS_PLUGIN:' "$1" 2>/dev/null | sed 's/^# POS_PLUGIN:[[:space:]]*//;s/[[:space:]]*$//' || true
}

list_plugins() {
    local dir="$1" f name
    for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        name="$(ent_plugin_marker "$f")"
        [ -n "$name" ] && echo "$name"
    done
}

ent_plugin_exists() {
    local dir="$1" name="$2" f
    for f in "$dir/$name" "$dir/$name.sh"; do
        [ -f "$f" ] && [ -x "$f" ] && [ -n "$(ent_plugin_marker "$f")" ] && return 0
    done
    return 1
}

resolve_plugin() {
    local dir="$1" name="$2" f
    [ -n "$name" ] || err "No plugin given"
    for f in "$dir/$name" "$dir/$name.sh"; do
        if [ -f "$f" ] && [ -x "$f" ]; then
            [ -n "$(ent_plugin_marker "$f")" ] || err "'$f' is not an entertainment plugin (missing '# POS_PLUGIN:' header)"
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

ent_plugin_keys() {
    # Usage: ent_plugin_keys <plugin-file>  → "KEY|description|required|optional"
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
        name="$(ent_plugin_marker "$f")"
        [ -n "$name" ] || continue
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            printf '%s|%s\n' "$name" "$line"
        done <<< "$(ent_plugin_keys "$f")"
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
        if ent_plugin_exists "$(ent_plugin_dir)" "$token"; then
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

# ── systemd user timers ───────────────────────────────────────────
# Interval → OnCalendar mapping, unit naming, the unit pair writer and linger
# bootstrap come from lib/user-timers-lib.sh (ut_*). Reconcile the auto-trigger
# schedule with the ENABLED list in the config.
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
        if ! ent_plugin_exists "$(ent_plugin_dir)" "$plugin"; then
            warn "plugin '$plugin' not installed — skipping"
            continue
        fi
        if ! oncal="$(ut_interval_to_oncalendar "$interval")"; then
            warn "invalid interval '$interval' for '$plugin' — skipping"
            continue
        fi
        wanted["$plugin"]="$oncal"
    done

    local runner wrote=0 t n=0
    runner="$(command -v pos-entertainment-send 2>/dev/null || echo /usr/local/bin/pos-entertainment-send)"
    for plugin in "${!wanted[@]}"; do
        local base="$USER_SYSTEMD_DIR/$(ut_unit_name "$TIMER_PREFIX" "$plugin")"
        ut_write_unit_pair "$base.service" "$base.timer" "pos entertainment send $plugin" "$runner $plugin" "${wanted[$plugin]}"
        wrote=1; n=$((n + 1))
    done
    [ "$wrote" -eq 1 ] && systemctl --user daemon-reload >/dev/null 2>&1 || true

    [ "$n" -gt 0 ] && ut_ensure_linger

    for plugin in "${!wanted[@]}"; do
        t="$(ut_unit_name "$TIMER_PREFIX" "$plugin").timer"
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
            systemctl --user disable --now "$(ut_unit_name "$TIMER_PREFIX" "$p").timer" >/dev/null 2>&1 || true
            rm -f "$USER_SYSTEMD_DIR/$(ut_unit_name "$TIMER_PREFIX" "$p").timer" "$USER_SYSTEMD_DIR/$(ut_unit_name "$TIMER_PREFIX" "$p").service"
            log "removed timer for '$p'"
            removed=1
        fi
    done
    [ "$removed" -eq 1 ] && systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# ── Per-plugin last-run state ────────────────────────────────────
# Written by 'pos entertainment send' on every non---print run so 'status' can
# show whether a scheduled run succeeded. State dir is per-user, not tracked.
save_last_run() {   # $1 = plugin, $2 = rc, $3 = message (first line)
    local f="$LAST_RUN_DIR/$1"
    mkdir -p "$LAST_RUN_DIR"
    {
        printf 'rc=%s\n' "$2"
        printf 'ts=%s\n' "$(date +%s)"
        printf 'msg=%s\n' "$3"
    } >"$f"
    chmod 600 "$f"
}

last_run_str() {   # $1 = plugin → "rc=N (MM-DD HH:MM)" or "never"
    local f="$LAST_RUN_DIR/$1" rc ts
    [ -f "$f" ] || { echo "never"; return 0; }
    rc="$(sed -n 's/^rc=//p' "$f" | tail -1)"
    ts="$(sed -n 's/^ts=//p' "$f" | tail -1)"
    [ -n "$rc" ] || { echo "never"; return 0; }
    printf 'rc=%s (%s)' "$rc" "$(date -d "@$ts" '+%m-%d %H:%M' 2>/dev/null || echo '?')"
}

