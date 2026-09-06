#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fails=0
warns=0

fail() { fails=$((fails + 1)); printf 'FAIL  %s\n' "$1"; }
warn_() { warns=$((warns + 1)); printf 'WARN  %s\n' "$1"; }

shell_files() {
    printf '%s\n' bin/pos bin/pos-* lib/*.sh features/*.sh entertainment/*.sh \
        apps/*/*.sh templates/*.sh scripts/*.sh install.sh preinstall.sh postinstall.sh \
        2>/dev/null
}

executable_files() {
    printf '%s\n' bin/pos-* entertainment/*.sh 2>/dev/null
}

has_regex() {
    local file="$1" re="$2"
    grep -qE "$re" "$file" && return 0
    return 1
}

# First deps guard: a `command -v` line that hard-fails the tool when the binary
# is absent — i.e. `command -v X … || err`, `if ! command -v X …`, or a
# `command -v X … \` multi-line continuation. Runtime capability probes like
# `if command -v X; then` (graceful degradation, e.g. system-health) are NOT
# guards and must not trigger the guard-before-help rule.
first_guard_line() {
    local file="$1" ln=0
    while IFS= read -r line || [ -n "$line" ]; do
        ln=$((ln + 1))
        [[ "$line" == *"command -v"* ]] || continue
        [[ "$line" == *"||"* || "$line" == *"if !"* || "$line" == *\\ ]] && { printf '%s' "$ln"; return; }
    done < "$file"
    printf '%s' ""
}

# Single-line stdin-reader test. Pure bash; no subprocess. Heredoc/while-loop
# exclusions are handled by the caller's per-file loop state.
_reads_stdin() {
    local ln="$1"
    case "$ln" in
        *'read -'*|*'read '*|*'select '*|*'confirm '*|*'confirm('*) ;;
        *) return 1 ;;
    esac
    [[ "$ln" =~ ^[[:space:]]*# ]] && return 1
    [[ "$ln" == *"/dev/tty"* ]] && return 1
    [[ "$ln" =~ (while|until)[[:space:]].*read ]] && return 1
    [[ "$ln" =~ [[:space:]]\< ]] && return 1
    return 0
}

INTERACTIVE_CMDS=""
if [ -f bin/pos ]; then
    INTERACTIVE_CMDS="$(sed -n 's/^INTERACTIVE_CMDS="\(.*\)"$/\1/p' bin/pos | head -1)"
fi

for f in $(shell_files); do
    [ -f "$f" ] || continue
    case "$f" in
        lib/*.sh) continue ;; # libraries are sourced, never executed
    esac
    read -r first < "$f" || first=""
    if [ "$first" != '#!/usr/bin/env bash' ]; then
        fail "$f: missing '#!/usr/bin/env bash' shebang"
    fi
    if ! grep -qE '^set -euo pipefail' "$f"; then
        fail "$f: missing 'set -euo pipefail'"
    fi
done

for f in $(executable_files); do
    [ -f "$f" ] || continue
    if [ ! -x "$f" ]; then
        fail "$f: not executable (needs chmod +x, committed as 100755)"
    fi
done

# Preload DOC/POS.md once — the per-tool presence check below must not re-read
# the file (and re-spawn grep) for every tool.
posmd=""
[ -f DOC/POS.md ] && posmd="$(cat DOC/POS.md)"

for f in bin/pos-*; do
    [ -f "$f" ] || continue

    # ── single-pass metadata scan (shebang/pos-header/help/local/stdin) ──
    headline=""
    posline=0
    local_line=""
    help_line=""
    uses_stdin=0
    lineno=0 heredoc="" depth=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        # # POS: header (whole-file scan, matches original `sed -n '/^# POS: /…'`)
        if [ "$posline" -eq 0 ] && [[ "$line" == "# POS: "* ]]; then
            posline=$lineno
            headline="${line#*POS: }"
        fi
        # First non-comment -h|--help line (matches original first_line lookup)
        if [ -z "$help_line" ] && ! [[ "$line" =~ ^[[:space:]]*# ]] && [[ "$line" == *-h* || "$line" == *--help* ]] && [[ "$line" =~ -h\|--help ]]; then
            help_line=$lineno
        fi
        [ -n "$heredoc" ] && { [ "$line" = "$heredoc" ] && heredoc=""; continue; }
        # Heredoc delimiter: greedy `.*` selects the LAST << / <<- on the line,
        # matching the original sed `s/.*<<-?[[:space:]]*([A-Za-z0-9_]+).*/\1/p | tail -1`.
        if [[ "$line" == *"<<"* ]] && [[ "$line" =~ .*\<\<-?[[:space:]]*([A-Za-z0-9_]+) ]]; then
            heredoc="${BASH_REMATCH[1]}"
            continue
        fi
        # Top-level `local` (WARN) — first occurrence at brace depth 0. Depth
        # tracking is only needed until the first one is found, so the two
        # full-line brace-count expansions are gated off after that.
        if [ -z "$local_line" ]; then
            if [[ "$line" == *local* ]] && [[ "$line" =~ ^[[:space:]]*local[[:space:]] ]]; then
                if [ "$depth" -eq 0 ]; then
                    [ -n "$local_line" ] || local_line="$lineno"
                fi
            fi
            opens="${line//[^{]/}"
            closes="${line//[^\}]/}"
            depth=$((depth + ${#opens} - ${#closes}))
            [ "$depth" -lt 0 ] && depth=0
        fi
        # stdin-reader detection (non-heredoc lines only; cheap string gate
        # keeps the expensive regex work inside `_reads_stdin` for read-like lines)
        if [ "$uses_stdin" -eq 0 ]; then
            case "$line" in
                *'read -'*|*'read '*|*'select '*|*'confirm '*|*'confirm('*) _reads_stdin "$line" && uses_stdin=1 ;;
            esac
        fi
    done < "$f"

    if [ -z "$headline" ]; then
        fail "$f: missing '# POS:' header"
        continue
    fi
    if [[ "$headline" != *' — '* ]]; then
        fail "$f: '# POS:' header missing em-dash ' — ' (format: '# POS: <cat> <cmd> — <desc>')"
    fi
    if [ "${posline:-99}" -gt 6 ]; then
        warn_ "$f: '# POS:' header on line $posline (convention: right after shebang/strict-mode)"
    fi

    if ! has_regex "$f" '\-h\|\-\-help'; then
        fail "$f: missing -h|--help handling"
    fi

    guard="$(first_guard_line "$f")"
    if [ -n "$guard" ] && [ -n "$help_line" ] && [ "$help_line" -lt "$guard" ]; then
        fail "$f: -h|--help (line $help_line) dispatched before deps guards (line $guard) — help must error on missing deps"
    fi

    if [ -n "$local_line" ]; then
        warn_ "$f: '$local_line': 'local' at top-level brace depth (invalid in bash outside a function)"
    fi

    if [ "$uses_stdin" -eq 1 ]; then
        name="${f#bin/pos-}"
        if ! [[ " $INTERACTIVE_CMDS " == *" $name "* ]]; then
            fail "$f: reads stdin but NOT in INTERACTIVE_CMDS in bin/pos (log tee will swallow/hang prompts)"
        fi
    fi

    base="${f#bin/}"
    if ! [[ "$posmd" == *"$base"* ]]; then
        warn_ "$f: file not referenced in DOC/POS.md"
    fi
done

if [ -n "$INTERACTIVE_CMDS" ]; then
    for entry in $INTERACTIVE_CMDS; do
        if [ ! -x "bin/pos-$entry" ]; then
            fail "bin/pos: INTERACTIVE_CMDS entry '$entry' has no matching bin/pos-$entry tool"
        fi
    done
fi

for f in entertainment/*.sh; do
    [ -f "$f" ] || continue
    if has_regex "$f" 'common\.sh'; then
        fail "$f: entertainment plugin must NOT source lib/common.sh (stdout is the Telegram message)"
    fi
    if ! has_regex "$f" '^# POS_PLUGIN: '; then
        fail "$f: missing '# POS_PLUGIN:' marker"
    fi
done

for f in apps/*/*.sh; do
    [ -f "$f" ] || continue
    app="${f##*/}"
    app="${app%.sh}"
    if ! has_regex "$f" "uninstall_${app//-/_}\(\).*\{"; then
        if ! has_regex "$f" "uninstall_${app}\(\).*\{"; then
            fail "$f: missing 'uninstall_${app}()' function"
        fi
    fi
    if ! has_regex "$f" 'uninstall\)'; then
        fail "$f: missing 'uninstall' dispatch case"
    fi
done

for f in systemd/*.service; do
    [ -f "$f" ] || continue
    if ! has_regex "$f" '^TimeoutStopSec='; then
        warn_ "$f: missing 'TimeoutStopSec=5s' (convention: a stuck process must not stall reboot 90s)"
    fi
    if ! has_regex "$f" '^WantedBy='; then
        warn_ "$f: missing '[Install] WantedBy='"
    fi
done

for f in bin/wr-* bin/mp3 bin/mp4 bin/vbox bin/ssh-load-all; do
    [ -f "$f" ] || continue
    if ! has_regex "$f" '\bpos\b'; then
        fail "$f: legacy wrapper does not forward to 'pos'"
    fi
    if [ "$(wc -l < "$f")" -gt 12 ]; then
        warn_ "$f: legacy wrapper has $(wc -l < "$f") lines (convention: thin forwarder only)"
    fi
    if has_regex "$f" '^[[:space:]]*case '; then
        warn_ "$f: legacy wrapper contains a case statement (should be a thin forwarder)"
    fi
done

# Secret-like literal assignment scan (WARN). Original used a grep pre-filter
# + a per-line heredoc grep; here both are bash `[[ =~ ]]` in one read per file.
while IFS= read -r f; do
    [ -f "$f" ] || continue
    num=0
    while IFS= read -r line; do
        num=$((num + 1))
        # cheap substring gate before the expensive assignment regex
        [[ "$line" == *TOKEN* || "$line" == *PASSWORD* || "$line" == *PASSWD* || "$line" == *SECRET* || "$line" == *API* || "$line" == *ACCESS* || "$line" == *KEY* || "$line" == *AUTH* ]] || continue
        [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*(TOKEN|PASSWORD|PASSWD|SECRET|API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?KEY)= ]] || continue
        [[ "$line" =~ (TOKEN|PASSWORD|PASSWD|SECRET|API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?KEY)= ]] || continue
        val="${line#*=}"
        case "$val" in
            ""|*'$'*) ;;
            *) warn_ "$f:$num: secret-like literal assignment (manual review for hardcoded credentials)" ;;
        esac
    done < "$f"
done < <(printf '%s\n' bin/pos bin/pos-* lib/*.sh features/*.sh entertainment/*.sh install.sh preinstall.sh postinstall.sh)

# Early-occurrence scan for one of the three system paths in a line.
# strindex sets the global _SI to the index of $2 in $1 (or 2147483647 if absent).
_SI=0
strindex() { local pre="${1%%"$2"*}"; if [ "$pre" = "$1" ]; then _SI=2147483647; else _SI=${#pre}; fi; }

# Faithful re-implementation of the original outer filter
#   grep -E '(\btee\b|>>?)[^#]*?(/etc/|\$HOME|/usr/local)'
# (operator, then any non-'#' chars, then a system path). Bash `=~` does not
# honour the lazy `[^#]*?` the same way, so we walk path occurrences manually,
# checking that the segment before each path (after the last '#') holds an
# operator (`>`/`>>` or a word-bounded `tee`).
_syspath_outer() {
    local ln="$1" best=2147483647 bestcand="" idx c pre seg h
    for c in '/etc/' '$HOME' '/usr/local'; do
        strindex "$ln" "$c"
        [ "$_SI" -lt "$best" ] && { best="$_SI"; bestcand="$c"; }
    done
    [ "$best" -ge 2147483647 ] && return 1
    pre="${ln:0:best}"
    h="${pre%#*}"
    if [ "$h" = "$pre" ]; then
        seg="$pre"           # no '#' before the path
    else
        seg="${pre:${#h}+1}" # after the last '#' before the path
    fi
    if [[ "$seg" == *">"* ]] || [[ "$seg" =~ \btee\b ]]; then
        return 0
    fi
    _syspath_outer "${ln:best+${#bestcand}}"
}

# System-path write scan (WARN). Route lines through the same outer filter then
# the same per-line heuristic the original applied (check + exclusions).
while IFS= read -r f; do
    [ -f "$f" ] || continue
    num=0
    while IFS= read -r line; do
        num=$((num + 1))
        # cheap string gate: outer filter needs both an operator and a path
        [[ "$line" == *">"* || "$line" == *tee* ]] || continue
        [[ "$line" == */etc/* || "$line" == *'$HOME'* || "$line" == */usr/local* ]] || continue
        _syspath_outer "$line" || continue
        if [[ "$line" =~ (>|>>|tee[[:space:]]) ]] && [[ "$line" =~ (/etc/|\$HOME|/usr/local) ]]; then
            case "$line" in
                *'command -v'*|*'|| echo'*) ;;
                *) warn_ "$f:$num: writes to a system path (verify a VAR=\"\${VAR:-path}\" test seam exists)" ;;
            esac
        fi
    done < "$f"
done < <(printf '%s\n' bin/pos-* lib/*.sh features/*.sh entertainment/*.sh)

printf '\n%d FAIL, %d WARN (convention lint)\n' "$fails" "$warns"
[ "$fails" -eq 0 ] || exit 1
