#!/usr/bin/env bash
# lib/bank-lib.sh — shared storage helpers for the Command Bank.
# Sourced by bin/pos-system-bank. Uses err() from lib/common.sh.
#
# Storage: ~/.config/linux_post_install/bank.env
# Format:  name|description|command
# v2: commands with real newlines are saved with \\ (backslash) and \n
#     (newline) escapes; files written by v1 have no marker and load raw.
#
# Contracts:
#   * Defines ONLY bank_* functions — sourcing never clobbers a tool's helpers.
#   * Requires common.sh to be sourced by the CALLER.
#   * NEVER exits — return codes only.
#   * Performs NO interactive prompts (those stay in bin/pos-system-bank).

CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/linux_post_install}"
BANK_FILE="${BANK_FILE:-${CONFIG_DIR}/bank.env}"

# ── Load ────────────────────────────────────────────────────────
# Populate parallel arrays: BANK_NAMES, BANK_DESCS, BANK_CMDS.
bank_load() {
    BANK_NAMES=(); BANK_DESCS=(); BANK_CMDS=()
    [ -f "$BANK_FILE" ] || return 0

    local line name desc cmd v2=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && { [[ "$line" == *"BANK_VERSION: 2"* ]] && v2=1; continue; }
        [[ -z "${line// /}" ]] && continue
        IFS='|' read -r name desc cmd <<< "$line"
        [[ -z "$name" ]] && continue
        [ "$v2" -eq 1 ] && cmd="$(printf '%b' "$cmd")"
        BANK_NAMES+=("$name")
        BANK_DESCS+=("${desc:-}")
        BANK_CMDS+=("${cmd:-}")
    done < "$BANK_FILE"
}

# ── Save ────────────────────────────────────────────────────────
# Atomic overwrite from parallel arrays.
bank_save() {
    local dir
    dir="$(dirname "$BANK_FILE")"
    mkdir -p "$dir"
    local tmp
    tmp="$(mktemp "${dir}/.bank.XXXXXX")"
    {
        printf '%s\n' "# Command Bank — managed by pos bank (do not hand-edit)"
        printf '%s\n' "# Format: name|description|command (\\n = escaped newline in command)"
        printf '%s\n' "# BANK_VERSION: 2"
        local i
        for ((i = 0; i < ${#BANK_NAMES[@]}; i++)); do
            local cmd="${BANK_CMDS[$i]}"
            # Escape: every backslash → \\, every real newline → \n (keeps one record per physical line)
            cmd="${cmd//\\/\\\\}"
            cmd="${cmd//$'\n'/\\n}"
            printf '%s|%s|%s\n' "${BANK_NAMES[$i]}" "${BANK_DESCS[$i]}" "$cmd"
        done
    } > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$BANK_FILE"
}

# ── Add ─────────────────────────────────────────────────────────
bank_add() {
    local name="$1" desc="$2" cmd="$3"
    bank_load
    local i
    for ((i = 0; i < ${#BANK_NAMES[@]}; i++)); do
        [[ "${BANK_NAMES[$i]}" == "$name" ]] && return 1
    done
    BANK_NAMES+=("$name")
    BANK_DESCS+=("$desc")
    BANK_CMDS+=("$cmd")
    bank_save
}

# ── Remove ──────────────────────────────────────────────────────
bank_remove() {
    local name="$1"
    bank_load
    local found=0 i
    for ((i = 0; i < ${#BANK_NAMES[@]}; i++)); do
        if [[ "${BANK_NAMES[$i]}" == "$name" ]]; then
            unset 'BANK_NAMES[i]'
            unset 'BANK_DESCS[i]'
            unset 'BANK_CMDS[i]'
            found=1
            break
        fi
    done
    [[ "$found" -eq 1 ]] || return 1
    # Re-index arrays (unset leaves gaps)
    BANK_NAMES=("${BANK_NAMES[@]}")
    BANK_DESCS=("${BANK_DESCS[@]}")
    BANK_CMDS=("${BANK_CMDS[@]}")
    bank_save
}

# ── Update ──────────────────────────────────────────────────────
bank_update() {
    local name="$1" desc="$2" cmd="$3"
    bank_load
    local i
    for ((i = 0; i < ${#BANK_NAMES[@]}; i++)); do
        if [[ "${BANK_NAMES[$i]}" == "$name" ]]; then
            BANK_DESCS[$i]="$desc"
            BANK_CMDS[$i]="$cmd"
            bank_save
            return 0
        fi
    done
    return 1
}

# ── Find (by name) ──────────────────────────────────────────────
# Sets BANK_IDX. Returns 0 if found, 1 if not.
bank_find() {
    local name="$1"
    bank_load
    local i
    for ((i = 0; i < ${#BANK_NAMES[@]}; i++)); do
        if [[ "${BANK_NAMES[$i]}" == "$name" ]]; then
            BANK_IDX=$i
            return 0
        fi
    done
    return 1
}

# ── Get (by name) ───────────────────────────────────────────────
# Outputs: name\tdescription\tcommand (tab-separated).
bank_get() {
    local name="$1"
    bank_find "$name" || return 1
    printf '%s\t%s\t%s\n' "${BANK_NAMES[$BANK_IDX]}" "${BANK_DESCS[$BANK_IDX]}" "${BANK_CMDS[$BANK_IDX]}"
}

# ── List names ──────────────────────────────────────────────────
bank_list_names() {
    bank_load
    local i
    for ((i = 0; i < ${#BANK_NAMES[@]}; i++)); do
        printf '%s\n' "${BANK_NAMES[$i]}"
    done
}

# ── Count ───────────────────────────────────────────────────────
bank_count() {
    bank_load
    echo "${#BANK_NAMES[@]}"
}

# ── Validate name ───────────────────────────────────────────────
bank_valid_name() {
    [[ "$1" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]
}

# ── Extract {param} names from a command template ───────────────
_extract_params() {
    local cmd="$1"
    grep -oE '\{[a-zA-Z_][a-zA-Z0-9_]*\}' <<< "$cmd" 2>/dev/null | \
        sed 's/[{}]//g' | \
        awk '!seen[$0]++' || true
}

# ── Substitute {param} with quoted values ───────────────────────
# Usage: _substitute_params "cmd template" "key1=val1" "key2=val2" ...
# Uses awk to build quoted replacements safely, avoiding bash quote-nesting.
_substitute_params() {
    local cmd="$1"; shift
    # Build a sed expression: for each key=val, replace {key} with "val"
    local sed_expr=""
    while [ $# -gt 0 ]; do
        local key="${1%%=*}"
        local val="${1#*=}"
        # Escape sed special chars in the value
        val="${val//\\/\\\\}"
        val="${val//\//\\/}"
        sed_expr+="s/{${key}}/\"${val}\"/g; "
        shift
    done
    [ -n "$sed_expr" ] && printf '%s' "$cmd" | sed "$sed_expr" || printf '%s' "$cmd"
}
