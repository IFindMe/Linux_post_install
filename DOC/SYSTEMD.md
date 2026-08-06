# Systemd & Shell Integration Reference

The units installed and enabled by `postinstall.sh`, plus the `pos` bash completion.

- [Services](#services)
  - [`autostart.service`](#autostartservice)
  - [`ssh-agent.service`](#ssh-agentservice)
  - [`pos-health.service`](#pos-healthservice)
- [Feature-flag gating](#feature-flag-gating)
- [Bash completion](#bash-completion)

---

## Services

`postinstall.sh` copies every `systemd/*.service` (and `systemd/*.timer`) to `/etc/systemd/system/`, runs `systemctl daemon-reload`, then enables each one (see the gating rule below).

### autostart.service

**Purpose:** run `features/autostart.sh` at boot (after the network is online) and keep retrying if it fails.

```ini
[Unit]
Description=My Linux Autostart Script
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/autostart.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Configuration:** point `ExecStart` at your boot script. Because the target script is a *feature*, this unit is only **enabled** when the `autostart` flag is set — the file is still copied, but a skipped feature leaves the unit present-but-disabled.

### ssh-agent.service

**Purpose:** a system-wide SSH agent, one shared socket for all sessions (so `pos ssh load-keys` and everyday ssh work without per-login agents).

```ini
[Unit]
Description=SSH Authentication Agent
After=network.target

[Service]
Type=simple
ExecStartPre=mkdir -p /run/ssh-agent
ExecStart=/usr/bin/ssh-agent -D -a /run/ssh-agent/socket
ExecStartPost=/bin/sh -c 'chmod 666 /run/ssh-agent/socket'
ExecStopPost=/bin/sh -c 'rm -f /run/ssh-agent/socket'
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**Configuration:** socket at `/run/ssh-agent/socket` (world-readable/writable). `~/.bashrc` (set by `postinstall.sh`) exports `SSH_AUTH_SOCK` to it. Not gated on any feature flag.

### pos-health.service

**Purpose:** daily "health digest" — runs `pos system health --send --markdown` at 08:00 and sends the report to Telegram.

```ini
[Unit]
Description=POS Health digest (daily report via Telegram)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=__POS_USER__
ExecStart=/usr/local/bin/pos system health --send --markdown

[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true
```

The service is `Type=oneshot` and is driven **only** by its companion `pos-health.timer` (`WantedBy=timers.target`); the service itself is never enabled directly.

**Configuration:** `postinstall.sh` substitutes `__POS_USER__` with the installing user (`${SUDO_USER:-$USER}`) so the digest uses that user's real Telegram config. The timer is enabled only when `~/.config/linux_post_install/telegram.env` already exists — otherwise postinstall warns and skips; re-run postinstall after configuring Telegram (`pos communication telegram config set TELEGRAM_*`) to install it.

---

## Feature-flag gating

The systemd loop in `postinstall.sh` special-cases two units:

```bash
if [ "$svc_name" = "autostart.service" ] && ! flag_is_set autostart; then
    warn "autostart feature not installed — skipping autostart.service (run ./install.sh --feature)"
    continue
fi
if [ "$svc_name" = "pos-health.service" ]; then
    # substitute User= and enable pos-health.timer only if Telegram is configured
fi
```

- `autostart.service` is **enabled** only when the `autostart` feature flag is set (`./install.sh --feature` or `flag-set autostart`). See [SCRIPTS.md → lib/flags.sh](SCRIPTS.md#libflagssh--feature-flags).
- `pos-health.service` is **not** enabled at all — `postinstall.sh` enables `pos-health.timer` instead, and only when a Telegram config already exists.

---

## Bash completion

**File:** `completions/pos.bash`
**Purpose:** tab-completion for the `pos` CLI.

### How it works

- **Dynamically discovers** subcommands by listing executable `pos-*` files next to the `pos` binary — no hard-coded command list, so new tools complete automatically.
- Works with the `bash-completion` package (`_init_completion`) and falls back to a manual init if it isn't loaded.
- Provides completion for the first two words of `pos <category> <command>`.

### Configuration

Installed by `postinstall.sh` to `/usr/local/share/bash-completion/completions/pos.bash` and sourced from `~/.bashrc`. To load it manually: `source completions/pos.bash` (or copy into `/etc/bash_completion.d/`).
