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
#   reg_each <callback>     cb(category, tool_key, description)
#   reg_tool_exists <tool>  exit 0 if registered

# ── common.sh helpers (guarded fallbacks) ─────────────────────
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

    done

    # Sort tools
    mapfile -t _reg_tools < <(printf '%s\n' "${_reg_tools[@]}" | sort)

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
