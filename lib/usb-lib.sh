# lib/usb-lib.sh — shared USB-storage detection + pick flow. Used by
# pos-system-backup (post-verify USB copy) and pos-media-sync (Music sync).
# Requires common.sh helpers: log/warn/ok/section/confirm/run. Defines ONLY
# usb_* functions plus the USB_MOUNTED / USB_UNMOUNTED / USB_ROOT globals.
#
# Seams (env overrides; the BACKUP_* names are kept as aliases so existing
# system.env lines keep working):
#   USB_MOUNT_BASE   where an unmounted stick is offered to mount (default /media)
#   USB_BYID         /dev/disk/by-id dir consulted by usb_related_present
#
# API:
#   usb_detect                    fill USB_MOUNTED (mountpoints, one per
#                                 removable USB storage) and USB_UNMOUNTED
#                                 ("path|label|size|model" entries)
#   usb_related_present           whole-system "is any USB storage attached?"
#   usb_mount_offer <devs...>     offer to mount detected-but-unmounted sticks
#                                 (sudo, mirrors usb-automount: /media/<label>,
#                                 fallback /media/usb-<devname>, umask=000);
#                                 returns 0 = mounted (or user will do it
#                                 manually), 1 = skipped/EOF
#   usb_pick_root <confirm-prefix> <subfolder> <giveup-msg>
#                                 full detect → mount-offer → pick loop; returns
#                                 0 with USB_ROOT set to the chosen mountpoint,
#                                 1 = skipped. Single-stick: confirm
#                                 "<confirm-prefix> <root>/<subfolder>?" first.

USB_MOUNT_BASE="${USB_MOUNT_BASE:-${BACKUP_MOUNT_BASE:-/media}}"
USB_BYID="${USB_BYID:-${BACKUP_USB_BYID:-/dev/disk/by-id}}"

# ── USB detection ────────────────────────────────────────────────
# TRAN=="usb" is the per-device deciding signal; when TRAN is empty,
# usb_related_present() corroborates. Non-USB removables are skipped. The
# "TRAN unavailable" warning fires once per scan, not per device.
usb_detect() {
    local out path="" mp="" label="" size="" model="" tran="" type="" children=""
    local warned=0
    USB_MOUNTED=()
    USB_UNMOUNTED=()
    out="$(lsblk -J -o NAME,PATH,LABEL,MOUNTPOINT,RM,TYPE,TRAN,SIZE,MODEL 2>/dev/null)" || return 0

    while IFS=$'\x1f' read -r path mp label size model tran type children; do
        [ -n "$path" ] || continue
        if [ "$tran" = "usb" ]; then
            :
        elif [ -z "$tran" ] && usb_related_present; then
            if [ "$warned" -eq 0 ]; then
                warn "TRAN unavailable — assuming USB (lsusb/by-id corroboration)"
                warned=1
            fi
        else
            continue
        fi
        if [ -n "$mp" ]; then
            USB_MOUNTED+=("$mp")
        elif [ "$children" = "0" ]; then
            USB_UNMOUNTED+=("$path|$label|$size|$model")
        fi
    done < <(printf '%s' "$out" | jq -r '
        .. | objects
        | select(.rm == true and (.type == "part" or .type == "disk"))
        | [.path, (.mountpoint // ""), (.label // ""), (.size // ""),
           (.model // ""), (.tran // ""), (.type // ""),
           ((.children // []) | length)]
        | join("\u001f")')
}

# Whole-system "is any USB storage attached?" — udev by-id usb-* symlinks
# are definitive; lsusb text is a secondary hint for storage-ish devices.
usb_related_present() {
    [ -n "$(ls "${USB_BYID}"/usb-* 2>/dev/null)" ] && return 0
    command -v lsusb &>/dev/null \
        && lsusb 2>/dev/null | grep -qiE 'mass storage|card reader|flash disk|usb.*(disk|drive|storage)|reader|external'
}

# ── Mount an unmounted USB stick (CLI-box case) ──────────────────
# Returns 0 → caller re-scans (mounted now or the user will mount manually);
# 1 → skipped/EOF.
usb_mount_offer() {
    local -a devs=("$@")
    local i=0 dev="" label="" size="" model="" mp="" resp="" n=""
    local -a chosen=()

    if [ ${#devs[@]} -gt 1 ]; then
        echo "Multiple unmounted USB storages found:"
        for i in "${!devs[@]}"; do
            IFS='|' read -r dev label size model <<< "${devs[$i]}"
            printf "%2d) %s  (%s, %s)\n" "$((i + 1))" "$dev" "$size" "${model:-no label}"
        done
        read -rp "Use which one? [1-${#devs[@]}] (0 = skip): " resp || return 1
        if ! [[ "$resp" =~ ^[0-9]+$ ]] || (( resp < 1 || resp > ${#devs[@]} )); then
            return 1
        fi
        chosen=("${devs[$((resp - 1))]}")
    else
        chosen=("${devs[0]}")
    fi

    IFS='|' read -r dev label size model <<< "${chosen[0]}"
    label="${label//\//_}"
    mp="${USB_MOUNT_BASE}/${label:-usb-$(basename "$dev")}"
    if [ -d "$mp" ] && mountpoint -q "$mp" 2>/dev/null; then
        n=2
        while [ -d "${mp}-${n}" ] && mountpoint -q "${mp}-${n}" 2>/dev/null; do
            n=$((n + 1))
        done
        mp="${mp}-${n}"
    fi

    echo "Found USB storage not mounted: $dev ($size, ${model:-no label})"
    if confirm "Mount it at $mp (world-writable) so we can use it?" n; then
        run sudo mkdir -p "$mp"
        if ! run sudo mount -o umask=000 "$dev" "$mp"; then
            run sudo mount "$dev" "$mp" || true
        fi
        if [ "${DRY_RUN:-0}" -eq 1 ] || mountpoint -q "$mp" 2>/dev/null; then
            ok "Mounted $dev at $mp"
            return 0
        fi
        warn "Mount failed — do it manually:"
        log "  sudo mkdir -p $mp && sudo mount $dev $mp"
    else
        warn "Mount it manually, then we'll continue:"
        log "  sudo mkdir -p $mp"
        log "  sudo mount $dev $mp"
    fi

    read -rp "Press Enter once mounted (or 's' to skip): " resp || return 1
    case "$resp" in
        s|S) return 1 ;;
    esac
    return 0
}

# ── Full pick flow ───────────────────────────────────────────────
# Loops detect → mount-offer (unmounted sticks) → "plug one in" re-scan until a
# mounted USB root is chosen or the user gives up. USB_ROOT is set on success.
usb_pick_root() {
    local confirm_prefix="${1:-Use this storage for}"
    local subfolder="${2:-}"
    local giveup="${3:-skipping}"
    local pass=0 resp="" i=0 root=""
    local -a roots=()
    local offered=0

    while :; do
        pass=$((pass + 1))
        roots=()

        usb_detect
        roots=("${USB_MOUNTED[@]}")

        if [ ${#roots[@]} -eq 0 ] && [ ${#USB_UNMOUNTED[@]} -gt 0 ]; then
            if [ "$offered" -ge 1 ]; then
                warn "USB stick still not mounted — ${giveup}"
                return 1
            fi
            offered=1
            usb_mount_offer "${USB_UNMOUNTED[@]}" || return 1
            continue
        fi

        [ ${#roots[@]} -gt 0 ] && break

        if [ "$pass" -ge 2 ]; then
            warn "Still no USB storage detected — ${giveup}"
            return 1
        fi
        warn "No USB storage detected"
        read -rp "Plug a USB drive in now and press Enter to re-check (or 's' to skip): " resp || return 1
        case "$resp" in
            s|S) return 1 ;;
        esac
    done

    if [ ${#roots[@]} -eq 1 ]; then
        root="${roots[0]}"
        if ! confirm "${confirm_prefix} ${root%/}/${subfolder}?" n; then
            return 1
        fi
    else
        echo "Multiple USB storages found:"
        for i in "${!roots[@]}"; do
            printf "%2d) %s\n" "$((i + 1))" "${roots[$i]}"
        done
        read -rp "Use which one? [1-${#roots[@]}] (0 = skip): " resp || return 1
        if ! [[ "$resp" =~ ^[0-9]+$ ]] || (( resp < 1 || resp > ${#roots[@]} )); then
            return 1
        fi
        root="${roots[$((resp - 1))]}"
    fi

    USB_ROOT="$root"
    return 0
}
