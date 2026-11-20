#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────────────────────
# TEMPLATE — new `pos` CLI tool
#
#  1. Copy:     cp templates/pos-tool.sh bin/pos-<category>-<command>
#  2. Header:   add a `# POS:` line right after the shebang/strict-mode
#               lines (metadata consumed by pos tree / completion):
#                 # POS: <category> <command> — one-line description
#                 # POS_FLAGS: --flag1 --flag2   (flag-style tools only)
#                 # POS_SUBCMDS: sub1 sub2       (multi-command tools only)
#                 # POS_DEPS: binary1 binary2    (runtime deps, optional)
#                 # POS_EXAMPLES: pos <tool> <args> | Description  (optional)
#  3. Exec bit: chmod +x bin/pos-<category>-<command>
#  4. If it reads stdin (password/selection prompts), add it to
#     INTERACTIVE_CMDS in bin/pos or its prompt breaks under the log tee.
#  5. Deps:     add apt packages to PACKAGES in preinstall.sh; non-apt
#               installers → `command -v <bin> || err "install from <URL>"`.
#  6. Done:     bash -n <file> && bin/pos tree && git diff --check
#
# Invoked as:  pos <category> <command> [args]
# ────────────────────────────────────────────────────────────────

# Robust common.sh load — works from the repo checkout AND from
# /usr/local/bin after install.sh (which copies lib/common.sh there).
source "$(dirname "$0")/../lib/common.sh" 2>/dev/null || source "$(dirname "$0")/common.sh"

# Optional runtime config (hand-written file; exported env vars win):
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
