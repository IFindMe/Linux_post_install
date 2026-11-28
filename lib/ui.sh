#!/usr/bin/env bash
# ── Terminal UI helpers (installer-facing) ──────────────────────
# Pure Bash: no gum/fzf/tput requirement (tput is used only when present).
# Sourced by install.sh, preinstall.sh, postinstall.sh and apps/install.sh.
# Streams: info/success/progress → stdout, warnings/errors/spinner → stderr.

# ── Capability detection ────────────────────────────────────────
_ui_env_init() {
    local term="${TERM:-}" lc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"

    UI_WIDTH_CACHE=""
    UI_BOX_INNER=0
    UI_ACTIVE_PID=""
    UI_ACTIVE_TMP=""
    UI_SPINNER_ACTIVE=0
    UI_TTY=0
    [ -t 1 ] && UI_TTY=1

    if [ -n "${NO_COLOR:-}" ] || [ "${UI_NO_COLOR:-0}" -eq 1 ] ||
       [ "$term" = "dumb" ] || [ "$UI_TTY" -eq 0 ]; then
        UI_GREEN=""; UI_YELLOW=""; UI_RED=""; UI_CYAN=""
        UI_BLUE=""; UI_BOLD=""; UI_DIM=""; UI_RESET=""
    else
        if command -v tput >/dev/null 2>&1; then
            UI_GREEN=$(tput setaf 2 2>/dev/null || printf '\033[32m')
            UI_YELLOW=$(tput setaf 3 2>/dev/null || printf '\033[33m')
            UI_RED=$(tput setaf 1 2>/dev/null || printf '\033[31m')
            UI_CYAN=$(tput setaf 6 2>/dev/null || printf '\033[36m')
            UI_BLUE=$(tput setaf 4 2>/dev/null || printf '\033[34m')
            UI_BOLD=$(tput bold 2>/dev/null || printf '\033[1m')
            UI_DIM=$(tput dim 2>/dev/null || printf '\033[2m')
            UI_RESET=$(tput sgr0 2>/dev/null || printf '\033[0m')
        else
            UI_GREEN=$'\033[32m'; UI_YELLOW=$'\033[33m'; UI_RED=$'\033[31m'
            UI_CYAN=$'\033[36m'; UI_BLUE=$'\033[34m'
            UI_BOLD=$'\033[1m'; UI_DIM=$'\033[2m'; UI_RESET=$'\033[0m'
        fi
    fi

    case "$lc" in
        *UTF-8*|*utf-8*|*UTF8*|*utf8*|"") UI_UNICODE=1 ;;
        *)                                  UI_UNICODE=0 ;;
    esac
    if [ "$UI_UNICODE" -eq 1 ]; then
        UI_SYM_OK="✓"; UI_SYM_WARN="!"; UI_SYM_ERR="✗"; UI_SYM_INFO="·"
        UI_BAR_FULL="█"; UI_BAR_EMPTY="░"
        UI_BOX_TL="┌"; UI_BOX_TR="┐"; UI_BOX_BL="└"; UI_BOX_BR="┘"
        UI_BOX_H="─"; UI_BOX_V="│"; UI_ELLIPSIS="…"
        UI_SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    else
        UI_SYM_OK="+"; UI_SYM_WARN="!"; UI_SYM_ERR="x"; UI_SYM_INFO="-"
        UI_BAR_FULL="="; UI_BAR_EMPTY="-"
        UI_BOX_TL="+"; UI_BOX_TR="+"; UI_BOX_BL="+"; UI_BOX_BR="+"
        UI_BOX_H="-"; UI_BOX_V="|"; UI_ELLIPSIS=""
        UI_SPIN=('|' '/' '-' '\')
    fi
}
_ui_env_init

# ── Internal helpers ────────────────────────────────────────────
_ui_width() {
    local w="${COLUMNS:-}"
    if ! [[ "$w" =~ ^[0-9]+$ ]]; then
        w=""
        if [ "$UI_TTY" -eq 1 ] && command -v tput >/dev/null 2>&1; then
            w=$(tput cols 2>/dev/null || true)
        fi
    fi
    if ! [[ "$w" =~ ^[0-9]+$ ]] || [ "$w" -lt 40 ]; then
        w=80
    elif [ "$w" -gt 120 ]; then
        w=120
    fi
    UI_WIDTH_CACHE="$w"
    printf '%s' "$w"
}

_ui_repeat() {
    local ch="$1" n="$2" out="" i
    for ((i = 0; i < n; i++)); do out+="$ch"; done
    printf '%s' "$out"
}

_ui_trunc() {
    local text="$1" max="$2"
    if [ "$max" -le 0 ]; then
        printf ''
    elif [ "${#text}" -le "$max" ]; then
        printf '%s' "$text"
    elif [ "$UI_UNICODE" -eq 1 ] && [ "$max" -ge 2 ]; then
        printf '%s%s' "${text:0:max-1}" "$UI_ELLIPSIS"
    elif [ "$max" -ge 3 ]; then
        printf '%s...' "${text:0:max-3}"
    else
        printf '%s' "${text:0:max}"
    fi
}

# Two-column line: leading indent, left text, right text flush to width-1.
_ui_two_col() {
    local width="$1" lc="$2" left="$3" rc="$4" right="$5" stream="${6:-1}"
    local pad=$(( width - 4 - ${#left} - ${#right} - 1 ))
    [ "$pad" -lt 1 ] && pad=1
    printf '  %s%s%s%*s%s%s%s\n' \
        "$lc" "$left" "$UI_RESET" "$pad" "" "$rc" "$right" "$UI_RESET" >&"$stream"
}

# Status line with an optional right-aligned suffix (e.g. a duration).
_ui_status() {
    local sym="$1" color="$2" msg="$3" suffix="${4:-}" stream="${5:-1}"
    local width pad
    width=$(_ui_width)
    if [ -n "$suffix" ]; then
        pad=$(( width - 4 - ${#msg} - ${#suffix} - 1 ))
        [ "$pad" -lt 1 ] && pad=1
        printf '  %s %s%s%s%*s%s%s%s\n' \
            "$sym" "$color" "$msg" "$UI_RESET" "$pad" "" \
            "$UI_DIM" "$suffix" "$UI_RESET" >&"$stream"
    else
        printf '  %s %s%s%s\n' "$sym" "$color" "$msg" "$UI_RESET" >&"$stream"
    fi
}

_ui_progress_bar() {
    local current="$1" total="$2" pct filled=0 i bar=""
    [[ "$total" =~ ^[0-9]+$ ]] && [ "$total" -gt 0 ] || total=1
    [[ "$current" =~ ^[0-9]+$ ]] || current=0
    [ "$current" -gt "$total" ] && current="$total"
    pct=$(( current * 100 / total ))
    filled=$(( pct / 10 ))
    for ((i = 0; i < filled; i++)); do bar+="$UI_BAR_FULL"; done
    for ((i = filled; i < 10; i++)); do bar+="$UI_BAR_EMPTY"; done
    printf '[%s] %d%%' "$bar" "$pct"
}

_ui_box_line() {
    local text="$1" color="$2"
    local pad=$(( UI_BOX_INNER - 2 - ${#text} ))
    [ "$pad" -lt 0 ] && pad=0
    printf '%s%s%s %s%s%s%*s %s%s%s\n' \
        "$UI_DIM" "$UI_BOX_V" "$UI_RESET" \
        "$color" "$text" "$UI_RESET" \
        "$pad" "" \
        "$UI_DIM" "$UI_BOX_V" "$UI_RESET"
}

_ui_now_ms() {
    local t
    t=$(date +%s%N 2>/dev/null || true)
    case "$t" in
        ''|*[!0-9]*) t=$(date +%s 2>/dev/null || printf 0); printf '%s000' "$t" ;;
        *) printf '%s' "${t:0:13}" ;;
    esac
}

_ui_elapsed() {
    local start="$1" end ms
    end=$(_ui_now_ms)
    ms=$(( end - start ))
    [ "$ms" -lt 0 ] && ms=0
    if [ "$ms" -ge 1000 ]; then
        awk "BEGIN { printf \"%.1fs\", $ms / 1000 }"
    else
        printf '%dms' "$ms"
    fi
}

_ui_spinner_enabled() {
    [ "$UI_TTY" -eq 1 ] || return 1
    [ "${TERM:-dumb}" = "dumb" ] && return 1
    [ "${UI_SPINNER:-1}" = "0" ] && return 1
    return 0
}

# Signal handler for an in-flight ui_run_step child.
_ui_on_signal() {
    local sig="$1" code=143
    [ "$sig" = "INT" ] && code=130
    trap - INT TERM
    if [ "$UI_SPINNER_ACTIVE" -eq 1 ]; then
        printf '\r\033[K' >&2
    fi
    if [ -n "$UI_ACTIVE_PID" ]; then
        kill -"$sig" "$UI_ACTIVE_PID" 2>/dev/null || true
        wait "$UI_ACTIVE_PID" 2>/dev/null || true
    fi
    [ -n "$UI_ACTIVE_TMP" ] && rm -rf "$UI_ACTIVE_TMP"
    exit "$code"
}

# ── Public UI functions ─────────────────────────────────────────
ui_header() {
    local name="$1" version="${2:-}" desc="${3:-}"
    local line1="$name" line2="$desc" width max inner
    [ -n "$version" ] && line1="$name  $version"
    width=$(_ui_width)
    max=${#line1}
    [ ${#line2} -gt "$max" ] && max=${#line2}
    inner=$(( max + 2 ))
    [ "$inner" -gt $(( width - 2 )) ] && inner=$(( width - 2 ))
    [ "$inner" -lt 20 ] && inner=20
    UI_BOX_INNER="$inner"
    line1=$(_ui_trunc "$line1" $(( inner - 2 )))
    line2=$(_ui_trunc "$line2" $(( inner - 2 )))

    printf '\n'
    printf '%s%s%s\n' \
        "$UI_DIM$UI_BOX_TL" "$(_ui_repeat "$UI_BOX_H" "$inner")" \
        "$UI_BOX_TR$UI_RESET"
    _ui_box_line "$line1" "$UI_BOLD"
    [ -n "$line2" ] && _ui_box_line "$line2" "$UI_DIM"
    printf '%s%s%s\n' \
        "$UI_DIM$UI_BOX_BL" "$(_ui_repeat "$UI_BOX_H" "$inner")" \
        "$UI_BOX_BR$UI_RESET"
}

ui_section() {
    local current="$1" total="$2" title="${3:-}" left right width
    left="[$current/$total]"
    [ -n "$title" ] && left="$left ${title^^}"
    right=$(_ui_progress_bar "$current" "$total")
    width=$(_ui_width)
    printf '\n'
    _ui_two_col "$width" "$UI_BOLD" "$left" "$UI_DIM" "$right" 1
}

ui_progress() {
    local current="$1" total="$2" label="${3:-}" bar width
    bar=$(_ui_progress_bar "$current" "$total")
    if [ -n "$label" ]; then
        width=$(_ui_width)
        _ui_two_col "$width" "" "$label" "$UI_DIM" "$bar" 1
    else
        printf '  %s%s%s\n' "$UI_DIM" "$bar" "$UI_RESET"
    fi
}

ui_info()    { local msg="$1"; shift; _ui_status "$UI_SYM_INFO" "$UI_CYAN" "$msg" "${1:-}" 1; }
ui_success() { local msg="$1"; shift; _ui_status "$UI_SYM_OK" "$UI_GREEN" "$msg" "${1:-}" 1; }
ui_warning() { local msg="$1"; shift; _ui_status "$UI_SYM_WARN" "$UI_YELLOW" "$msg" "${1:-}" 2; }
ui_error()   { local msg="$1"; shift; _ui_status "$UI_SYM_ERR" "$UI_RED" "$msg" "${1:-}" 2; }
ui_die()     { ui_error "$*"; exit 1; }

# ui_run_step [--optional] [--reason TEXT] <message> <command> [args...]
# Runs a command with a spinner (TTY only), prints a timed status line and
# returns the command's exit code. Output is captured and only shown on
# failure, or streamed live when UI_DEBUG=1. DRY_RUN prints a plan line only.
ui_run_step() {
    local optional=0 reason="" msg rc=0 tmpdir out err start elapsed i old_int old_term
    while [ $# -gt 0 ]; do
        case "$1" in
            --optional) optional=1; shift ;;
            --reason)
                [ -n "${2:-}" ] || ui_die "ui_run_step: --reason needs a value"
                reason="$2"; shift 2 ;;
            --) shift; break ;;
            -*) ui_die "ui_run_step: unknown option: $1" ;;
            *) break ;;
        esac
    done
    [ $# -ge 1 ] || ui_die "ui_run_step: missing message"
    msg="$1"; shift
    [ $# -ge 1 ] || ui_die "ui_run_step: missing command for '$msg'"

    start=$(_ui_now_ms)
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        ui_info "(dry-run) $msg"
        return 0
    fi

    if [ "${UI_DEBUG:-0}" -eq 1 ]; then
        ui_info "$msg"
        "$@"
        rc=$?
        elapsed=$(_ui_elapsed "$start")
        if [ "$rc" -eq 0 ]; then
            ui_success "$msg" "$elapsed"
        elif [ "$optional" -eq 1 ]; then
            ui_warning "$msg — skipped: ${reason:-command failed (exit $rc)}" "$elapsed"
        else
            ui_error "$msg" "$elapsed"
        fi
        return "$rc"
    fi

    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/lip-ui.XXXXXX") ||
        { ui_error "$msg — cannot create temp dir"; return 1; }
    out="$tmpdir/out"; err="$tmpdir/err"
    : >"$out"; : >"$err"
    UI_ACTIVE_PID=""; UI_ACTIVE_TMP="$tmpdir"

    old_int=$(trap -p INT || true)
    old_term=$(trap -p TERM || true)
    trap '_ui_on_signal INT' INT
    trap '_ui_on_signal TERM' TERM

    "$@" >"$out" 2>"$err" &
    UI_ACTIVE_PID=$!

    if _ui_spinner_enabled; then
        UI_SPINNER_ACTIVE=1
        i=0
        while kill -0 "$UI_ACTIVE_PID" 2>/dev/null; do
            printf '\r  %s%s%s %s' "$UI_CYAN" "${UI_SPIN[$i]}" "$UI_RESET" "$msg" >&2
            i=$(( (i + 1) % ${#UI_SPIN[@]} ))
            sleep 0.1
        done
        printf '\r\033[K' >&2
        UI_SPINNER_ACTIVE=0
    fi

    rc=0
    wait "$UI_ACTIVE_PID" || rc=$?
    UI_ACTIVE_PID=""
    trap - INT TERM
    [ -n "$old_int" ] && eval "$old_int"
    [ -n "$old_term" ] && eval "$old_term"

    elapsed=$(_ui_elapsed "$start")
    if [ "$rc" -eq 0 ]; then
        ui_success "$msg" "$elapsed"
        rm -rf "$tmpdir"
        UI_ACTIVE_TMP=""
        return 0
    fi

    # Always surface diagnostics: stderr first, then a tail of stdout.
    if [ -s "$err" ]; then
        sed 's/^/    /' "$err" >&2
    fi
    if [ -s "$out" ]; then
        tail -n 20 "$out" | sed 's/^/    /'
    fi

    if [ "$optional" -eq 1 ]; then
        if [ -z "$reason" ] && [ -s "$err" ]; then
            IFS= read -r reason <"$err" || true
        fi
        reason="${reason:-command failed (exit $rc)}"
        ui_warning "$msg — skipped: ${reason:0:80}" "$elapsed"
    else
        ui_error "$msg" "$elapsed"
    fi
    rm -rf "$tmpdir"
    UI_ACTIVE_TMP=""
    return "$rc"
}

# ── Source guard ────────────────────────────────────────────────
return 0 2>/dev/null || true
