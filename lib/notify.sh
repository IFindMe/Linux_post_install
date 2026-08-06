#!/usr/bin/env bash
# lib/notify.sh — optional alerting helper. Self-contained by design:
# defines ONLY notify_send() so it can be sourced by tools that define
# their own log/warn/err (e.g. pos-system-firewall) without clobbering.
#
# Usage (opt-in — source it, do NOT auto-load from common.sh):
#   source "$(dirname "$0")/../lib/notify.sh" 2>/dev/null || source "$(dirname "$0")/notify.sh"
#   notify_send "Backup completed: $ARCHIVE"
#   notify_send "⚠ disk full" --markdown
#
# Delegates to `pos communication telegram send`; silent-fail if the
# telegram sender is missing or not configured (warns, never breaks the
# caller and never changes its exit code).

notify_send() {
    local msg="" markdown=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --markdown) markdown=1; shift ;;
            *) msg="$1"; shift ;;
        esac
    done

    if [ -z "$msg" ]; then
        warn "notify_send: empty message, skipped" 2>/dev/null || echo "notify_send: empty message, skipped"
        return 0
    fi

    local tg
    tg="$(command -v pos-communication-telegram 2>/dev/null)" || \
        tg="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../bin/pos-communication-telegram"

    if [ ! -x "$tg" ]; then
        warn "notify_send: pos-communication-telegram not found, notification skipped" 2>/dev/null || true
        return 0
    fi

    if [ "$markdown" -eq 1 ]; then
        "$tg" send "$msg" --parse-mode markdown >/dev/null 2>&1 || {
            warn "notify_send: telegram send failed, notification skipped" 2>/dev/null || true
        }
    else
        "$tg" send "$msg" >/dev/null 2>&1 || {
            warn "notify_send: telegram send failed, notification skipped" 2>/dev/null || true
        }
    fi
}
