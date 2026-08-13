# Systemd & Shell Integration Reference

The units installed and enabled by `postinstall.sh`, plus the `pos` bash completion.

- [Services](#services)
  - [`autostart.service`](#autostartservice)
  - [`usb-automount.service`](#usb-automountservice)
  - [`ssh-agent.service`](#ssh-agentservice)
  - [`pos-health.service`](#pos-healthservice)
- [Per-user units (`pos network download`)](#per-user-units-pos-network-download)
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

### usb-automount.service

**Purpose:** mount USB storage automatically — at boot (via `WantedBy=multi-user.target`) and on hotplug (a udev rule installed by the feature script triggers this unit). Each run mounts every unmounted removable block device at `/media/<label>`, world-writable (`-o umask=000`), so `pos system backup`'s post-verify USB copy finds the stick and the unprivileged user can write to it.

```ini
[Unit]
Description=Auto-mount USB storage (usb-automount feature)
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/usb-automount.sh

[Install]
WantedBy=multi-user.target
```

**Configuration:** `Type=oneshot` — each start (boot, hotplug, manual `systemctl start usb-automount`) does one idempotent scan. `features/usb-automount.sh` self-installs its udev rule (`/etc/udev/rules.d/99-usb-automount.rules`, `SYSTEMD_WANTS="usb-automount.service"`) on first root run and reloads udev, so plugging in a stick fires the mount with no extra setup; an edited rule is never overwritten. Because the target script is a *feature*, this unit is only **enabled** when the `usb-automount` flag is set — the file is still copied, but a skipped feature leaves the unit present-but-disabled. Hotplug is restricted to USB (`ENV{ID_BUS}=="usb"`); the boot scan covers all removable media.

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

**Purpose:** daily "health digest" — runs `pos system health --send --markdown` at 08:00 and sends the report to the configured notify platform(s).

```ini
[Unit]
Description=POS Health digest (daily report via configured notify platforms)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=__POS_USER__
EnvironmentFile=-%h/.config/linux_post_install/system.env
EnvironmentFile=-%h/.config/linux_post_install/notify.env
ExecStart=/usr/local/bin/pos system health --send --markdown

[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true
```

The service is `Type=oneshot` and is driven **only** by its companion `pos-health.timer` (`WantedBy=timers.target`); the service itself is never enabled directly.

**Configuration:** `postinstall.sh` substitutes `__POS_USER__` with the installing user (`${SUDO_USER:-$USER}`) so the digest uses that user's real notify config. The `EnvironmentFile=` lines load `system.env` (health/backup settings) and `notify.env` (`NOTIFY_PLATFORM`). The timer is enabled only when a Telegram config (`~/.config/linux_post_install/telegram.env`) already exists — otherwise postinstall warns and skips; re-run postinstall after configuring a notify platform to install it.

---

## Per-user units (`pos network download`)

The aria2 download tool installs **user-scope** units (not by postinstall):
written to `~/.config/systemd/user/` and enabled with `systemctl --user` on
first use, so they need no sudo.

- `pos-aria2.service` — the daemon (`Type=simple`, `Restart=on-failure`,
  `WantedBy=default.target`): runs `aria2c --enable-rpc
  --rpc-listen-port=6800 --rpc-secret=… --dir=$HOME/Downloads --continue=true
  --max-connection-per-server=16 --split=16 --seed-time=0`. `pos network
  download start` generates the `RPC_SECRET` into
  `~/.config/linux_post_install/download.env` (chmod 600).
- `pos-aria2-retry.service` — `Type=oneshot`; `ExecStart=<pos> network download
  retry all --once --quiet` (runner = `/usr/local/bin/pos-network-download`,
  repo-path fallback with a warning). Driven only by its companion timer.
- `pos-aria2-retry.timer` — `OnUnitActiveSec=2min` + `OnBootSec=2min`,
  `AccuracySec=30s`, `Persistent=true`, `WantedBy=timers.target`. Arms itself
  when a download starts (`add`/`torrent`/`metalink`/`restart`) and disables
  itself when no active, waiting, or errored downloads remain.

On headless boxes `pos network download start` prints a `loginctl
enable-linger` warning so the user units survive logout.

---

## Feature-flag gating

The systemd loop in `postinstall.sh` special-cases three units:

```bash
if [ "$svc_name" = "autostart.service" ] && ! flag_is_set autostart; then
    warn "autostart feature not installed — skipping autostart.service (run ./install.sh --feature)"
    continue
fi
if [ "$svc_name" = "usb-automount.service" ] && ! flag_is_set usb-automount; then
    warn "usb-automount feature not installed — skipping usb-automount.service (run ./install.sh --feature)"
    continue
fi
if [ "$svc_name" = "pos-health.service" ]; then
    # substitute User= and enable pos-health.timer only if Telegram is configured
fi
```

- `autostart.service` is **enabled** only when the `autostart` feature flag is set (`./install.sh --feature` or `flag-set autostart`). See [SCRIPTS.md → lib/flags.sh](SCRIPTS.md#libflagssh--feature-flags).
- `usb-automount.service` is **enabled** only when the `usb-automount` feature flag is set — same mechanism.
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
