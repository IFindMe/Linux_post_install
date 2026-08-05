#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# TEMPLATE — new `pos` CLI tool
#
#  1. Copy:     cp templates/pos-tool.sh bin/pos-<category>-<command>
#  2. Exec bit: chmod +x bin/pos-<category>-<command>
#  3. Register: add the command to usage() CATEGORIES/EXAMPLES in bin/pos
#     If it reads stdin (password/selection prompts), also add it to
#     INTERACTIVE_CMDS in bin/pos or its prompt breaks under the log tee.
#  4. Docs:     DOC/POS.md section table + detail block,
#     DOC/AGENT_Context_Project.md (bin tree, dispatch table,
#     self-contained list, file line-count table), root README.md only
#     when the category list changes.
#  5. Deps:     add packages to PACKAGES in preinstall.sh if needed.
#
# Invoked as:  pos <category> <command> [args]
# ────────────────────────────────────────────────────────────────

# Robust common.sh load — works from the repo checkout AND from
# /usr/local/bin after install.sh (which copies lib/common.sh there).
source "$(dirname "$0")/../lib/common.sh" 2>/dev/null || source "$(dirname "$0")/common.sh"

# Optional runtime config (see DEV.md "Config files"):
# CONFIG_FILE="$HOME/.config/linux_post_install/<tool>.env"

usage() {
    cat <<EOF
Usage: pos <category> <command> [args]

<describe what this command does>

Examples:
  pos <category> <command> arg1
EOF
    exit 0
}

case "${1:-}" in
    -h|--help) usage ;;
esac

# ── script logic ────────────────────────────────────────────────
# Use helpers from common.sh: log / warn / err / ok / section /
# step / run (respects --dry-run) / spawn / confirm.
#
#   command -v <dep> &>/dev/null || err "<dep> not found"
#   run sudo <command>                          # dry-run aware
#   log "done"                                  # green [+] message
#
# Exit 0 on success, err() exits 1 on failure.
