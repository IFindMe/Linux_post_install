# lib/config-ui.sh — interactive, self-describing config UI for the pos tools.
# Reads each tool's "# POS_CONFIG:" header — the config registry — and renders
# a numbered menu per scope to view/edit values in the matching env file.
# Self-contained: uses common.sh helpers when available, with guarded fallbacks
# (mirrors lib/notify.sh). Sourced opt-in by bin/pos-config.
#
# Header grammar — one "# POS_CONFIG:" line per scope a tool exposes:
#   # POS_CONFIG: <scope> | <env-file> | <field> | ... | *plugins
#     <env-file>  basename of the config file under ~/.config/linux_post_install/
#     <field> := <KEY>=<flags>:<desc>[::<example>]
#              | @<caption>                        group caption (unconditional)
#              | @[<KEY>=<alt>[|…]] <caption>      conditional group caption —
#                                                  active iff KEY's current value
#                                                  equals a listed alt; an empty
#                                                  alt segment ("gemini|") means
#                                                  "or unset (= default)"
#     <flags>     secret (masked display + stty -echo input) | digits | num | float
#     <example>   optional value format hint shown in the editor, e.g. "weather,5m joke,10m"
#     *plugins    marker: also list every key declared by the installed
#                 entertainment plugins' "# POS_KEYS:" headers (dynamic)
#     *providers[=<tag>]  marker: keys from lib/ai-providers/*.sh adapters;
#                 with =<tag>, only from <tag>.sh (zero match → warn + the
#                 preceding caption is suppressed)
#   Example:
#     # POS_CONFIG: telegram | telegram.env | TELEGRAM_BOT_TOKEN=secret:Bot token | TELEGRAM_CHAT_ID=digits:Numeric chat id
#
# Usage (opt-in):
#   source "$(dirname "$0")/../lib/config-ui.sh" 2>/dev/null || source "$(dirname "$0")/config-ui.sh"
#   cfg_scopes            # list all declared scopes (deduped, sorted)
#   cfg_ui <scope>        # interactive numbered-menu editor for one scope

CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/linux_post_install}"

# common.sh helpers (guarded so the lib is safe if common.sh wasn't loaded)
declare -F log  >/dev/null || log()  { echo "[+] $*"; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }
declare -F ok   >/dev/null || ok()   { echo "  OK $*"; }

# Color tokens (guarded — mirrors lib/menu-lib.sh): degrade to plain text when
# common.sh didn't define them, never an error on standalone sourcing.
BOLD="${BOLD:-}"
DIM="${DIM:-}"
CYAN="${CYAN:-}"
RESET="${RESET:-}"

_cfg_scope=""               # scope being edited (drives the post-write hook)
declare -A _cfg_seen=()     # key dedupe registry for cfg_scope_keys
_CS=$'\x1f'                 # unit-separator for caption records — never in env
                            # names or alt strings, avoids collision with | in
                            # alternation syntax (AI_PROVIDER=gemini|)

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

# Split a POS_CONFIG keystring into fields on "|", IGNORING separators inside
# [...] condition brackets (caption conditions legitimately contain pipes,
# e.g. @[AI_PROVIDER=gemini|]). Byte-identical output to IFS='|' splitting for
# any string without brackets — fully backward compatible.
_cfg_split_fields() {   # $1=keystring → one field per line
    local s="$1" cur="" i ch depth=0
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        if [ "$ch" = "[" ]; then
            depth=$((depth + 1))
        elif [ "$ch" = "]" ] && [ "$depth" -gt 0 ]; then
            depth=$((depth - 1))
        fi
        if [ "$ch" = "|" ] && [ "$depth" -eq 0 ]; then
            printf '%s\n' "$cur"
            cur=""
        else
            cur+="$ch"
        fi
    done
    printf '%s\n' "$cur"
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
    pdir="$(ent_plugin_dir)"
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

# Emit the "# PROVIDER_CONFIG:" keys of ONE adapter file (helper for
# _cfg_provider_keys; keeps the tag-filter path and the all-adapters path DRY).
_cfg_provider_file() {
    local pfile="$1" line key desc flags rest
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # Format: KEY=flags:description (same as POS_CONFIG key fields)
        key="${line%%=*}"
        [ -n "$key" ] || continue
        [ -n "${_cfg_seen[$key]:-}" ] && continue
        _cfg_seen[$key]=1
        rest="${line#*=}" flags="" desc=""
        if [[ "$rest" == *":"* ]]; then
            flags="${rest%%:*}"
            desc="${rest#*:}"
        else
            flags="$rest"
        fi
        printf '%s|%s|%s|\n' "$key" "$flags" "$desc"
    done < <(grep '^# PROVIDER_CONFIG:' "$pfile" 2>/dev/null | sed 's/^.*# PROVIDER_CONFIG:[[:space:]]*//' || true)
    return 0
}

# "*providers" expansion: keys declared by the installed AI provider
# adapters' "# PROVIDER_CONFIG:" headers (lib/ai-providers/*.sh).
# Optional <tag> argument restricts to <tag>.sh; an explicit tag matching zero
# adapters warns once (stderr) — silent emptiness would hide authoring errors,
# and the preceding caption is suppressed by cfg_ui's lazy flush. Bare
# *providers stays silent, exactly as today.
declare -A _CFG_TAG_WARNED=()
_cfg_provider_keys() {
    local want_tag="${1:-}"
    local pdir line key desc flags
    # Repo layout: lib/config-ui.sh → ../lib/ai-providers/
    # Installed layout: /usr/local/bin/config-ui.sh → ./ai-providers/
    pdir=""
    local candidate
    for candidate in \
        "$(dirname "${BASH_SOURCE[0]}")/../lib/ai-providers" \
        "$(dirname "${BASH_SOURCE[0]}")/ai-providers"; do
        if [ -d "$candidate" ]; then
            pdir="$(cd "$candidate" 2>/dev/null && pwd)"
            break
        fi
    done
    [ -n "$pdir" ] || return 0
    if [ -n "$want_tag" ]; then
        local matched=0 pfile
        for pfile in "$pdir"/*.sh; do
            [ -f "$pfile" ] || continue
            [ "$(basename "$pfile" .sh)" = "$want_tag" ] || continue
            matched=1
            _cfg_provider_file "$pfile"
        done
        if [ "$matched" -eq 0 ] && [ -z "${_CFG_TAG_WARNED[$want_tag]:-}" ]; then
            _CFG_TAG_WARNED["$want_tag"]=1
            printf '[!] config scope: *providers=%s matched no adapter in %s\n' "$want_tag" "$pdir" >&2
        fi
        return 0
    fi
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        # Format: KEY=flags:description (same as POS_CONFIG key fields)
        key="${line%%=*}"
        [ -n "$key" ] || continue
        [ -n "${_cfg_seen[$key]:-}" ] && continue
        _cfg_seen[$key]=1
        rest="${line#*=}" flags="" desc=""
        if [[ "$rest" == *":"* ]]; then
            flags="${rest%%:*}"
            desc="${rest#*:}"
        else
            flags="$rest"
        fi
        printf '%s|%s|%s|\n' "$key" "$flags" "$desc"
    done < <(grep '^# PROVIDER_CONFIG:' "$pdir"/*.sh 2>/dev/null | sed 's/^.*# PROVIDER_CONFIG:[[:space:]]*//' || true)
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
        mapfile -t fields < <(_cfg_split_fields "$keystring")
        for field in "${fields[@]}"; do
            field="${field#"${field%%[![:space:]]*}"}"
            field="${field%"${field##*[![:space:]]}"}"
            if [ -n "$field" ]; then
                if [[ "$field" == "@"* ]]; then
                    # Caption record (key position ">"): >|cond|caption|
                    #   @[KEY=alt1|alt2] Caption  →  cond "KEY=alt1|alt2"
                    #   @Caption                  →  cond "" (always active)
                    local cond="" cap=""
                    if [[ "$field" == "@["*"]"* ]]; then
                        cond="${field:2}"
                        cond="${cond%%]*}"
                        cap="${field#*]}"
                        cap="${cap# }"
                    else
                        cap="${field#@}"
                        cap="${cap# }"
                    fi
                    printf '%s\n' ">${_CS}${cond}${_CS}${cap}${_CS}"
                elif [[ "$field" == "*"* ]]; then
                    case "$field" in
                        *plugins*)  _cfg_plugin_keys ;;
                        *providers*)
                            local ptag=""
                            [[ "$field" == *"="* ]] && ptag="${field#*=}"
                            _cfg_provider_keys "$ptag" ;;
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

# Evaluate a caption condition against the env file: active iff KEY's current
# value equals any listed alt, or an empty alt segment is present and the value
# is unset/empty (trailing/double/leading pipe). Empty cond → always active.
_cfg_cond_active() {   # file cond
    [ -n "$2" ] || return 0
    local key alts cur alt hit=0 has_empty=0 oldIFS
    key="${2%%=*}"
    alts="${2#*=}"
    cur="$(cfg_value "$1" "$key")"
    case "$alts" in
        "|"*|*"||"*|*"|") has_empty=1 ;;
    esac
    oldIFS="$IFS"
    IFS='|'
    for alt in $alts; do
        if [ -n "$alt" ] && [ "$alt" = "$cur" ]; then hit=1; break; fi
    done
    IFS="$oldIFS"
    [ "$hit" -eq 1 ] && return 0
    [ "$has_empty" -eq 1 ] && [ -z "$cur" ] && return 0
    return 1
}

# Word-wrap <text> to <width> columns, prefixing EVERY line with <indent>
# (hanging indent). Breaks at spaces only, no hyphenation; over-long tokens
# pass through unbroken.
_cfg_wrap() {   # text width indent
    local text="$1" width="$2" indent="$3"
    local line="" w
    for w in $text; do
        if [ -z "$line" ]; then
            line="$w"
        elif (( ${#line} + 1 + ${#w} <= width )); then
            line="$line $w"
        else
            printf '%s%s\n' "$indent" "$line"
            line="$w"
        fi
    done
    [ -n "$line" ] && printf '%s%s\n' "$indent" "$line"
    return 0
}

# Interactive numbered-menu editor for one scope. q quits; r re-renders.
#
# Rendering contract (menu-lib house pattern): the whole render block goes to
# stderr — display only, nothing on stdout. Caption records ('>') group keys;
# conditions are evaluated per render from the env file, so an edit flips group
# emphasis on the very next redraw. Inactive groups are dimmed with a textual
# reason — never hidden — so numbering stays stable across edits.
cfg_ui() {
    local scope="$1" envfile file line idx
    envfile="$(cfg_scope_envfile "$scope")" || { warn "unknown config scope '$scope'"; return 1; }
    file="$CONFIG_DIR/$envfile"
    _cfg_scope="$scope"

    # Collect records: KEY|flags|desc|example for keys, >|cond|caption| for captions
    local -a recs=() nums=()
    mapfile -t recs < <(cfg_scope_keys "$scope")
    if [ ${#recs[@]} -eq 0 ]; then
        warn "no config keys declared for scope '$scope'"
        return 1
    fi
    # number→record map: numbers go to keys only, in static header order →
    # stable across renders and provider switches
    for idx in "${!recs[@]}"; do
        [[ "${recs[$idx]}" == ">"* ]] || nums+=("$idx")
    done

    # Wrap width clamped to 60–120 cols minus the 6-column hanging indent
    local W="${COLUMNS:-80}"
    (( W < 60 )) && W=60
    (( W > 120 )) && W=120
    local wrapW=$((W - 6))
    local rule
    rule="$(printf '─%.0s' $(seq 1 40))"

    local choice k f d e v disp n dim pend_cap="" pend_cond="" ckey cval why
    while true; do
        {
            echo
            echo "${BOLD}pos config — ${scope} (${envfile})${RESET}"
            echo "${CYAN}${rule}${RESET}"
            n=0; dim=0; pend_cap=""; pend_cond=""
            for idx in "${!recs[@]}"; do
                # Caption records use \x1f (unit separator) to avoid collision
                # with | in alternation syntax; key records use | as before.
                if [[ "${recs[$idx]}" == ">"* ]]; then
                    # Caption record: >\x1fcond\x1fcaption\x1f
                    # Strip leading > and first \x1f, then split on next \x1f
                    pend_cond="${recs[$idx]#>}"
                    pend_cond="${pend_cond#$_CS}"
                    pend_cond="${pend_cond%%$_CS*}"
                    pend_cap="${recs[$idx]#>}"
                    pend_cap="${pend_cap#$_CS}"
                    pend_cap="${pend_cap#*$_CS}"
                    pend_cap="${pend_cap%%$_CS*}"
                    continue
                fi
                IFS='|' read -r k f d e <<<"${recs[$idx]}"
                if [ -n "$pend_cap" ]; then
                    if _cfg_cond_active "$file" "$pend_cond"; then
                        dim=0
                        printf '\n%s  ── %s%s\n' "$DIM" "$pend_cap" "$RESET"
                    else
                        dim=1
                        ckey="${pend_cond%%=*}"
                        cval="$(cfg_value "$file" "$ckey")"
                        if [ -z "$cval" ]; then why="— inactive (${ckey} not set)"
                        else why="— inactive while ${ckey}=${cval}"; fi
                        printf '\n%s  ── %s %s%s\n' "$DIM" "$pend_cap" "$why" "$RESET"
                    fi
                    pend_cap=""
                fi
                n=$((n + 1))
                v="$(cfg_value "$file" "$k")"
                disp="$(cfg_display "$v" "$f")"
                if [ "$disp" = "(not set)" ]; then
                    disp="${DIM}(not set)${RESET}"
                elif [ "$dim" -eq 1 ]; then
                    # Inactive group: key name stays bold/colored (readable);
                    # only the value dims — the caption already carries the
                    # inactive reason, so a fully grey block adds no signal.
                    disp="${DIM}${disp}${RESET}"
                fi
                printf '  %s%2d)%s %s%-28s%s %s\n' "$DIM" "$n" "$RESET" "$BOLD" "$k" "$RESET" "$disp"
                if [ -n "$d" ]; then
                    [ "$dim" -eq 1 ] && printf '%s' "$DIM"
                    _cfg_wrap "$d" "$wrapW" "      "
                    [ "$dim" -eq 1 ] && printf '%s' "$RESET"
                fi
                if [ -n "$e" ]; then
                    printf '%s' "$DIM"
                    _cfg_wrap "e.g. $e" "$wrapW" "      "
                    printf '%s' "$RESET"
                fi
            done
            echo
            read -rp "Number to edit [r=refresh, q=quit]: " choice || { echo; return 0; }
        } >&2
        case "$choice" in
            q|Q|quit|exit) echo; return 0 ;;
            r|R|refresh) continue ;;
            "") continue ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#nums[@]} )); then
                    _cfg_edit_one "$file" "${recs[${nums[$((choice - 1))]}]}"
                else
                    warn "invalid number '$choice' (1-${#nums[@]})"
                fi
                ;;
        esac
    done
}
