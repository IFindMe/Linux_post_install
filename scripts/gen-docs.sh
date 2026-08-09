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
#   - "# POS_SUBCMDS:" line → subcommand completion list (multi-command tools)

root="$(cd "$(dirname "$0")/.." && pwd)"
mode="write"
[ "${1:-}" = "--check" ] && mode="check"

ctx="$root/DOC/AGENT_Context_Project.md"
comp="$root/completions/pos.bash"

# ── Collect tools: "cat|sub|desc|flags|subcmds" ────────────────
# Category-less tools (pos-<cat>, e.g. pos-config) get an empty cat.
# tooldisp <cat> <sub> → display name (pos-config / pos-communication-telegram-sender).
tooldisp() { printf 'pos-%s%s' "${1:+$1-}" "$2"; }
tools=()
for f in "$root"/bin/pos-*; do
    [ -x "$f" ] || continue
    name="${f##*/pos-}"
    if [[ "$name" == *-* ]]; then
        cat="${name%%-*}"
        sub="${name#*-}"
    else
        cat=""
        sub="$name"
    fi
    desc="$(sed -n '/^# POS: /{s/^# POS: //;p;q}' "$f")"
    [ -n "$desc" ] || { echo "gen-docs: no '# POS:' header in $f" >&2; exit 1; }
    desc="${desc#*— }"
    flags="$(sed -n '/^# POS_FLAGS: /{s/^# POS_FLAGS: //;p;q}' "$f")"
    subcmds="$(sed -n '/^# POS_SUBCMDS: /{s/^# POS_SUBCMDS: //;p;q}' "$f")"
    tools+=("$cat|$sub|$desc|$flags|$subcmds")
done
mapfile -t tools < <(printf '%s\n' "${tools[@]}" | sort)

# ── Block generators (emit inner content only, no markers) ──────
gen_tree() {
    local width=0 cat sub desc flags name t
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags subcmds <<<"$t"
        name="$(tooldisp "$cat" "$sub")"
        [ ${#name} -gt "$width" ] && width=${#name}
    done
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags subcmds <<<"$t"
        name="$(tooldisp "$cat" "$sub")"
        printf '│   ├── %-*s# %s\n' "$((width + 1))" "$name" "$desc"
    done
}

gen_dispatch() {
    local cat sub desc flags t
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags subcmds <<<"$t"
        printf '| %s | %s | `%s` | %s |\n' "$cat" "$sub" "$(tooldisp "$cat" "$sub")" "$desc"
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
        IFS='|' read -r cat sub desc flags subcmds <<<"$t"
        name="bin/$(tooldisp "$cat" "$sub")"
        printf '| `%s` | %s | %s |\n' "$name" "$(wc -l < "$root/$name")" "$desc"
    done
    printf '| `completions/pos.bash` | %s | Dynamic bash completion |\n' "$(wc -l < "$comp")"
}

gen_posflags() {
    local cat sub desc flags t
    echo "declare -A _pos_flags"
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags subcmds <<<"$t"
        [ -n "$flags" ] || continue
        printf '_pos_flags[%s]="%s"\n' "$(tooldisp "$cat" "$sub" | sed 's/^pos-//')" "$flags"
    done
}

gen_possubcmds() {
    # Subcommand completion: "# POS_SUBCMDS:" list + nested sub-tools from
    # filenames (pos-<cat>-<sub>-<extra> → "extra" completes under <cat>-<sub>).
    local cat sub desc flags subcmds rest f t
    echo "declare -A _pos_subcmds"
    for t in "${tools[@]}"; do
        IFS='|' read -r cat sub desc flags subcmds <<<"$t"
        subcmds="${subcmds:-}"
        for f in "$root"/bin/"$(tooldisp "$cat" "$sub")"-*; do
            [ -x "$f" ] || continue
            rest="${f##*/$(tooldisp "$cat" "$sub")-}"
            case " $subcmds " in
                *" $rest "*) ;;
                *) subcmds="${subcmds:+$subcmds }$rest" ;;
            esac
        done
        [ -n "$subcmds" ] || continue
        printf '_pos_subcmds[%s]="%s"\n' "$(tooldisp "$cat" "$sub" | sed 's/^pos-//')" "$subcmds"
    done
}

# Config scopes: the "# POS_CONFIG:" registry (first field = scope), cached so
# `pos config <TAB>` doesn't re-scan every tool per completion.
gen_posconfigscopes() {
    local f line scope scopes=()
    for f in "$root"/bin/pos-*; do
        [ -x "$f" ] || continue
        while IFS= read -r line; do
            line="${line#*POS_CONFIG:}"
            scope="${line%%|*}"
            scope="${scope// }"
            [ -n "$scope" ] && scopes+=("$scope")
        done < <(grep '^# POS_CONFIG:' "$f" 2>/dev/null || true)
    done
    mapfile -t scopes < <(printf '%s\n' "${scopes[@]}" | sort -u)
    echo "declare -a _pos_config_scopes=(${scopes[*]:-})"
}

# Section index of AGENT_Context itself: maps each "## " heading to its
# line range. Excludes the "Document Map" heading (this block).
gen_docmap() {
    local file="$ctx" lines=() sections=() line n title i last
    mapfile -t lines < <(grep -nE '^## ' "$file")
    for line in "${lines[@]}"; do
        title="${line#*:}"
        [[ "$title" == "## Document Map" ]] && continue
        sections+=("$line")
    done
    for i in "${!sections[@]}"; do
        n="${sections[$i]%%:*}"
        title="${sections[$i]#*:}"
        if [ "$i" -eq $((${#sections[@]} - 1)) ]; then
            last=$(wc -l < "$file")
        else
            last=$(( ${sections[$((i + 1))]%%:*} - 1 ))
        fi
        printf '| %s | %s–%s |\n' "$title" "$n" "$last"
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
        # mktemp creates 0600 files — mv would leave the doc/completion at 0600
        chmod 644 "$tmp"
        mv "$tmp" "$file"
    fi
    rm -f "$newfile"
}

regen_block "$ctx" tree
regen_block "$ctx" dispatch
regen_block "$ctx" selfcontained
regen_block "$comp" posflags
regen_block "$comp" possubcmds
regen_block "$comp" posconfigscopes
regen_block "$ctx" filetable

# docmap is self-referential: its own block size shifts the section line
# numbers below it — regenerate until stable (converges in 2-3 passes).
regen_block "$ctx" docmap
if [ "$mode" = "write" ]; then
    for _ in 1 2 3 4 5; do
        prev="$(sed -n '/<!-- GEN:START docmap -->/,/<!-- GEN:END docmap -->/p' "$ctx")"
        regen_block "$ctx" docmap
        after="$(sed -n '/<!-- GEN:START docmap -->/,/<!-- GEN:END docmap -->/p' "$ctx")"
        [ "$prev" = "$after" ] && break
    done
fi

echo "gen-docs: $mode OK"
