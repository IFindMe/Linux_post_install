# lib/config-ui.sh — interactive, self-describing config UI for the pos tools.
# Reads each tool's "# POS_CONFIG:" header — the config registry — and renders
# a numbered menu per scope to view/edit values in the matching env file.
# Self-contained: uses common.sh helpers when available, with guarded fallbacks
# (mirrors lib/notify.sh). Sourced opt-in by bin/pos-config.
#
# Header grammar — one "# POS_CONFIG:" line per scope a tool exposes:
#   # POS_CONFIG: <scope> | <env-file> | <KEY>=<flags>:<desc>[::<example>] | ... | *plugins
#     <env-file>  basename of the config file under ~/.config/linux_post_install/
#     <flags>     secret (masked display + stty -echo input) | digits | num | float
#     <example>   optional value format hint shown in the editor, e.g. "weather,5m joke,10m"
#     *plugins    marker: also list every key declared by the installed
#                 entertainment plugins' "# POS_KEYS:" headers (dynamic)
#   Example:
#     # POS_CONFIG: telegram | telegram.env | TELEGRAM_BOT_TOKEN=secret:Bot token | TELEGRAM_CHAT_ID=digits:Numeric chat id
#
# Usage (opt-in):
#   source "$(dirname "$0")/../lib/config-ui.sh" 2>/dev/null || source "$(dirname "$0")/config-ui.sh"
#   cfg_scopes            # list all declared scopes (deduped, sorted)
#   cfg_ui <scope>        # interactive numbered-menu editor for one scope

CONFIG_DIR="$HOME/.config/linux_post_install"

# common.sh helpers (guarded so the lib is safe if common.sh wasn't loaded)
declare -F log  >/dev/null || log()  { echo "[+] $*"; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }
declare -F ok   >/dev/null || ok()   { echo "  OK $*"; }

_cfg_scope=""               # scope being edited (drives the post-write hook)
declare -A _cfg_seen=()     # key dedupe registry for cfg_scope_keys

# ── tool directory ─────────────────────────────────────────────────
# Repo layout: lib/config-ui.sh → tools live in ../bin.
# Installed layout: /usr/local/bin/config-ui.sh → ../bin == /usr/local/bin.
cfg_tools_dir() {
    local dir f found=0
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd)"
    if [ -n "$dir" ]; then
        for f in "$dir"/pos-*; do
            [ -x "$f" ] && { found=1; break; }
        done
    fi
    [ "$found" -eq 1 ] && { echo "$dir"; return 0; }
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
}

# All "# POS_CONFIG:" header lines (prefix stripped), one per line.
# `|| true` keeps pipefail happy when a tool has no such header (grep exits 1).
cfg_headers() {
    local dir="$1" f
    for f in "$dir"/pos-*; do
        [ -f "$f" ] && [ -x "$f" ] || continue
        grep '^# POS_CONFIG:' "$f" 2>/dev/null | sed 's/^# POS_CONFIG:[[:space:]]*//' || true
    done
    return 0
}

# All declared scopes (deduped, sorted).
cfg_scopes() {
    local dir line scope
    dir="$(cfg_tools_dir)"
    cfg_headers "$dir" | while IFS= read -r line; do
        scope="${line%%|*}"
        scope="${scope// }"
        if [ -n "$scope" ]; then
            echo "$scope"
        fi
    done | sort -u
}

# Env-file basename for a scope (first header declaring it wins). Exit 1 if none.
cfg_scope_envfile() {
    local scope="$1" dir line s rest env
    dir="$(cfg_tools_dir)"
    while IFS= read -r line; do
        s="${line%%|*}"
        s="${s// }"
        [ "$s" = "$scope" ] || continue
        rest="${line#*|}"
        env="${rest%%|*}"
        env="${env// }"
        echo "$env"
        return 0
    done < <(cfg_headers "$dir")
    return 1
}

# One key field → "KEY|flags|description|example" (deduped via _cfg_seen).
# The optional example is "desc::example" — a literal "::" separates the
# value-format hint from the description.
_cfg_key_line() {
    local field="$1" key="" flags="" desc="" rest="" example=""
    key="${field%%=*}"
    if [[ "$field" == *"="* ]]; then
        rest="${field#*=}"
        if [[ "$rest" == *":"* ]]; then
            flags="${rest%%:*}"
            desc="${rest#*:}"
        else
            flags="$rest"
        fi
        if [[ "$desc" == *"::"* ]]; then
            example="${desc##*::}"
            desc="${desc%%::*}"
        fi
    fi
    [ -n "$key" ] || return 0
    [ -n "${_cfg_seen[$key]:-}" ] && return 0
    _cfg_seen[$key]=1
    printf '%s|%s|%s|%s\n' "$key" "$flags" "$desc" "$example"
}

# "*plugins" expansion: keys declared by the installed entertainment
# plugins' "# POS_KEYS:" headers (via lib/entertainment-lib.sh, sourced lazily).
_cfg_plugin_keys() {
    declare -F config_keys >/dev/null 2>&1 || {
        local lib
        for lib in \
            "$(dirname "${BASH_SOURCE[0]}")/../lib/entertainment-lib.sh" \
            "$(dirname "${BASH_SOURCE[0]}")/entertainment-lib.sh"; do
            if [ -f "$lib" ]; then source "$lib"; break; fi
        done
    }
    declare -F config_keys >/dev/null 2>&1 || return 0
    local pdir line plugin key desc req
    pdir="$(plugin_dir)"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        IFS='|' read -r plugin key desc req <<<"$line"
        [ -n "$key" ] || continue
        [ -n "${_cfg_seen[$key]:-}" ] && continue
        _cfg_seen[$key]=1
        printf '%s|%s|%s (%s) [%s]|\n' "$key" "" "$desc" "$req" "$plugin"
    done < <(config_keys "$pdir")
    return 0
}

# Declared keys for a scope: "KEY|flags|description" lines, deduped.
cfg_scope_keys() {
    local scope="$1" dir line s keystring field
    local -a fields=()
    dir="$(cfg_tools_dir)"
    _cfg_seen=()
    while IFS= read -r line; do
        s="${line%%|*}"
        s="${s// }"
        [ "$s" = "$scope" ] || continue
        keystring="${line#*|}"
        keystring="${keystring#*|}"          # drop the env-file field
        IFS='|' read -r -a fields <<<"$keystring"
        for field in "${fields[@]}"; do
            field="${field#"${field%%[![:space:]]*}"}"
            field="${field%"${field##*[![:space:]]}"}"
            if [ -n "$field" ]; then
                if [[ "$field" == "*"* ]]; then
                    case "$field" in
                        *plugins*) _cfg_plugin_keys ;;
                    esac
                else
                    _cfg_key_line "$field"
                fi
            fi
        done
    done < <(cfg_headers "$dir")
    return 0
}

# Current value of a key in an env file (file is the source of truth, never sourced).
cfg_value() {
    local file="$1" key="$2" v
    [ -f "$file" ] || return 0
    v="$(sed -n "s|^${key}=||p" "$file" | tail -1)"
    v="${v//$'\r'/}"
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    printf '%s' "$v"
}

# Write KEY="value" (append or replace) with mkdir -p + chmod 600; a value of
# "-" removes the key's line. Same semantics as write_config_key(). Replaces
# via grep-v + append (not sed), so values may contain &, |, \ etc. safely.
cfg_write() {
    local file="$1" key="$2" val="$3" tmp
    mkdir -p "$(dirname "$file")"
    if [ "$val" = "-" ]; then
        [ -f "$file" ] || return 0
        tmp="$(mktemp)"
        grep -v "^${key}=" "$file" >"$tmp" || true
        mv "$tmp" "$file"
        chmod 600 "$file"
        return 0
    fi
    val="${val//$'\r'/}"
    if [[ "$val" == *$'\n'* ]]; then
        val="${val%%$'\n'*}"
        warn "multi-line paste — using first line only"
    fi
    tmp="$(mktemp)"
    grep -v "^${key}=" "$file" 2>/dev/null >"$tmp" || true
    printf '%s="%s"\n' "$key" "$val" >>"$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
}

# Display a value: masked for secret flags, "(not set)" when empty.
cfg_display() {
    local val="$1" flags="$2" n
    if [ -z "$val" ]; then
        echo "(not set)"
    elif [[ ",$flags," == *,secret,* ]]; then
        n=${#val}
        if [ "$n" -le 12 ]; then
            echo "${val:0:4}... (${n} chars)"
        else
            echo "${val:0:6}...${val: -4} (${n} chars)"
        fi
    else
        echo "$val"
    fi
}

# Validate a value against a key's flags. Prints an error, returns 1 on failure.
cfg_validate() {
    local flags="$1" val="$2"
    case ",$flags," in
        *,digits,*) [[ "$val" =~ ^-?[0-9]+$ ]] || { echo "must be digits only (a leading '-' is allowed for group/supergroup ids)"; return 1; } ;;
    esac
    case ",$flags," in
        *,num,*) [[ "$val" =~ ^-?[0-9]+$ ]] || { echo "must be an integer"; return 1; } ;;
    esac
    case ",$flags," in
        *,float,*) [[ "$val" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { echo "must be a number"; return 1; } ;;
    esac
    return 0
}

# Read a value with echo off (secret flags). Falls back to plain read when
# stdin is not a TTY (e.g. piped menu input).
# The cursor-advancing newline after the hidden input MUST go to the terminal
# (>&2), not stdout — cfg_read_secret is called via $(), so anything on stdout
# is captured into the value; a stray leading newline corrupted ai.env.
cfg_read_secret() {
    local val echo_off=0
    if [ -t 0 ]; then
        stty -echo 2>/dev/null && echo_off=1
    fi
    read -r val || true
    if [ "$echo_off" -eq 1 ]; then
        stty echo 2>/dev/null || true
        echo >&2
    fi
    printf '%s' "$val"
}

# After a successful write: the entertainment scope re-syncs its auto-trigger
# timers when the ENABLED list changes (mirrors `pos entertainment config set`).
_cfg_post_write() {
    local key="$1"
    [ "$_cfg_scope" = "entertainment" ] && [ "$key" = "ENABLED" ] || return 0
    declare -F sync_timers >/dev/null 2>&1 && sync_timers
}

# Edit one key: Enter keeps the current value, "-" clears it.
_cfg_edit_one() {
    local file="$1" keystr="$2"
    local key flags desc example cur val errmsg hint
    IFS='|' read -r key flags desc example <<<"$keystr"
    cur="$(cfg_value "$file" "$key")"
    hint="${example:+ (e.g. ${example})}"

    if [[ ",$flags," == *,secret,* ]]; then
        printf '  %s [%s]%s (input hidden): ' "$key" "$(cfg_display "$cur" "$flags")" "$hint"
        val="$(cfg_read_secret)"
    else
        read -rp "  ${key}${hint} [${cur:-unset}]: " val || return 0
    fi

    if [ -z "$val" ]; then
        log "kept current value for $key"
        return 0
    fi
    if [ "$val" = "-" ]; then
        cfg_write "$file" "$key" "-"
        log "cleared $key from $file"
        _cfg_post_write "$key"
        return 0
    fi
    if ! errmsg="$(cfg_validate "$flags" "$val")"; then
        warn "$key: $errmsg — not saved"
        return 0
    fi
    cfg_write "$file" "$key" "$val"
    ok "$key saved to $file"
    _cfg_post_write "$key"
}

# Interactive numbered-menu editor for one scope. q quits; r re-renders.
cfg_ui() {
    local scope="$1" envfile file line
    envfile="$(cfg_scope_envfile "$scope")" || { warn "unknown config scope '$scope'"; return 1; }
    file="$CONFIG_DIR/$envfile"
    _cfg_scope="$scope"

    local -a keys=()
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            keys+=("$line")
        fi
    done < <(cfg_scope_keys "$scope")
    if [ ${#keys[@]} -eq 0 ]; then
        warn "no config keys declared for scope '$scope'"
        return 1
    fi

    local choice i k f d e v
    while true; do
        echo
        echo "pos config — ${scope} (${envfile})"
        echo "------------------------------------"
        i=0
        for line in "${keys[@]}"; do
            i=$((i + 1))
            IFS='|' read -r k f d e <<<"$line"
            v="$(cfg_value "$file" "$k")"
            printf '  %2d) %-28s %s\n' "$i" "$k" "$(cfg_display "$v" "$f")"
            if [ -n "$d" ]; then
                printf '      %s\n' "$d"
            fi
            if [ -n "$e" ]; then
                printf '      e.g. %s\n' "$e"
            fi
        done
        echo
        read -rp "Variable number [q to quit]: " choice || { echo; return 0; }
        case "$choice" in
            q|Q|quit|exit) echo; return 0 ;;
            r|R|refresh) continue ;;
            "") continue ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#keys[@]} )); then
                    _cfg_edit_one "$file" "${keys[$((choice - 1))]}"
                else
                    warn "invalid number '$choice' (1-${#keys[@]})"
                fi
                ;;
        esac
    done
}
