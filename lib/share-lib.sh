# lib/share-lib.sh — precondition probes, remote listings and advisories for
# the `pos share` suite (nfs/smb/usb tools), plus compat shims to the
# category-neutral menu layer (lib/menu-lib.sh).
#
# Contracts (all of them, no exceptions):
#   * Defines ONLY `share_*` functions — sourcing never clobbers a tool's own
#     helpers (same discipline as lib/notify.sh).
#   * Requires common.sh to be sourced by the CALLER first (log/warn/err/
#     confirm/run/spawn + CYAN/RESET colors are used, never defined here).
#   * NEVER exits and never terminates the caller: every function returns,
#     failures are signalled through the return code.
#   * Display goes to stderr, results go to stdout — any function whose result
#     is meant to be command-substituted prints ONLY the result on stdout
#     (matches the ui_pick contract in the telegram/matrix listeners).
#   * Performs NO file writes of its own — every path a tool persists stays
#     tool-owned (the env-seam surface does not grow here).
#
# Function index:
#   share_menu_run <title> <item...>    shim → menu_run (lib/menu-lib.sh)
#   share_pick <prompt> <item...>       shim → menu_pick (lib/menu-lib.sh)
#   share_ask_value <label> [default]   shim → menu_ask_value (lib/menu-lib.sh)
#   share_menu_guard                    shim → menu_guard (lib/menu-lib.sh)
#   share_require_bin <bin> <hint>      dependency probe (rc only)
#   share_port_probe <host> <port>      TCP reachability probe (rc only)
#   share_service_active <unit>         systemd unit state probe (rc only)
#   share_ufw_blocks_ports <egrep>      ufw-blocking decision (rc only)
#   share_offer_fix <desc> <cmd...>     advisory remediation offer (rc always 0)
#   share_nfs_exports <host>            remote export list via showmount
#   share_smb_shares <host> [user]      remote Disk-share list via smbclient
#   share_usb_devices / _clients        usbsrv listing records as "ID|display"
#   share_folder_candidates             mountpoint/dir candidates for sharing

# ── Menu primitives live in lib/menu-lib.sh (category-neutral) ─
# The generic interactive layer was extracted there; these thin shims keep the
# public `share_*` names/contracts identical for all five share tools. Delegation
# preserves rc semantics 1:1 (guard rc, EOF → rc 1, index/value → stdout only).
source "$(dirname "${BASH_SOURCE[0]}")/../lib/menu-lib.sh" 2>/dev/null \
    || source "$(dirname "${BASH_SOURCE[0]}")/menu-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/../lib/menu-lib.sh" 2>/dev/null \
    || source "$(dirname "$0")/menu-lib.sh"

share_menu_guard() { menu_guard "$@"; }
share_menu_run() { menu_run "$@"; }
share_pick() { menu_pick "$@"; }
share_ask_value() { menu_ask_value "$@"; }

# ── Dependency probe (NOT an err wrapper) ──────────────────────
# rc 0 present · rc 1 absent. Callers decide between err() and graceful
# degradation; <hint> documents intent at call sites and is intentionally
# not printed here (message policy belongs to the caller).
share_require_bin() {
    command -v "$1" >/dev/null 2>&1
}

# ── TCP reachability probe (generalized probe_server core) ─────
# rc 0 reachable within 3s · rc 1 unreachable/no-route. Message policy (targeted
# hints, firewall wording) belongs to the caller.
share_port_probe() {
    timeout 3 bash -c "exec 3<>/dev/tcp/${1}/${2}" 2>/dev/null
}

# ── systemd unit state probe ───────────────────────────────────
# rc 0 active · rc 1 inactive/unqueryable (nonzero systemctl codes normalized).
share_service_active() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ── Bounded path probe ─────────────────────────────────────────
# share_path_probe <-d|-w> <path> — rc 0 when the stat answers within 2s.
# Guards discovery against wedged network mountpoints where a plain
# `[ -d … ]` would block forever.
share_path_probe() {
    timeout 2 bash -c '[ "$1" "$2" ]' _ "$1" "$2" 2>/dev/null
}

# ── ufw blocking decision ──────────────────────────────────────
# Core moved verbatim from pos-share-smb-server's ufw_blocks_samba, with the
# rule pattern parameterized. rc 0 = ufw active but no matching rule (traffic
# blocked) · rc 1 = ufw absent/inactive OR a matching rule exists (not blocking).
# Callers own all message text.
share_ufw_blocks_ports() {
    command -v ufw >/dev/null 2>&1 || return 1
    local st
    st="$(sudo ufw status 2>/dev/null)" || return 1
    grep -q "^Status: active" <<<"$st" || return 1
    if grep -qiE "$1" <<<"$st"; then
        return 1
    fi
    return 0
}

# ── Advisory remediation offer ─────────────────────────────────
# On a terminal: confirm "<desc>. Fix it now?" (default No) and run/spawn the
# command, reporting the outcome. Without a terminal: print desc + manual
# command as a hint-only warning. ALWAYS rc 0 — purely advisory; aborting on a
# declined offer stays the caller's confirm/err decision.
share_offer_fix() {
    local desc="$1"; shift
    if [ -t 0 ]; then
        echo >&2
        if confirm "$desc. Fix it now?" n; then
            if run "$@"; then
                ok "Fixed: $*"
            else
                warn "Fix command failed: $*"
            fi
        else
            warn "Declined — run manually: $*"
        fi
    else
        warn "$desc — run manually: $*"
    fi
    return 0
}

# ── Remote NFS export enumeration ──────────────────────────────
# stdout: export paths, one per row (column 1 of the showmount table, header
# skipped). rc 0 ok · rc 1 unavailable (showmount missing / timeout / RPC
# failure / no exports) with the reason warned on stderr.
share_nfs_exports() {
    local host="$1" out rows
    if ! command -v showmount >/dev/null 2>&1; then
        printf '[!] showmount not found (install nfs-common) — cannot list exports from %s\n' "$host" >&2
        return 1
    fi
    if ! out="$(timeout 5 showmount -e "$host" 2>&1)"; then
        printf "[!] could not list exports from %s (server down, RPC/firewall blocked, or timeout)\n" "$host" >&2
        return 1
    fi
    rows="$(awk 'NF > 0 && $1 !~ /^Export/ {print $1}' <<<"$out")"
    if [ -z "$rows" ]; then
        printf "[!] no exports visible on %s\n" "$host" >&2
        return 1
    fi
    printf '%s\n' "$rows"
}

# ── Remote SMB share enumeration ───────────────────────────────
# stdout: Disk share names, one per line (-g parse; IPC$/printer `*$` names
# dropped). Sets SMB_AUTH_USER="" at entry, and to the account that ended up
# authenticating, so callers can reuse it for the actual mount:
#   * user argument given  → authenticate immediately (password prompted,
#     travels via the PASSWD environment, never argv); no guest attempt.
#   * no user argument     → guest query first; on ACCESS_DENIED /
#     LOGON_FAILURE a Samba user + password are asked once (TTY required)
#     and the query retries.
# rc 0 ok · rc 1 unavailable / failed-after-retry (reason warned on stderr).
share_smb_shares() {
    local host="$1" user="${2:-}" out names pw u
    local -r GPARSE='BEGIN { FS = "|" } $1 == "Disk" && $2 != "" && $2 != "IPC$" && $2 !~ /\$$/ { print $2 }'
    SMB_AUTH_USER=""
    if ! command -v smbclient >/dev/null 2>&1; then
        printf '[!] smbclient not found — cannot enumerate shares (install the smbclient package)\n' >&2
        return 1
    fi

    if [ -n "$user" ]; then
        if ! [ -t 0 ]; then
            printf '[!] Samba login for %s needs a terminal (password prompt)\n' "$host" >&2
            return 1
        fi
        read -rsp "Samba password for $user: " pw || { echo >&2; return 1; }
        echo >&2
        if out="$(PASSWD="$pw" smbclient -L "//${host}/" -g -t 5 -U "$user" 2>&1)"; then
            SMB_AUTH_USER="$user"
        else
            printf '[!] share enumeration failed for %s@%s (wrong user/password?)\n' "$user" "$host" >&2
            return 1
        fi
    else
        if ! out="$(smbclient -L "//${host}/" -N -g -t 5 2>&1)"; then
            case "$out" in
                *ACCESS_DENIED*|*LOGON_FAILURE*|*NOT_GRANTED*)
                    if ! [ -t 0 ]; then
                        printf '[!] %s requires authentication — rerun interactively (menu) to enter a Samba user\n' "$host" >&2
                        return 1
                    fi
                    printf '[!] %s rejected guest access — a Samba login is required\n' "$host" >&2
                    u="$(share_ask_value "Samba user for ${host}")" || return 1
                    read -rsp "Samba password for $u: " pw || { echo >&2; return 1; }
                    echo >&2
                    if ! out="$(PASSWD="$pw" smbclient -L "//${host}/" -g -t 5 -U "$u" 2>&1)"; then
                        printf '[!] share enumeration failed for %s@%s after retry\n' "$u" "$host" >&2
                        return 1
                    fi
                    SMB_AUTH_USER="$u"
                    ;;
                *)
                    printf '[!] could not enumerate shares on %s: %s\n' "$host" "$(head -1 <<<"$out")" >&2
                    return 1
                    ;;
            esac
        fi
    fi

    names="$(printf '%s\n' "$out" | awk "$GPARSE")"
    if [ -z "$names" ]; then
        printf '[!] no Disk shares visible on %s\n' "$host" >&2
        return 1
    fi
    printf '%s\n' "$names"
}

# ── USB Redirector listings ────────────────────────────────────
# Both emit blank-line-split records as "ID|display-line" rows; rc 0 parsed ≥1
# record · rc 1 unparsable/down — callers fall back to the raw listing plus a
# manual ID entry (= today's UX).
share_usb_records() { # internal helper: stdin = raw listing, $1 = ID-line regex
    awk -v idre="$1" '
        BEGIN { RS = "" }
        {
            n = split($0, L, "\n")
            id = ""; desc = ""; fb = ""
            for (i = 1; i <= n; i++) {
                line = L[i]
                if (line ~ idre && id == "") {
                    id = line
                    sub(/^[^:]*:[ \t]*/, "", id)
                } else if (line ~ /^Description:/) {
                    desc = line
                    sub(/^Description:[ \t]*/, "", desc)
                } else if (fb == "") {
                    fb = line
                }
            }
            if (id != "") print id "|" (desc != "" ? desc : fb)
        }'
}

share_usb_devices() {
    local raw recs
    if ! command -v usbsrv >/dev/null 2>&1; then
        printf '[!] usbsrv not found — install the USB Redirector server first\n' >&2
        return 1
    fi
    if ! raw="$(usbsrv -list-devices 2>&1)"; then
        printf '[!] usbsrv -list-devices failed — is the USB Redirector server running?\n' >&2
        return 1
    fi
    recs="$(printf '%s\n' "$raw" | share_usb_records '^ID:')"
    if [ -z "$recs" ]; then
        printf '[!] no USB device records could be parsed from the server listing\n' >&2
        return 1
    fi
    printf '%s\n' "$recs"
}

share_usb_clients() {
    local raw recs
    if ! command -v usbsrv >/dev/null 2>&1; then
        printf '[!] usbsrv not found — install the USB Redirector server first\n' >&2
        return 1
    fi
    if ! raw="$(usbsrv -list-clients 2>&1)"; then
        printf '[!] usbsrv -list-clients failed — is the USB Redirector server running?\n' >&2
        return 1
    fi
    recs="$(printf '%s\n' "$raw" | share_usb_records '^Client ID:')"
    if [ -z "$recs" ]; then
        printf '[!] no connected clients could be parsed from the server listing\n' >&2
        return 1
    fi
    printf '%s\n' "$recs"
}

# ── Share-folder candidates ────────────────────────────────────
# stdout: candidate paths, one per line — writable real-filesystem findmnt
# targets (pseudo-fs denylist and read-only mounts excluded) ∪ immediate
# directories under /mnt,/srv,/media,/export. LC_ALL=C sorted, deduplicated;
# entries that are mountpoints carry a "(mounted <fstype>)" annotation.
# rc 0 always; an empty list is allowed (caller falls back to manual entry).
share_folder_candidates() {
    local -A seen=()
    local line fs tgt opts entry child r path fst
    local -a cands=()

    # findmnt targets: split TARGET FSTYPE OPTIONS (TARGET may hold escaped
    # spaces, OPTIONS/FSTYPE never do) — pseudo-fs denylist + ro exclusion.
    while IFS=$'\t' read -r fs tgt opts; do
        [ -n "$tgt" ] || continue
        case "$fs" in
            proc | sysfs | devtmpfs | devpts | tmpfs | cgroup | cgroup2 | squashfs | \
                overlay | mqueue | hugetlbfs | debugfs | tracefs | configfs | fusectl | \
                securityfs | pstore | efivarfs | bpf | ramfs | nsfs | binfmt_misc | autofs | \
                iso9660 | swap | fuse.* | cgroupfs) continue ;;
        esac
        case ",$opts," in *,ro,*) continue ;; esac
        share_path_probe -w "$tgt" || continue
        cands+=("${tgt}|${fs}")
    done < <(timeout 5 findmnt -rn -o TARGET,FSTYPE,OPTIONS 2>/dev/null |
        awk '{ opts=$NF; fstype=$(NF-1); tgt=substr($0, 1, length($0)-length(opts)-length(fstype)-1); sub(/[ \t]+$/, "", tgt); print fstype "\t" tgt "\t" opts }')

    # immediate directories under the conventional share roots
    for r in /mnt /srv /media /export; do
        [ -d "$r" ] || continue
        for child in "$r"/*; do
            share_path_probe -d "$child" || continue
            cands+=("${child}|")
        done
    done

    # annotate mountpoints, prefer annotated duplicates, sort byte-order
    for line in "${cands[@]}"; do
        path="${line%%|*}"
        fst="${line#*|}"
        if [ -n "$fst" ]; then
            seen["$path"]="${path} (mounted ${fst})"
        elif [ -z "${seen[$path]:-}" ]; then
            seen["$path"]="$path"
        fi
    done
    for path in "${!seen[@]}"; do
        printf '%s\n' "${seen[$path]}"
    done | LC_ALL=C sort -u
}
