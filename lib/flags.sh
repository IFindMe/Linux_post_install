# ── Feature flag store ─────────────────────────────────────────
# System-wide flags: one file per flag in $FLAGS_DIR.
#   presence = flag set, file content = optional value.
# Sourced by scripts; reads are plain file ops, writes use sudo.
# Override FLAGS_DIR via environment for testing.
FLAGS_DIR="${FLAGS_DIR:-/usr/local/share/linux_post_install/flags}"

# flag_set <name> [value] — mark a flag as set (green), optionally with a value
flag_set() {
    local name="$1" value="${2:-}" tmp
    run sudo install -d -m 755 "$FLAGS_DIR"
    if [ -n "$value" ]; then
        tmp=$(mktemp)
        printf '%s' "$value" > "$tmp"
        run sudo install -m 644 "$tmp" "$FLAGS_DIR/$name"
        rm -f "$tmp"
    else
        run sudo touch "$FLAGS_DIR/$name"
    fi
}

# flag_clear <name> — remove a flag
flag_clear() {
    run sudo rm -f "$FLAGS_DIR/$1"
}

# flag_is_set <name> — 0 if flag is set, 1 otherwise
flag_is_set() {
    [ -f "$FLAGS_DIR/$1" ]
}

# flag_value <name> — print the stored value (empty when unset or valueless)
flag_value() {
    local f="$FLAGS_DIR/$1"
    [ -f "$f" ] && cat "$f"
}

# flag_list — print the names of all set flags, one per line
flag_list() {
    [ -d "$FLAGS_DIR" ] || return 0
    for f in "$FLAGS_DIR"/*; do
        [ -f "$f" ] || continue
        printf '%s\n' "$(basename "$f")"
    done
}

# flag_status <name> — print a human-readable status line
flag_status() {
    local name="$1" v
    if flag_is_set "$name"; then
        v=$(flag_value "$name")
        if [ -n "$v" ]; then
            echo "set: $name=$v"
        else
            echo "set: $name"
        fi
    else
        echo "unset: $name"
    fi
}
