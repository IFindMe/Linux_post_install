# lib/notify.sh — optional MULTI-PLATFORM alerting helper. Self-contained by
# design: defines ONLY notify_send() + notify_platforms() (plus internal
# helpers) so it can be sourced by tools that define their own log/warn/err
# (e.g. pos-system-firewall) without clobbering.
#
# Usage (opt-in — source it, do NOT auto-load from common.sh):
#   source "$(dirname "$0")/../lib/notify.sh" 2>/dev/null || source "$(dirname "$0")/notify.sh"
#   notify_send "Backup completed: $ARCHIVE"
#   notify_send "**disk full**" --markdown
#
# Platform routing — ~/.config/linux_post_install/notify.env:
#   NOTIFY_PLATFORM=telegram,matrix
# Comma-separated = send to every listed platform (default: telegram).
#
# Sender contract — each platform is a bin/pos-communication-<platform> tool
# that MUST implement:
#   pos-communication-<platform> send <value> [--markdown]
#   (exit 0 on delivery; non-zero on failure)
# NOTE: the telegram sender tool is named `pos-communication-telegram-sender`;
# notify_sender_name() maps the platform key "telegram" → "telegram-sender".
# To add a platform (e.g. Matrix/Synapse), add `bin/pos-communication-matrix`
# implementing that interface and put `matrix` in NOTIFY_PLATFORM.
#
# Silent-fails per platform: a missing sender or a failed send only warns and
# never changes the caller's exit code.

CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/linux_post_install}"

# Platform key → sender tool name (bin/pos-communication-<name>).
notify_sender_name() {
    case "${1:-}" in
        telegram) echo telegram-sender ;;
        *)        echo "${1:-}" ;;
    esac
}

# Effective platform list (env > notify.env > "telegram").
notify_platforms() {
    local p="${NOTIFY_PLATFORM:-}"
    if [ -z "$p" ] && [ -f "$CONFIG_DIR/notify.env" ]; then
        p="$(grep -E '^NOTIFY_PLATFORM=' "$CONFIG_DIR/notify.env" | tail -1 | cut -d= -f2-)"
        p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"
    fi
    printf '%s' "${p:-telegram}"
}

notify_send() {
    local msg="" markdown=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --markdown) markdown=1; shift ;;
            *) msg="$1"; shift ;;
        esac
    done

    if [ -z "$msg" ]; then
        warn "notify_send: empty message, skipped" 2>/dev/null || echo "notify_send: empty message, skipped" >&2
        return 0
    fi

    local -a plist
    IFS=',' read -r -a plist <<< "$(notify_platforms)"

    local p sender sname
    for p in "${plist[@]}"; do
        p="${p// /}"
        [ -n "$p" ] || continue
        sname="$(notify_sender_name "$p")"
        sender="$(command -v "pos-communication-${sname}" 2>/dev/null)" || \
            sender="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../bin/pos-communication-${sname}"

        if [ ! -x "$sender" ]; then
            warn "notify_send: pos-communication-${sname} not found, notification skipped" 2>/dev/null || true
            continue
        fi

        if [ "$markdown" -eq 1 ]; then
            "$sender" send "$msg" --markdown >/dev/null 2>&1 || {
                warn "notify_send: ${p} send failed, notification skipped" 2>/dev/null || true
            }
        else
            "$sender" send "$msg" >/dev/null 2>&1 || {
                warn "notify_send: ${p} send failed, notification skipped" 2>/dev/null || true
            }
        fi
    done
}
