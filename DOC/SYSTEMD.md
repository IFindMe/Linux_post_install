# Systemd & Shell Integration Reference

The units installed and enabled by `postinstall.sh`, plus the `pos` bash completion.

- [Services](#services)
  - [`autostart.service`](#autostartservice)
  - [`ssh-agent.service`](#ssh-agentservice)
- [Feature-flag gating](#feature-flag-gating)
- [Bash completion](#bash-completion)

---

## Services

`postinstall.sh` copies every `systemd/*.service` to `/etc/systemd/system/`, runs `systemctl daemon-reload`, then enables each one (see the gating rule below).

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

---

## Feature-flag gating

The systemd loop in `postinstall.sh` special-cases `autostart.service`:

```bash
if [ "$svc_name" = "autostart.service" ] && ! flag_is_set autostart; then
    warn "autostart feature not installed — skipping autostart.service (run ./install.sh --feature)"
    continue
fi
```

Set the flag with `./install.sh --feature` (or `flag-set autostart`). See [SCRIPTS.md → lib/flags.sh](SCRIPTS.md#libflagssh--feature-flags).

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
