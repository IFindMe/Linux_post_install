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

first_line() {
    local file="$1" re="$2"
    grep -nE "$re" "$file" 2>/dev/null | while IFS=: read -r ln rest; do
        [ -z "$ln" ] && continue
        [[ "$rest" =~ ^[[:space:]]*# ]] && continue
        printf '%s' "$ln"
        break
    done
}

last_line() {
    local file="$1" re="$2"
    grep -nE "$re" "$file" 2>/dev/null | tail -1 | cut -d: -f1 || true
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

uses_stdin() {
    local file="$1" line heredoc=""
    while IFS= read -r line; do
        if [ -n "$heredoc" ]; then
            [ "$line" = "$heredoc" ] && heredoc=""
            continue
        fi
        local delim
        delim="$(printf '%s\n' "$line" | sed -nE 's/.*<<-?[[:space:]]*([A-Za-z0-9_]+).*/\1/p' | tail -1)"
        [ -n "$delim" ] && { heredoc="$delim"; continue; }
        case "$line" in
            *'read -'*|*'read '*|*'select '*|*'confirm '*|*'confirm('*) ;;
            *) continue ;;
        esac
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" == *"/dev/tty"* ]] && continue
        [[ "$line" =~ (while|until)[[:space:]].*read ]] && continue
        [[ "$line" =~ [[:space:]]\< ]] && continue
        return 0
    done < "$file"
    return 1
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
    if ! head -1 "$f" | grep -q '^#!/usr/bin/env bash'; then
        fail "$f: missing '#!/usr/bin/env bash' shebang"
    fi
    if ! has_regex "$f" '^set -euo pipefail'; then
        fail "$f: missing 'set -euo pipefail'"
    fi
done

for f in $(executable_files); do
    [ -f "$f" ] || continue
    if [ ! -x "$f" ]; then
        fail "$f: not executable (needs chmod +x, committed as 100755)"
    fi
done

for f in bin/pos-*; do
    [ -f "$f" ] || continue

    headline="$(sed -n '/^# POS: /{s/^# POS: //;p;q}' "$f" 2>/dev/null)"
    if [ -z "$headline" ]; then
        fail "$f: missing '# POS:' header"
        continue
    fi
    if ! grep -q ' — ' <<<"$headline"; then
        fail "$f: '# POS:' header missing em-dash ' — ' (format: '# POS: <cat> <cmd> — <desc>')"
    fi
    posline="$(grep -nE '^# POS: ' "$f" | head -1 | cut -d: -f1 || true)"
    if [ "${posline:-99}" -gt 6 ]; then
        warn_ "$f: '# POS:' header on line $posline (convention: right after shebang/strict-mode)"
    fi

    if ! has_regex "$f" '\-h\|\-\-help'; then
        fail "$f: missing -h|--help handling"
    fi

    guard="$(first_guard_line "$f")"
    help_line="$(first_line "$f" '\-h\|\-\-help')"
    if [ -n "$guard" ] && [ -n "$help_line" ] && [ "$help_line" -lt "$guard" ]; then
        fail "$f: -h|--help (line $help_line) dispatched before deps guards (line $guard) — help must error on missing deps"
    fi

    local_line=""
    lineno=0
    depth=0
    heredoc=""
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        if [ -n "$heredoc" ]; then
            [ "$line" = "$heredoc" ] && heredoc=""
            continue
        fi
        delim="$(printf '%s\n' "$line" | sed -nE 's/.*<<-?[[:space:]]*([A-Za-z0-9_]+).*/\1/p' | tail -1)"
        if [ -n "$delim" ]; then
            heredoc="$delim"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*local[[:space:]] ]]; then
            if [ "$depth" -eq 0 ]; then
                [ -n "$local_line" ] || local_line="$lineno"
            fi
        fi
        opens="${line//[^{]/}"
        closes="${line//[^\}]/}"
        depth=$((depth + ${#opens} - ${#closes}))
        [ "$depth" -lt 0 ] && depth=0
    done < "$f"
    if [ -n "$local_line" ]; then
        warn_ "$f: '$local_line': 'local' at top-level brace depth (invalid in bash outside a function)"
    fi

    if uses_stdin "$f"; then
        name="${f#bin/pos-}"
        if ! [[ " $INTERACTIVE_CMDS " == *" $name "* ]]; then
            fail "$f: reads stdin but NOT in INTERACTIVE_CMDS in bin/pos (log tee will swallow/hang prompts)"
        fi
    fi

    if ! grep -q "$(basename "$f")" DOC/POS.md 2>/dev/null; then
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

while IFS= read -r f; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        [[ "$line" =~ ^[0-9]+: ]] || continue
        num="${line%%:*}"
        body="${line#*:}"
        if grep -qE '(TOKEN|PASSWORD|PASSWD|SECRET|API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?KEY)=' <<<"$body"; then
            val="${body#*=}"
            case "$val" in
                ""|*'$'*) ;;
                *) warn_ "$f:$num: secret-like literal assignment (manual review for hardcoded credentials)" ;;
            esac
        fi
    done < <(grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*(TOKEN|PASSWORD|PASSWD|SECRET|API[_-]?KEY|ACCESS[_-]?TOKEN|AUTH[_-]?KEY)=' "$f" 2>/dev/null || true)
done < <(printf '%s\n' bin/pos bin/pos-* lib/*.sh features/*.sh entertainment/*.sh install.sh preinstall.sh postinstall.sh)

while IFS= read -r f; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
        [[ "$line" =~ ^[0-9]+: ]] || continue
        num="${line%%:*}"
        body="${line#*:}"
        if grep -qE '(>|>>|tee )' <<<"$body" && grep -qE '(/etc/|\$HOME|/usr/local)' <<<"$body"; then
            case "$body" in
                *'command -v'*|*'|| echo'*) ;;
                *) warn_ "$f:$num: writes to a system path (verify a VAR=\"\${VAR:-path}\" test seam exists)" ;;
            esac
        fi
    done < <(grep -nE '(\btee\b|>>?)[^#]*?(/etc/|\$HOME|/usr/local)' "$f" 2>/dev/null || true)
done < <(printf '%s\n' bin/pos-* lib/*.sh features/*.sh entertainment/*.sh)

printf '\n%d FAIL, %d WARN (convention lint)\n' "$fails" "$warns"
[ "$fails" -eq 0 ] || exit 1
