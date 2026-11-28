#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/ui.sh"

timer_start
ui_info "Running post-install..."

# ── Ensure all bin dirs are in PATH ────────────────────────────
PATH_LINE='export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$PATH"'
BASHRC="$HOME/.bashrc"

if grep -qsF "$PATH_LINE" "$BASHRC" 2>/dev/null; then
    ui_info "PATH already configured"
else
    run echo "$PATH_LINE" >> "$BASHRC"
    ui_info "Added PATH to ~/.bashrc"
fi

# ── Bash completion for pos ─────────────────────────────────────
COMPLETION_LINE='source /usr/local/share/bash-completion/completions/pos.bash 2>/dev/null || true'

if grep -qsF "pos.bash" "$BASHRC" 2>/dev/null; then
    ui_info "pos completion already configured"
else
    run echo "$COMPLETION_LINE" >> "$BASHRC"
    ui_info "Added pos completion to ~/.bashrc"
fi

if [ -f completions/pos.bash ]; then
    run sudo mkdir -p /usr/local/share/bash-completion/completions
    run sudo install -m 644 completions/pos.bash \
        /usr/local/share/bash-completion/completions/pos.bash
    ui_info "Installed pos completion"
else
    ui_warning "completions/pos.bash not found, skipping"
fi

# ── SSH authorized keys ────────────────────────────────────────
SSH_DIR="$HOME/.ssh"
AUTH_FILE="$SSH_DIR/authorized_keys"
KEY_FILE="config/authorized_keys"

if [ -f "$KEY_FILE" ]; then
    run mkdir -p "$SSH_DIR"
    run chmod 700 "$SSH_DIR"
    run touch "$AUTH_FILE"
    run chmod 600 "$AUTH_FILE"

    added=0
    while IFS= read -r key; do
        [[ -z "$key" || "$key" == \#* ]] && continue
        if grep -qsF "$key" "$AUTH_FILE" 2>/dev/null; then
            ui_info "SSH key already present"
        else
            run echo "$key" >> "$AUTH_FILE"
            added=$((added + 1))
        fi
    done < "$KEY_FILE"
    if [ "$added" -gt 0 ]; then
        ui_info "Installed $added SSH key(s)"
    elif ! grep -qE '^[[:space:]]*[^#[:space:]]' "$KEY_FILE"; then
        ui_info "config/authorized_keys is empty — nothing to add"
    fi
else
    ui_warning "config/authorized_keys not found, skipping SSH setup"
fi

if [ "${DRY_RUN:-0}" -eq 1 ]; then
    ui_info "(dry-run) Post-install plan complete" "$(timer_stop)"
else
    ui_success "Post-install complete" "$(timer_stop)"
fi
