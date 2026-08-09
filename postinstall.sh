#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/flags.sh"

log "Running post-install..."

# ── rclone config ──────────────────────────────────────────────
# Place your rclone.conf in config/ (gitignored) and this will install it.
if [ -f config/rclone.conf ]; then
    run mkdir -p "$HOME/.config/rclone"
    run cp config/rclone.conf "$HOME/.config/rclone/rclone.conf"
    run chmod 600 "$HOME/.config/rclone/rclone.conf"
    log "Installed rclone.conf"
else
    warn "config/rclone.conf not found, skipping"
fi

# ── entertainment config ───────────────────────────────────────
# Generic template for the weather plugin — copied only if the user
# has not already created their own entertainment.env (no clobber).
ENT_DIR="$HOME/.config/linux_post_install"
if [ -f config/entertainment.env ]; then
    run mkdir -p "$ENT_DIR"
    if [ -f "$ENT_DIR/entertainment.env" ]; then
        log "entertainment.env already exists, keeping it"
    else
        run cp config/entertainment.env "$ENT_DIR/entertainment.env"
        run chmod 600 "$ENT_DIR/entertainment.env"
        log "Installed entertainment.env — set your location:"
        cat "$ENT_DIR/entertainment.env"
    fi
else
    warn "config/entertainment.env not found, skipping"
fi

# ── system + notify config templates ───────────────────────────
# Copied only if the user has not already created their own (no clobber).
run mkdir -p "$ENT_DIR"
for tpl in system.env notify.env ai.env; do
    if [ -f "config/$tpl" ]; then
        if [ -f "$ENT_DIR/$tpl" ]; then
            log "$tpl already exists, keeping it"
        else
            run cp "config/$tpl" "$ENT_DIR/$tpl"
            run chmod 600 "$ENT_DIR/$tpl"
            log "Installed $tpl — edit $ENT_DIR/$tpl"
        fi
    fi
done

# ── Ensure all bin dirs are in PATH ────────────────────────────
PATH_LINE='export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/bin:$PATH"'
BASHRC="$HOME/.bashrc"

if grep -qsF "$PATH_LINE" "$BASHRC" 2>/dev/null; then
    log "PATH already configured"
else
    run echo "$PATH_LINE" >> "$BASHRC"
    log "Added PATH to ~/.bashrc"
fi

# ── Bash completion for pos ─────────────────────────────────────
COMPLETION_LINE='source /usr/local/share/bash-completion/completions/pos.bash 2>/dev/null || true'

if grep -qsF "pos.bash" "$BASHRC" 2>/dev/null; then
    log "pos completion already configured"
else
    run echo "$COMPLETION_LINE" >> "$BASHRC"
    log "Added pos completion to ~/.bashrc"
fi

if [ -f completions/pos.bash ]; then
    run sudo mkdir -p /usr/local/share/bash-completion/completions
    run sudo install -m 644 completions/pos.bash \
        /usr/local/share/bash-completion/completions/pos.bash
    log "Installed pos completion"
else
    warn "completions/pos.bash not found, skipping"
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
            log "SSH key already present"
        else
            run echo "$key" >> "$AUTH_FILE"
            added=$((added + 1))
        fi
    done < "$KEY_FILE"
    if [ "$added" -gt 0 ]; then
        log "Installed $added SSH key(s)"
    fi
else
    warn "config/authorized_keys not found, skipping SSH setup"
fi
# ── systemd services ───────────────────────────────────────────
if [ -d systemd ] && [ -n "$(ls -A systemd/*.service 2>/dev/null)" ]; then
    run sudo cp systemd/*.service /etc/systemd/system/
    if [ -n "$(ls -A systemd/*.timer 2>/dev/null)" ]; then
        run sudo cp systemd/*.timer /etc/systemd/system/
    fi
    run sudo systemctl daemon-reload

    for svc in systemd/*.service; do
        svc_name=$(basename "$svc")
        # autostart.service runs features/autostart.sh — enable only when
        # the autostart feature flag is green (set by ./install.sh --feature)
        if [ "$svc_name" = "autostart.service" ] && ! flag_is_set autostart; then
            warn "autostart feature not installed — skipping autostart.service (run ./install.sh --feature)"
            continue
        fi
        run sudo systemctl enable --now "$svc_name" 2>/dev/null || \
            run sudo systemctl enable "$svc_name"
    done
    log "Systemd services installed and enabled"
else
    warn "No systemd services found, skipping"
fi

log "Post-install completed."
