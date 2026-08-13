# lib/user-timers-lib.sh — shared systemd **user** timer machinery for the pos
# tools that schedule one-shot jobs: the entertainment module and the system
# scheduler. Sourced by lib/entertainment-lib.sh and lib/scheduler-lib.sh AFTER
# lib/common.sh. Defines only ut_* helpers so it never collides with either lib.
#
# Both libs previously re-implemented the same interval→OnCalendar mapping, unit
# pair writer and linger bootstrap (the two copies drifted — e.g. the
# TimeoutStopSec fix had to be applied to both). This is the single source for:
#   ut_interval_to_oncalendar  ut_interval_label  ut_unit_name
#   ut_write_unit_pair         ut_ensure_linger

# common.sh helpers (guarded so the lib is safe if common.sh wasn't loaded)
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F ok   >/dev/null || ok()   { echo "  OK $*"; }
declare -F log  >/dev/null || log()  { echo "[+] $*"; }

USER_SYSTEMD_DIR="${USER_SYSTEMD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"

# ── Interval → systemd OnCalendar ─────────────────────────────────
# Named + numeric intervals shared by both schedulers, or a raw OnCalendar=…
# spec passed through unchanged. Returns non-zero for invalid values.
ut_interval_to_oncalendar() {
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

ut_interval_label() {
    case "$1" in
        daily)        echo "daily (08:00)" ;;
        weekly)       echo "weekly (Mon 08:00)" ;;
        hourly)       echo "hourly" ;;
        OnCalendar=*) echo "${1#OnCalendar=}" ;;
        *m|*h|*d)     echo "every $1" ;;
        *)            echo "$1" ;;
    esac
}

# ── Unit naming / writer ──────────────────────────────────────────
ut_unit_name() {   # $1 = prefix (e.g. pos-entertainment), $2 = name → prefix-name
    printf '%s-%s\n' "$1" "$2"
}

# Write one service/timer pair (oneshot, network-online, Persistent).
# Usage: ut_write_unit_pair <service-file> <timer-file> <description> <execstart> <oncal>
ut_write_unit_pair() {
    local svc="$1" timer="$2" desc="$3" execstart="$4" oncal="$5"
    mkdir -p "$USER_SYSTEMD_DIR"
    cat >"$svc" <<EOF
[Unit]
Description=$desc
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$execstart
TimeoutStopSec=5s

[Install]
WantedBy=timers.target
EOF
    cat >"$timer" <<EOF
[Unit]
Description=Schedule: $desc

[Timer]
OnCalendar=$oncal
Persistent=true

[Install]
WantedBy=timers.target
EOF
    chmod 644 "$svc" "$timer"
}

# ── Linger bootstrap ──────────────────────────────────────────────
# Timers only fire without a login when the user has linger enabled; try once,
# warn with the exact command otherwise (never fails the caller).
ut_ensure_linger() {
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
