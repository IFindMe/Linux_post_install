#!/usr/bin/env bash
# Optional shell hook for pos ai * --last: auto-captures terminal output.
# Usage: add to ~/.bashrc:
#   source /usr/local/bin/pos-ai-hook.sh
#   — or —
#   source /path/to/Linux_post_install/lib/pos-ai-hook.sh
#
# After sourcing, every command's stdout+stderr is silently tee'd to
# ~/.local/share/linux_post_install/last_cmd_output (truncated at 1 MB).
# Then pos ai gemini ask --last / pos ai openrouter ask --last will
# pick it up automatically — no 'capture' subcommand needed.
# To disable: unset __POS_CAPTURE_ACTIVE

__POS_CAPTURE_FILE="${HOME}/.local/share/linux_post_install/last_cmd_output"
__POS_CAPTURE_MAX=${__POS_CAPTURE_MAX:-1048576}  # 1 MB, override with env

# Truncate if oversized (keep last half)
if [ -f "$__POS_CAPTURE_FILE" ]; then
    __sz=$(stat -c%s "$__POS_CAPTURE_FILE" 2>/dev/null || echo 0)
    if [ "$__sz" -gt "$__POS_CAPTURE_MAX" ]; then
        tail -c $((__POS_CAPTURE_MAX / 2)) "$__POS_CAPTURE_FILE" > "${__POS_CAPTURE_FILE}.tmp" 2>/dev/null
        mv -- "${__POS_CAPTURE_FILE}.tmp" "$__POS_CAPTURE_FILE"
    fi
else
    : > "$__POS_CAPTURE_FILE"
fi

# Only activate in interactive terminals, not already redirected
if [ -t 1 ] && [ -t 2 ] && [ -z "${__POS_CAPTURE_ACTIVE:-}" ]; then
    export __POS_CAPTURE_ACTIVE=1
    exec > >(tee -a "$__POS_CAPTURE_FILE" 2>&1) 2>&1
fi
