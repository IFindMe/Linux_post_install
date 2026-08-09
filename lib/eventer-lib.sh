# lib/eventer-lib.sh — shared library for `pos system event-trigger`.
# Sourced by bin/pos-system-event-trigger AFTER lib/common.sh.
#
# eventer reads a list of independent RULES from event.env, one per line:
#
#     "High CPU temp" if sensors -u | grep -m1 temp1_input | awk '{print $2}' > 60c
#     disk root > 80%
#     loadavg >= 4
#
# Grammar:  ["<message>" if ] <inline-check-command> <op> <threshold>
#   - optional message before the last ' if ' (quote-stripped) = alert text
#   - the operator is the RIGHTMOST '>= <= == != > <' whose RHS parses as a
#     number (a unit suffix like 60c / 80% is fine) — everything before it is
#     the check command, the number is the threshold
#   - the check command is run and its FIRST numeric token is compared (float).
#   State-based alerting: notify on false→true, one recovery on true→false.
#
# NOTE: rules are arbitrary shell commands (the user's own config, chmod 600),
# the same trust model as the Telegram listener's command map.

CONFIG_FILE="${EVENT_CONFIG:-$HOME/.config/linux_post_install/event.env}"
EVENT_STATE_DIR="${EVENT_STATE_DIR:-$HOME/.local/share/linux_post_install/eventer/state}"
USER_SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
EVENT_UNIT="pos-event-trigger"
EVENT_RUNNER="$(command -v pos-system-event-trigger 2>/dev/null || echo /usr/local/bin/pos-system-event-trigger)"

# common.sh helpers (guarded so the lib is safe if common.sh wasn't loaded)
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F ok   >/dev/null || ok()   { echo "  OK $*"; }
declare -F log  >/dev/null || log()  { echo "[+] $*"; }

# ── Rule file helpers ────────────────────────────────────────────
# Fills the global array RULES with every line of the file (raw).
eventer_read_rules() {
    RULES=()
    [ -f "$CONFIG_FILE" ] || return 0
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        RULES+=("$line")
    done < "$CONFIG_FILE"
}

eventer_write_rules() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    local tmp
    tmp="$(mktemp)"
    printf '%s\n' "${RULES[@]}" >"$tmp"
    mv "$tmp" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

eventer_count_rules() {
    local i n=0 line
    for line in "${RULES[@]}"; do
        line="${line#"${line%%[![:space:]]*}"}"   # trim leading whitespace
        [ -n "$line" ] && [[ "$line" != \#* ]] && n=$((n + 1))
    done
    printf '%s' "$n"
}

# ── Rule parsing ─────────────────────────────────────────────────
# eventer_parse_rule "<line>" — on success sets RULE_MSG, RULE_CMD,
# RULE_OP, RULE_THRESH, RULE_NUM and returns 0; otherwise returns 1.
# Also supports bare "CMD OP THRESH" (no message) and "MSG if CMD OP THRESH".
eventer_parse_rule() {
    local line="$1" cond="" msg="" s m parts="" i
    s="$line"
    while [[ "$s" == *" if "* ]]; do
        m="${s%% if *}"
        s="${s#*" if "}"
        if [[ "$s" == *" if "* ]]; then
            parts+="${m} if "
        else
            parts+="${m}"
        fi
    done
    msg="$parts"
    cond="$s"
    [ -n "$cond" ] || return 1

    local -a tokens=()
    read -r -a tokens <<< "$cond"
    local n=${#tokens[@]}
    [ "$n" -ge 2 ] || return 1
    for ((i=n-2; i>=0; i--)); do
        case "${tokens[i]}" in
            ">="|"<="|"=="|"!="|">"|"<")
                if eventer_numeric "${tokens[i+1]}" >/dev/null 2>&1; then
                    RULE_OP="${tokens[i]}"
                    RULE_THRESH="${tokens[i+1]}"
                    RULE_NUM="$(eventer_numeric "${tokens[i+1]}")"
                    if [ "$i" -eq 0 ]; then
                        RULE_CMD="${tokens[0]}"
                    else
                        RULE_CMD="$(printf '%s ' "${tokens[@]:0:i}")"
                        RULE_CMD="${RULE_CMD% }"
                    fi
                    RULE_MSG="$(eventer_strip_quotes "$msg")"
                    return 0
                fi ;;
        esac
    done
    return 1
}

# First numeric prefix of a string (allows a unit suffix: 60c, 80%, 10g).
eventer_numeric() {
    if [[ "$1" =~ ^[+-]?([0-9]+([.][0-9]+)?|[.][0-9]+) ]]; then
        printf '%s' "${BASH_REMATCH[0]}"
        return 0
    fi
    return 1
}

eventer_strip_quotes() {
    local v="$1"
    v="${v#\"}"; v="${v%\"}"
    v="${v#\'}"; v="${v%\'}"
    printf '%s' "$v"
}

# Float-safe numeric comparison. Returns 0 if $1 $2 $3 is TRUE.
eventer_compare() {
    awk -v a="$1" -v op="$2" -v b="$3" 'BEGIN{
        if (op==">")  exit (a>b)  ? 0 : 1
        if (op=="<")  exit (a<b)  ? 0 : 1
        if (op==">=") exit (a>=b) ? 0 : 1
        if (op=="<=") exit (a<=b) ? 0 : 1
        if (op=="==") exit (a==b) ? 0 : 1
        if (op=="!=") exit (a!=b) ? 0 : 1
        exit 1
    }'
}

# ── Running a check ──────────────────────────────────────────────
# eventer_eval_check — runs RULE_CMD, sets VALUE_DISPLAY (first numeric
# token as printed) and VALUE_NUM (its numeric prefix). Returns 0 on success.
eventer_eval_check() {
    local out tok line
    out="$(bash -c "$RULE_CMD" 2>/dev/null || true)"
    [ -n "$out" ] || return 1
    line="$(printf '%s' "$out" | sed -n '1p')"
    read -r -a tokens <<< "$line"
    for tok in "${tokens[@]}"; do
        if eventer_numeric "$tok" >/dev/null 2>&1; then
            VALUE_NUM="$(eventer_numeric "$tok")"
            VALUE_DISPLAY="$tok"
            return 0
        fi
    done
    return 1
}

# ── Alert messages ───────────────────────────────────────────────
eventer_alert_msg() {
    if [ -n "$RULE_MSG" ]; then
        printf '%s (now %s)' "$RULE_MSG" "$VALUE_DISPLAY"
    else
        printf '%s now %s is %s %s' "${RULE_CMD%% *}" "$VALUE_DISPLAY" "$RULE_OP" "$RULE_THRESH"
    fi
}

eventer_recover_msg() {
    if [ -n "$RULE_MSG" ]; then
        printf '%s recovered (now %s)' "$RULE_MSG" "$VALUE_DISPLAY"
    else
        printf '%s OK (now %s)' "${RULE_CMD%% *}" "$VALUE_DISPLAY"
    fi
}

# ── State (per rule, keyed by a short hash of the rule line) ─────
eventer_hash() { printf '%s' "$1" | sha256sum | cut -c1-16; }

eventer_state_is_firing() {   # $1 = hash
    [ -f "$EVENT_STATE_DIR/$1" ] && grep -q '^1' "$EVENT_STATE_DIR/$1"
}

eventer_state_set() {         # $1 = hash, $2 = 0|1
    mkdir -p "$EVENT_STATE_DIR"
    printf '%s\n' "$2" >"$EVENT_STATE_DIR/$1"
}

# ── Interval → systemd OnCalendar (same list as entertainment) ──
eventer_interval_to_oncalendar() {
    local i="$1"
    case "$i" in
        OnCalendar=*) printf '%s' "${i#OnCalendar=}"; return 0 ;;
    esac
    if [[ "$i" =~ ^([0-9]+)m$ ]]; then
        local n="${BASH_REMATCH[1]}"
        [ "$n" -ge 1 ] && [ "$n" -le 59 ] || return 1
        printf '*:00/%s:00' "$n"; return 0
    fi
    if [[ "$i" =~ ^([0-9]+)h$ ]]; then
        local n="${BASH_REMATCH[1]}"
        [ "$n" -ge 1 ] && [ "$n" -le 23 ] || return 1
        printf '*-*-* 00/%s:00:00' "$n"; return 0
    fi
    case "$i" in
        hourly) printf '*-*-* *:00:00' ;;
        daily)  printf '*-*-* 08:00:00' ;;
        weekly) printf 'Mon *-*-* 08:00:00' ;;
        *) return 1 ;;
    esac
    return 0
}

eventer_interval_label() {
    case "$1" in
        daily)      echo "daily (08:00)" ;;
        weekly)     echo "weekly (Mon 08:00)" ;;
        hourly)     echo "hourly" ;;
        OnCalendar=*) echo "${1#OnCalendar=}" ;;
        *m|*h)      echo "every $1" ;;
        *)          echo "$1" ;;
    esac
}

# ── systemd user timer ───────────────────────────────────────────
eventer_ensure_linger() {
    local user
    user="$(id -un)"
    [ "$user" = "root" ] && { warn "running as root — enable linger for your real user: sudo loginctl enable-linger <user>"; return 0; }
    command -v loginctl >/dev/null 2>&1 || return 0
    if loginctl show-user "$user" 2>/dev/null | grep -q '^Linger=yes'; then
        return 0
    fi
    if sudo -n loginctl enable-linger "$user" 2>/dev/null; then
        ok "enabled linger for $user (timers fire without login)"
    else
        warn "run once so timers fire without login: sudo loginctl enable-linger $user"
    fi
}

eventer_write_units() {
    local oncal="$1"
    mkdir -p "$USER_SYSTEMD_DIR"
    cat >"$USER_SYSTEMD_DIR/$EVENT_UNIT.service" <<EOF
[Unit]
Description=pos system event-trigger — evaluate event.env rules
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$EVENT_RUNNER run

[Install]
WantedBy=timers.target
EOF
    cat >"$USER_SYSTEMD_DIR/$EVENT_UNIT.timer" <<EOF
[Unit]
Description=Schedule: pos system event-trigger

[Timer]
OnCalendar=$oncal
Persistent=true

[Install]
WantedBy=timers.target
EOF
    chmod 644 "$USER_SYSTEMD_DIR/$EVENT_UNIT.service" "$USER_SYSTEMD_DIR/$EVENT_UNIT.timer"
}

eventer_enable() {
    local interval="${1:-5m}" oncal
    oncal="$(eventer_interval_to_oncalendar "$interval")" || {
        warn "invalid interval '$interval' (use 5m 10m 15m 30m 45m hourly 2h 6h 12h daily weekly, or OnCalendar=…)"
        return 1
    }
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) write $USER_SYSTEMD_DIR/$EVENT_UNIT.timer (OnCalendar=$oncal)"
        return 0
    fi
    eventer_write_units "$oncal"
    systemctl --user daemon-reload >/dev/null 2>&1 || warn "daemon-reload failed (user systemd running?)"
    if systemctl --user enable --now "$EVENT_UNIT.timer" >/dev/null 2>&1; then
        ok "$EVENT_UNIT.timer enabled ($(eventer_interval_label "$interval"))"
        eventer_ensure_linger
    else
        warn "could not enable $EVENT_UNIT.timer (is the user systemd manager running?)"
    fi
}

eventer_disable() {
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        log "(dry-run) remove $USER_SYSTEMD_DIR/$EVENT_UNIT.timer + .service"
        return 0
    fi
    if [ -f "$USER_SYSTEMD_DIR/$EVENT_UNIT.timer" ]; then
        systemctl --user disable --now "$EVENT_UNIT.timer" >/dev/null 2>&1 || true
        rm -f "$USER_SYSTEMD_DIR/$EVENT_UNIT.timer" "$USER_SYSTEMD_DIR/$EVENT_UNIT.service"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        ok "$EVENT_UNIT.timer disabled"
    else
        warn "$EVENT_UNIT.timer is not enabled"
    fi
}

eventer_status() {
    if [ -f "$USER_SYSTEMD_DIR/$EVENT_UNIT.timer" ] && systemctl --user show-environment >/dev/null 2>&1 \
        && systemctl --user is-enabled "$EVENT_UNIT.timer" >/dev/null 2>&1; then
        eventer_read_rules
        local oncal next
        oncal="$(sed -n 's/^OnCalendar=//p' "$USER_SYSTEMD_DIR/$EVENT_UNIT.timer")"
        next="$(systemctl --user list-timers "$EVENT_UNIT.timer" --no-legend 2>/dev/null | awk '{print $1, $2}' | head -1)"
        echo "enabled — schedule: ${oncal}${next:+ (next: $next)}"
        echo "rules: $(eventer_count_rules) in $CONFIG_FILE"
    else
        echo "not enabled (run: pos system event-trigger enable [interval])"
    fi
}
