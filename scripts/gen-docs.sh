#!/usr/bin/env bash
set -euo pipefail
# Regenerate code-derived doc sections between GEN markers.
#
#   scripts/gen-docs.sh          rewrite files in place
#   scripts/gen-docs.sh --check  verify only; exit 1 on any drift
#
# Sources of truth:
#   - bin/pos-* filenames  → category, subcommand
#   - "# POS:" header line → one-line description
#   - "# POS_FLAGS:" line  → flag completion list (flag-style tools only)

root="$(cd "$(dirname "$0")/.." && pwd)"
mode="write"
[ "${1:-}" = "--check" ] && mode="check"

ctx="$root/DOC/AGENT_Context_Project.md"
comp="$root/completions/pos.bash"

# ── Collect tools: "cat|sub|desc|flags" ────────────────────────
tools=()
for f in "$root"/bin/pos-*; do
    [ -x "$f" ] || continue
    name="${f##*/pos-}"
    cat="${name%%-*}"
    sub="${name#*-}"
    desc="$(sed -n '/^# POS: /{s/^# POS: //;p;q}' "$f")"
    [ -n "$desc" ] || { echo "gen-docs: no '# POS:' header in $f" >&2; exit 1; }
    desc="${desc#*— }"
    flags="$(sed -n '/^# POS_FLAGS: /{s/^# POS_FLAGS: //;p;q}' "$f")"
    tools+=("$cat|$sub|$desc|$flags")
done
mapfile -t tools < <(printf '%s\n' "${tools[@]}" | sort)

# ── Block generators (emit inner content only, no markers) ──────
gen_tree() {
    local width=0 cat sub desc flags name t
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags <<<"$t"
        name="pos-$cat-$sub"
        [ ${#name} -gt "$width" ] && width=${#name}
    done
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags <<<"$t"
        name="pos-$cat-$sub"
        printf '│   ├── %-*s# %s\n' "$((width + 1))" "$name" "$desc"
    done
}

gen_dispatch() {
    local cat sub desc flags t
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags <<<"$t"
        printf '| %s | %s | `pos-%s-%s` | %s |\n' "$cat" "$sub" "$cat" "$sub" "$desc"
    done
}

gen_selfcontained() {
    local list=() f base out=""
    for f in "$root"/bin/pos "$root"/bin/pos-*; do
        [ -x "$f" ] || continue
        base="$(basename "$f")"
        grep -q 'common\.sh' "$f" || list+=("$base")
    done
    for b in "${list[@]}"; do
        out+="\`$b\`, "
    done
    echo "${out%, }."
}

gen_filetable() {
    local cat sub desc flags name t
    printf '| `bin/pos` | %s | CLI dispatcher with smart arg matching + logging + category help |\n' "$(wc -l < "$root/bin/pos")"
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags <<<"$t"
        name="bin/pos-$cat-$sub"
        printf '| `%s` | %s | %s |\n' "$name" "$(wc -l < "$root/$name")" "$desc"
    done
    printf '| `completions/pos.bash` | %s | Dynamic bash completion |\n' "$(wc -l < "$comp")"
}

gen_posflags() {
    local cat sub desc flags t
    echo "declare -A _pos_flags"
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags <<<"$t"
        [ -n "$flags" ] || continue
        printf '_pos_flags[%s-%s]="%s"\n' "$cat" "$sub" "$flags"
    done
}

# ── Replace (write) or verify (check) one marker block ──────────
regen_block() {
    local file="$1" name="$2"
    local start end newfile tmp
    case "$file" in
        *.bash|*.sh) start="# GEN:START $name"; end="# GEN:END $name" ;;
        *)           start="<!-- GEN:START $name -->"; end="<!-- GEN:END $name -->" ;;
    esac
    newfile="$(mktemp)"
    "gen_$name" > "$newfile"

    grep -qF "$start" "$file" || { echo "gen-docs: missing marker '$start' in $file" >&2; rm -f "$newfile"; exit 1; }

    if [ "$mode" = "check" ]; then
        local cur
        cur="$(sed -n "/^$start$/,/^$end$/p" "$file" | sed '1d;$d')"
        if [ "$cur" != "$(cat "$newfile")" ]; then
            echo "gen-docs: DRIFT in $file ($name block)" >&2
            diff <(printf '%s\n' "$cur") <(cat "$newfile") >&2 || true
            rm -f "$newfile"
            exit 1
        fi
    else
        tmp="$(mktemp)"
        awk -v start="$start" -v end="$end" -v nf="$newfile" '
            $0==start {
                print
                while ((getline line < nf) > 0) print line
                skip=1
                next
            }
            skip && $0==end { skip=0; print; next }
            skip { next }
            { print }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
    fi
    rm -f "$newfile"
}

regen_block "$ctx" tree
regen_block "$ctx" dispatch
regen_block "$ctx" selfcontained
regen_block "$comp" posflags
regen_block "$ctx" filetable

echo "gen-docs: $mode OK"
