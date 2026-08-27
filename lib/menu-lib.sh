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
#   menu_read_value <label>             raw-mode bracketed-paste reader
#   menu_redraw                         internal redraw (menu_read_value only)

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

# ── Raw-mode value reader (bracketed-paste safe) ───────────────
# Reads ONE value from the terminal in raw mode with bracketed paste enabled,
# so a multi-line CTRL+V paste is inserted LITERALLY — embedded newlines are
# data, never line terminators — and can never leak into the shell or a later
# prompt as leftover keystrokes. A plain bash `read` is line-oriented: it
# consumes only the first pasted line and the remaining lines sit in the tty
# queue, where the next prompt (or the shell after this script exits) treats
# them as input/commands. That is the paste bug this reader exists to prevent.
#
# Editing (single-line typing behaves like a normal prompt):
#   Enter            submit the value (outside a paste)
#   Backspace/DEL    delete the character before the cursor
#   Left/Right       move the cursor; Home/End jump to start/end
#   Delete           delete the character at the cursor
#   Ctrl-U           clear the whole value
#   Ctrl-D (empty)   EOF — cancel   ·   Ctrl-C/Z/\ — cancel · Up/Down — ignored
#   Inside a bracketed paste the above are inert: text (incl. newlines) is
#   inserted verbatim until the paste-end marker; a real Enter then submits.
#
# Display goes to stderr so callers may command-substitute the result:
#   rc 0  value on stdout · rc 1  cancel/EOF/non-tty.
menu_read_value() {
    local label="$1"
    local val="" state="" chunk="" ch="" esc="" seq="" esc_c=""
    local paste=0 pos=0 submit=0 i=0 n=0

    if ! state="$(stty -g 2>/dev/null)"; then
        # not a terminal — plain stdin read; no paste protection is possible
        IFS= read -r val || return 1
        [ -n "$val" ] && printf '%s' "$val"
        return 0
    fi
    if ! stty -icanon -echo -isig min 1 time 0 2>/dev/null; then
        stty "$state" 2>/dev/null
        IFS= read -r val || return 1
        [ -n "$val" ] && printf '%s' "$val"
        return 0
    fi

    local restore
    restore() {
        stty "$state" 2>/dev/null
        printf '\033[?2004l' >&2
    }
    trap 'restore; trap - INT TERM; return 1' INT TERM

    printf '\033[?2004h' >&2
    printf '%s: ' "$label" >&2

    # Next input byte as a 2-hex-digit string, returned via nameref. Uses
    # dd|od, NOT bash's read builtin: read's tty path self-interrupts on an ETX
    # byte even with ISIG disabled (SIGINTs the whole script on Ctrl-C, killing
    # a cmdsubst caller). One dd per input burst (VMIN=1 returns all queued
    # bytes), so pastes cost O(chunks), not O(per-byte forks). Runs in-place
    # (never in a $( ) subshell) so its chunk/offset state persists.
    #   byte <hexvar> — rc 0 = byte in hexvar, rc 1 = EOF/short.
    local byte
    byte() {
        local -n _hex="$1"
        if [ "$i" -ge "$n" ]; then
            chunk="$(dd bs=4096 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')"
            [ -n "$chunk" ] || return 1
            n=${#chunk}
            i=0
        fi
        _hex="${chunk:i:2}"
        i=$((i + 2))
        return 0
    }

    while byte ch; do
        case "$ch" in
            1b)
                seq=""
                while byte esc; do
                    printf -v esc_c '%b' "\\x$esc"
                    seq+="$esc_c"
                    case "$esc_c" in
                        [A-Za-z~]) break ;;
                    esac
                done
                case "$seq" in
                    '[200~') paste=1 ;;
                    '[201~') paste=0 ;;
                    '[C') [ "$pos" -lt "${#val}" ] && { pos=$((pos + 1)); menu_redraw "$label" "$val" "$pos"; } ;;
                    '[D') [ "$pos" -gt 0 ] && { pos=$((pos - 1)); menu_redraw "$label" "$val" "$pos"; } ;;
                    '[H' | '[1~') pos=0; menu_redraw "$label" "$val" "$pos" ;;
                    '[F' | '[4~') pos=${#val}; menu_redraw "$label" "$val" "$pos" ;;
                    '[3~')
                        if [ "$pos" -lt "${#val}" ]; then
                            val="${val:0:pos}${val:pos+1}"
                            menu_redraw "$label" "$val" "$pos"
                        fi
                        ;;
                    '[A' | '[B') : ;;          # up/down: no history — ignore
                esac
                ;;
            0a | 0d)
                if [ "$paste" -eq 1 ]; then
                    # newline inside a paste is literal data (paste as text);
                    # echo the line break so CRLF pastes render at col 0
                    printf -v ch '%b' "\\x$ch"
                    val="${val:0:pos}${ch}${val:pos}"
                    pos=$((pos + 1))
                    printf '%s' "$ch" >&2
                else
                    submit=1
                    break
                fi
                ;;
            7f | 08)                        # Backspace/DEL
                if [ "$pos" -gt 0 ]; then
                    val="${val:0:pos-1}${val:pos}"
                    pos=$((pos - 1))
                    menu_redraw "$label" "$val" "$pos"
                fi
                ;;
            03 | 1a | 1c)                   # Ctrl-C / Ctrl-Z / Ctrl-\ — cancel
                submit=0
                break
                ;;
            04)                             # Ctrl-D: EOF on empty → cancel
                if [ -z "$val" ]; then
                    submit=0
                    break
                fi
                ;;
            15)                             # Ctrl-U: clear
                val=""; pos=0
                menu_redraw "$label" "$val" "$pos"
                ;;
            *)
                printf -v ch '%b' "\\x$ch"
                val="${val:0:pos}${ch}${val:pos}"
                pos=$((pos + 1))
                if [ "$pos" -eq "${#val}" ]; then
                    printf '%s' "$ch" >&2     # append in place — fast path
                else
                    menu_redraw "$label" "$val" "$pos"
                fi
                ;;
        esac
    done

    trap - INT TERM
    restore
    printf '\n' >&2
    if [ "$submit" -eq 0 ]; then
        return 1
    fi
    printf '%s' "$val"
    return 0
}

# ── Internal: redraw the whole input block (menu_read_value only) ──
# The value may span several terminal rows (multiline paste); redraw clears
# below the block start and reprints label + value, then repositions the
# cursor to (row, col) of $3. Columns are counted in characters — wide CJK
# glyphs can be off by one column (display-only; the stored value is exact).
menu_redraw() {
    local label="$1" val="$2" pos="$3"
    local nl="" r="" c="" last="" ec="" d="" up=""
    nl="${val//[^$'\n']/}"
    [ "${#nl}" -gt 0 ] && printf '\033[%dA' "${#nl}" >&2
    printf '\r\033[J' >&2
    printf '%s: ' "$label" >&2
    printf '%s' "$val" >&2
    # target row/col of the cursor
    last="${val:0:pos}"
    r="${last//[^$'\n']/}"; r="${#r}"
    last="${last##*$'\n'}"
    c="${#last}"
    # current cursor (end of block): end row = nl count; end col = after last
    # newline (or 0 when the value ends with a newline)
    ec=0; last="${val##*$'\n'}"
    case "$val" in
        *$'\n') ec=0 ;;
        *) ec="${#last}" ;;
    esac
    [ "${#nl}" -gt "$r" ] && printf '\033[%dA' $(( ${#nl} - r )) >&2
    d=$(( c - ec ))
    if [ "$d" -gt 0 ]; then
        printf '\033[%dC' "$d" >&2
    elif [ "$d" -lt 0 ]; then
        printf '\033[%dD' $(( -d )) >&2
    fi
    return 0
}

# ── Prompted value with optional default ───────────────────────
# Prints "<label> [<default>]: " and echoes the entered value or the default
# when the answer is empty. Uses the bracketed-paste-safe reader, so pasting
# text — including multi-line pastes — inserts it literally instead of letting
# leftover lines escape to the shell as commands.
#   rc 0  value on stdout · rc 1  EOF/cancel, or empty answer with no default.
menu_ask_value() {
    local label="$1" def="${2:-}" val pr="$1"
    [ -n "$def" ] && pr="$pr [$def]"
    if ! val="$(menu_read_value "$pr")"; then
        return 1                          # EOF / cancel
    fi
    if [ -z "$val" ]; then
        [ -n "$def" ] || return 1
        echo "$def"
        return 0
    fi
    echo "$val"
}
