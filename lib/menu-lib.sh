# lib/menu-lib.sh — category-neutral interactive menu primitives.
#
# The generic half of the former share-lib interactive layer (Pattern B),
# extracted so any `pos` tool can share one interaction vocabulary: a tty
# guard, a looping boxed menu, a type-to-filter picker and a prompt with
# optional default. Display goes to stderr, results to stdout; reads are
# stdin-based and fail closed (EOF / no terminal → rc 1, never a hang),
# so the functions are safe under the dispatcher's logging tee and inside
# command substitution.
#
# Contracts (all of them, no exceptions):
#   * Defines ONLY `menu_*` functions — sourcing never clobbers a tool's own
#     helpers (same discipline as lib/notify.sh).
#   * Requires common.sh to be sourced by the CALLER for colored output;
#     CYAN/RESET get empty guarded fallbacks here so the lib also works
#     standalone-sourced (plain text instead of color — never an error).
#   * NEVER exits and never terminates the caller: every function returns,
#     failures are signalled through the return code.
#   * Display goes to stderr, results go to stdout — any function whose result
#     is meant to be command-substituted prints ONLY the result on stdout.
#   * Performs NO file writes of its own.
#
# Function index:
#   menu_guard                          rc 0 iff stdin is a terminal
#   menu_run <title> <item...>          numbered menu loop → chosen index
#   menu_pick <prompt> <item...>        type-to-filter picker → chosen index
#   menu_ask_value <label> [default]    prompted value → entered text

# ── Colors (guarded fallbacks; a sourced common.sh wins) ──────
CYAN="${CYAN:-}"
RESET="${RESET:-}"

# ── Terminal guard ────────────────────────────────────────────
# rc 0 iff stdin is a tty · rc 1 otherwise, with a one-line pointer to the
# scriptable subcommands. Tools that must fail hard without a TTY call this
# before entering the loop.
menu_guard() {
    if [ -t 0 ]; then
        return 0
    fi
    printf '[!] Interactive menu needs a terminal — use a subcommand instead (see --help).\n' >&2
    return 1
}

# ── Numbered menu loop (firewall-precedent style) ──────────────
# Renders a section-box title + `%2d)` items + separator to stderr and reads
# `Choose: `. stdout carries the chosen index ONLY.
#   rc 0  valid pick (index on stdout)
#   rc 1  quit (`0`/`q`/`Q`), EOF, or no terminal — callers treat this as a
#         clean menu exit (tools that must fail hard without a TTY call
#         menu_guard themselves before entering the loop).
menu_run() {
    local title="$1"; shift
    local -a items=("$@")
    if ! menu_guard; then
        return 1
    fi
    local opt i
    while true; do
        {
            echo
            echo "${CYAN}════════════════════════════════════════════${RESET}"
            echo "${CYAN}  ${title}${RESET}"
            echo "${CYAN}════════════════════════════════════════════${RESET}"
            for ((i = 0; i < ${#items[@]}; i++)); do
                printf ' %2d) %s\n' $((i + 1)) "${items[$i]}"
            done
            printf ' %2d) %s\n' 0 "Exit"
            echo "----------------------------------------"
        } >&2
        if ! read -rp "Choose: " opt; then
            return 1          # EOF — clean menu exit
        fi
        case "$opt" in
            "") ;;            # empty input → redraw
            0 | q | Q) return 1 ;;
            *)
                if [[ "$opt" =~ ^[0-9]+$ ]] && (( opt >= 1 && opt <= ${#items[@]} )); then
                    echo "$opt"
                    return 0
                fi
                echo "Unknown choice." >&2
                ;;
        esac
    done
}

# ── Type-to-filter picker ──────────────────────────────────────
# Lists items on stderr; numeric choice → index (into the FULL item list) on
# stdout; non-numeric input filters case-insensitively and redisplays with a
# "-- N of M match 'text' --" banner; empty or `/` while filtered clears back
# to the full list; zero matches warn and redisplay.
#   rc 0  picked · rc 1  back/cancel (`0`/`q`/`b`, EOF) — never out of bounds.
menu_pick() {
    local prompt="${1:-Pick}"; shift
    local -a items=("$@")
    if [ "${#items[@]}" -eq 0 ]; then
        return 1
    fi
    if ! [ -t 0 ]; then
        printf '[!] Interactive picker needs a terminal.\n' >&2
        return 1
    fi
    local filter="" ans i n total=${#items[@]}
    local -a shown=() orig=()
    while true; do
        shown=()
        orig=()
        for ((i = 0; i < total; i++)); do
            if [ -z "$filter" ] || [[ "${items[$i],,}" == *"${filter,,}"* ]]; then
                shown+=("${items[$i]}")
                orig+=("$((i + 1))")
            fi
        done
        n=${#shown[@]}
        {
            echo
            if [ -n "$filter" ]; then
                printf -- "-- %d of %d match '%s' --\n" "$n" "$total" "$filter"
            else
                printf -- "-- %d available --\n" "$total"
            fi
            if [ "$n" -eq 0 ]; then
                printf '[!] no matches — enter nothing or / to clear the filter\n' >&2
            else
                for ((i = 0; i < n; i++)); do
                    printf ' %2d) %s\n' $((i + 1)) "${shown[$i]}"
                done
            fi
        } >&2
        if ! read -rp "${prompt} [1-${n}], text=filter, 0=back " ans; then
            return 1                     # EOF — cancel
        fi
        case "$ans" in
            "")  [ -z "$filter" ] || filter="" ; continue ;;
            "/") filter="" ; continue ;;
            0 | q | Q | b | B) return 1 ;;
            *[!0-9]*)
                filter="$ans"
                continue
                ;;
            *)
                if (( ans >= 1 && ans <= n )); then
                    echo "${orig[$((ans - 1))]}"
                    return 0
                fi
                echo "Unknown choice." >&2
                ;;
        esac
    done
}

# ── Prompted value with optional default ───────────────────────
# Prints "<label> [<default>]: " (read -p sends prompts to stderr) and echoes
# the entered value or the default when the answer is empty.
#   rc 0  value on stdout · rc 1  EOF, or empty answer with no default.
menu_ask_value() {
    local label="$1" def="${2:-}" val pr="$1"
    [ -n "$def" ] && pr="$pr [$def]"
    if ! read -rp "${pr}: " val; then
        return 1                          # EOF — cancel
    fi
    if [ -z "$val" ]; then
        [ -n "$def" ] || return 1
        echo "$def"
        return 0
    fi
    echo "$val"
}
