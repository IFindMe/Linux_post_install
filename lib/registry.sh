# lib/registry.sh — shared query API for POS tool metadata headers.
# Sourced opt-in by consumers that need tool metadata.
# Populates bash arrays from "# POS_*:" headers in bin/pos-* files;
# consumers call reg_scan once, then reg_list / reg_lookup / reg_each.
#
# API:
#   reg_scan [dir]          scan pos-* files → populate arrays
#   reg_list                sorted tool keys
#   reg_categories          sorted unique category names
#   reg_tools_in <cat>      tool keys in a category
#   reg_lookup <tool> <field>  field: cat|desc|flags|subcmds|deps|examples
#   reg_config_scopes       sorted config scope names
#   reg_config_keys <scope> key|flags|desc lines
#   reg_config_envfile <scope> env-file basename for a scope
#   reg_each <callback>     cb(category, tool_key, description)
#   reg_tool_exists <tool>  exit 0 if registered

# ── common.sh helpers (guarded — mirrors lib/config-ui.sh) ─────
declare -F log  >/dev/null || log()  { echo "[+] $*"; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }

# ── tool directory detection ────────────────────────────────────
# Repo:   lib/registry.sh → ../bin
# Install: /usr/local/bin/registry.sh → /usr/local/bin (same dir)
_reg_tools_dir() {
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd)"
    if [ -d "$dir" ] && ls "$dir"/pos-* &>/dev/null; then
        echo "$dir"
    else
        dirname "${BASH_SOURCE[0]}"
    fi
}

# ── data stores ─────────────────────────────────────────────────
declare -a _reg_tools=()
declare -A _reg_cat=()
declare -A _reg_desc=()
declare -A _reg_flags=()
declare -A _reg_subcmds=()
declare -A _reg_deps=()
declare -A _reg_examples=()
declare -a _reg_config_scopes=()
declare -A _reg_config_keys=()

# ── reg_scan ────────────────────────────────────────────────────
reg_scan() {
    local dir="${1:-$(_reg_tools_dir)}" f
    local LC_ALL_PREV="${LC_ALL:-}"
    export LC_ALL=C

    _reg_tools=()
    # Clear all associative arrays
    for key in "${!_reg_cat[@]}"; do
        unset "_reg_cat[$key]" "_reg_desc[$key]" "_reg_flags[$key]"
        unset "_reg_subcmds[$key]" "_reg_deps[$key]" "_reg_examples[$key]"
    done
    _reg_config_scopes=()
    for scope in "${!_reg_config_keys[@]}"; do
        unset "_reg_config_keys[$scope]"
    done

    local -A scope_seen=()

    for f in "$dir"/pos-*; do
        [ -x "$f" ] || continue
        local name="${f##*/pos-}"
        local key cat
        key="$name"
        if [[ "$name" == *-* ]]; then
            cat="${name%%-*}"
        else
            cat=""
        fi

        _reg_tools+=("$key")
        _reg_cat["$key"]="$cat"

        # POS: — description (text after first "— ")
        local pos_line
        pos_line="$(sed -n '/^# POS: /{s/^# POS: //;p;q}' "$f" 2>/dev/null)"
        _reg_desc["$key"]="${pos_line#*— }"

        # POS_FLAGS:
        _reg_flags["$key"]="$(sed -n '/^# POS_FLAGS: /{s/^# POS_FLAGS: //;p;q}' "$f" 2>/dev/null)"

        # POS_SUBCMDS:
        _reg_subcmds["$key"]="$(sed -n '/^# POS_SUBCMDS: /{s/^# POS_SUBCMDS: //;p;q}' "$f" 2>/dev/null)"

        # POS_DEPS:
        _reg_deps["$key"]="$(sed -n '/^# POS_DEPS: /{s/^# POS_DEPS: //;p;q}' "$f" 2>/dev/null)"

        # POS_EXAMPLES: (may appear multiple times — join with newlines)
        local examples=""
        examples="$(sed -n '/^# POS_EXAMPLES: /{s/^# POS_EXAMPLES: //;p}' "$f" 2>/dev/null)"
        _reg_examples["$key"]="$examples"

        # POS_CONFIG: (may appear multiple lines per file)
        local line
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            line="${line#*POS_CONFIG:}"
            local scope="${line%%|*}"
            scope="${scope// }"
            [ -n "$scope" ] || continue
            _reg_config_keys["$scope"]+="${_reg_config_keys[$scope]:+$'\n'}$line"
            if [ -z "${scope_seen[$scope]:-}" ]; then
                scope_seen["$scope"]=1
                _reg_config_scopes+=("$scope")
            fi
        done < <(grep '^# POS_CONFIG:' "$f" 2>/dev/null || true)
    done

    # Sort tools
    mapfile -t _reg_tools < <(printf '%s\n' "${_reg_tools[@]}" | sort)
    # Sort config scopes
    mapfile -t _reg_config_scopes < <(printf '%s\n' "${_reg_config_scopes[@]}" | sort -u)

    # Restore LC_ALL
    if [ -n "$LC_ALL_PREV" ]; then
        export LC_ALL="$LC_ALL_PREV"
    else
        unset LC_ALL
    fi
}

# ── discovery ───────────────────────────────────────────────────
reg_list() { printf '%s\n' "${_reg_tools[@]}"; }

reg_categories() {
    local -a cats=()
    local t cat _rc_key
    local -A _rc_seen=()
    for t in "${_reg_tools[@]}"; do
        cat="${_reg_cat[$t]}"
        if [ -z "$cat" ]; then
            _rc_key="__empty__"
        else
            _rc_key="$cat"
        fi
        if [ -z "${_rc_seen[$_rc_key]+x}" ]; then
            _rc_seen["$_rc_key"]=1
            cats+=("$cat")
        fi
    done
    printf '%s\n' "${cats[@]}" | sort
}

reg_tools_in() {
    local cat="$1" t
    for t in "${_reg_tools[@]}"; do
        [ "${_reg_cat[$t]}" = "$cat" ] && echo "$t"
    done
}

# ── lookup ──────────────────────────────────────────────────────
reg_lookup() {
    local tool="$1" field="$2"
    case "$field" in
        cat)      echo "${_reg_cat[$tool]:-}" ;;
        desc)     echo "${_reg_desc[$tool]:-}" ;;
        flags)    echo "${_reg_flags[$tool]:-}" ;;
        subcmds)  echo "${_reg_subcmds[$tool]:-}" ;;
        deps)     echo "${_reg_deps[$tool]:-}" ;;
        examples) echo "${_reg_examples[$tool]:-}" ;;
        *)        return 1 ;;
    esac
}

# ── config scope helpers ────────────────────────────────────────
reg_config_scopes() { printf '%s\n' "${_reg_config_scopes[@]}"; }

reg_config_keys() {
    local scope="$1"
    echo "${_reg_config_keys[$scope]:-}"
}

reg_config_envfile() {
    local scope="$1" line
    line="$(echo "${_reg_config_keys[$scope]:-}" | head -1)"
    [ -n "$line" ] || return 1
    line="${line#*|}"   # drop scope
    local env="${line%%|*}"
    echo "${env// }"
}

# ── iteration ───────────────────────────────────────────────────
reg_each() {
    local cb="$1" t
    for t in "${_reg_tools[@]}"; do
        "$cb" "${_reg_cat[$t]}" "$t" "${_reg_desc[$t]}"
    done
}

# ── convenience ─────────────────────────────────────────────────
reg_tool_exists() {
    [ -n "${_reg_desc[$1]+x}" ]
}
