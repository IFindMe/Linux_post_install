#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# USB automount feature — auto-mounts removable USB storage.
#
# Installed on demand with:  ./install.sh --feature
#   → copied to /usr/local/bin/usb-automount.sh (chmod 755)
#   → flag "usb-automount" is set
#
# Triggers:
#   - boot + hotplug via systemd/usb-automount.service (the udev
#     rule below is self-installed on first root run)
#   - manual:  sudo usb-automount.sh
#
# Behavior: mounts every unmounted removable block device at
# /media/<label>, world-writable (-o umask=000) so non-root users
# can write — this is what lets `pos system backup` copy the
# verified archive onto a stick. Idempotent: already-mounted
# devices are skipped, repeated runs are no-ops.
# ────────────────────────────────────────────────────────────────

# Log — root/systemd runs have no $HOME (same convention as autostart.sh).
LOG="${HOME:-/root}/.usb-automount.log"

# Test-only seams (DEV.md env-seam registry):
#   AUTOMOUNT_SKIP_ROOT_GUARD=1   skip the sudo re-exec (stub suites)
#   UDEV_RULES_DIR=<dir>          where the udev rule goes
#   UDEVADM=<path>                udevadm binary (or stub)
#   MOUNT_BASE=<dir>              mount point base (stub suites use a tmpdir)
RULES_DIR="${UDEV_RULES_DIR:-/etc/udev/rules.d}"
RULE_FILE="$RULES_DIR/99-usb-automount.rules"
UDEV_RULE='ACTION=="add", KERNEL=="sd[a-z]*", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", TAG+="systemd", SYSTEMD_WANTS="usb-automount.service"'
MOUNT_BASE="${MOUNT_BASE:-/media}"

usage() {
    cat <<EOF
Usage: usb-automount.sh [options]

Auto-mount USB storage: every unmounted removable block device is
mounted at /media/<label> (world-writable). Idempotent.

Triggers:
  - boot and hotplug via usb-automount.service (udev rule installed
    on first root run, service flag-gated in postinstall.sh)
  - manual:  sudo usb-automount.sh

Installed via:  ./install.sh --feature
Flag:           usb-automount
Log:            ${HOME:-/root}/.usb-automount.log
EOF
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
esac

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG" 2>/dev/null || true
}

# ── dependency guard ────────────────────────────────────────────
for dep in lsblk jq mount mountpoint; do
    command -v "$dep" &>/dev/null || {
        log "missing dependency: $dep"
        exit 1
    }
done

# ── root guard: mounting + udev need root ───────────────────────
if [ "$(id -u)" -ne 0 ] && [ "${AUTOMOUNT_SKIP_ROOT_GUARD:-0}" != "1" ]; then
    exec sudo "$0" "$@"
fi

# ── udev rule: hotplug trigger, self-installed once ─────────────
# Installed on first root run only — an existing (possibly
# user-edited) rule is never overwritten.
install_udev_rule() {
    mkdir -p "$RULES_DIR"
    if [ ! -f "$RULE_FILE" ]; then
        printf '%s\n' "$UDEV_RULE" > "$RULE_FILE"
        "${UDEVADM:-udevadm}" control --reload
        "${UDEVADM:-udevadm}" trigger --subsystem-match=block
        log "installed udev rule: $RULE_FILE"
    fi
}

# ── mount one device at /media/<label> (bump -2, -3 on collision)
mount_one() {
    local dev="$1" label="$2" mp n

    label="${label//\//_}"
    mp="$MOUNT_BASE/${label:-usb-$(basename "$dev")}"

    # Label already in use as a mountpoint (another stick) → bump.
    if [ -d "$mp" ] && mountpoint -q "$mp" 2>/dev/null; then
        n=2
        while [ -d "${mp}-${n}" ] && mountpoint -q "${mp}-${n}" 2>/dev/null; do
            n=$((n + 1))
        done
        mp="${mp}-${n}"
    fi

    mkdir -p "$mp"
    if mount -o umask=000 "$dev" "$mp" 2>/dev/null; then
        log "mounted $dev -> $mp (umask=000, world-writable)"
    elif mount "$dev" "$mp" 2>/dev/null; then
        log "mounted $dev -> $mp (plain)"
    else
        log "FAILED to mount $dev -> $mp"
    fi
}

# ── scan: unmounted removable partitions / raw whole-disk FS ────
mount_removable() {
    local out
    out="$(lsblk -J -o NAME,PATH,LABEL,MOUNTPOINT,RM,TYPE 2>/dev/null)" || {
        log "lsblk failed"
        return 1
    }
    while IFS=$'\t' read -r dev label; do
        [ -n "$dev" ] || continue
        mount_one "$dev" "$label"
    done < <(printf '%s' "$out" | jq -r '
        .. | objects
        | select(.rm == true and .mountpoint == null and
                 (.type == "part" or (.type == "disk" and ((.children // []) | length) == 0)))
        | [.path, (.label // "")] | @tsv')
}

install_udev_rule
mount_removable
exit 0
