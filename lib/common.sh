# ── Colors (auto-off when not a TTY) ───────────────────────────
if [ -t 1 ]; then
    CYAN=$(tput setaf 6)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    RED=$(tput setaf 1)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    CYAN=""; GREEN=""; YELLOW=""; RED=""; BLUE=""; BOLD=""; RESET=""
fi

# ── Core helpers ───────────────────────────────────────────────
log()   { echo "${GREEN}[+]${RESET} $*"; }
warn()  { echo "${YELLOW}[!]${RESET} $*"; }
err()   { echo "${RED}ERROR:${RESET} $*" >&2; exit 1; }
ok()   { echo "${GREEN}  OK${RESET} $*"; }

# ── Section header ─────────────────────────────────────────────
section() {
    local title="$*"
    echo
    echo "${CYAN}════════════════════════════════════════════${RESET}"
    echo "${CYAN}  ${title}${RESET}"
    echo "${CYAN}════════════════════════════════════════════${RESET}"
}

# ── Step header (numbered) ─────────────────────────────────────
step() {
    local current="$1" total="$2" msg="$3"
    echo
    echo "${BOLD}  [${current}/${total}] ${msg}${RESET}"
    echo "${BLUE}  ─────────────────────────────────────────${RESET}"
}

# ── Dry-run aware executor ─────────────────────────────────────
run() {
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) $*"
    else
        "$@"
    fi
}

# ── Internal: nanoseconds → formatted time string ─────────────
_nano_now() { date +%s%N; }
_elapsed() {
    local start="$1" end
    end=$(_nano_now)
    local ms=$(( (end - start) / 1000000 ))
    if [ "$ms" -ge 1000 ]; then
        awk "BEGIN { printf \"%.1fs\", $ms / 1000 }"
    elif [ "$ms" -ge 1 ]; then
        echo "${ms}ms"
    else
        echo "0ms"
    fi
}

# ── Timer ──────────────────────────────────────────────────────
TIMER_START=0
timer_start() { TIMER_START=$(_nano_now); }
timer_stop()  { _elapsed "$TIMER_START"; }

# ── Timed command runner ───────────────────────────────────────
# Shows a spinner while the command runs in background,
# then prints result + elapsed time.
spawn() {
    local msg="$1"
    shift
    local start
    start=$(_nano_now)

    # Run in background, capture output
    local out err rc
    out=$(mktemp)
    err=$(mktemp)
    "$@" >"$out" 2>"$err" &
    local pid=$!

    # Spinner
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}  %s${RESET} %s" "${spin[$i]}" "$msg"
        i=$(( (i + 1) % ${#spin[@]} ))
        sleep 0.1
    done
    rc=0; wait "$pid" || rc=$?
    local elapsed
    elapsed=$(_elapsed "$start")

    if [ "$rc" -eq 0 ]; then
        printf "\r${GREEN}  OK${RESET} %s (${elapsed})\n" "$msg"
    else
        printf "\r${RED}  FAIL${RESET} %s (${elapsed})\n" "$msg"
        # Show captured stderr on failure
        if [ -s "$err" ]; then
            sed 's/^/    /' "$err"
        fi
        rm -f "$out" "$err"
        exit "$rc"
    fi
    rm -f "$out" "$err"
}

# ── Confirmation prompt ────────────────────────────────────────
confirm() {
    local prompt="$1" default="${2:-y}" yn
    if [ "$default" = "y" ]; then
        read -rp "${prompt} [Y/n]: " yn
        [[ -z "$yn" || "$yn" =~ ^[Yy] ]]
    else
        read -rp "${prompt} [y/N]: " yn
        [[ "$yn" =~ ^[Yy] ]]
    fi
}

# ── Source guard ───────────────────────────────────────────────
return 0 2>/dev/null || true
