# `pos` HOW-TO Guides

Hands-on, copy-paste guides for every `pos` category. These are the **tutorial**
layer: flags, examples, configuration, recipes, and troubleshooting. For the
authoritative one-line reference (every command + flag), see
[DOC/POS.md](POS.md).

## Quick start — pick your category

| Category | What you can do | Guide |
|----------|-----------------|-------|
| `pos network` | IP info, hotspot, scan, port check | [network](howto/network.md) |
| `pos docker` | Compose services, container dashboards, disposable VMs | [docker](howto/docker.md) |
| `pos media` | Download audio/video via yt-dlp | [media](howto/media.md) |
| `pos system` | Backups, firewall, health dashboard | [system](howto/system.md) |
| `pos ssh` | Load keys into the agent | [ssh](howto/ssh.md) |
| `pos usb` | Share USB devices over the network | [usb](howto/usb.md) |
| `pos communication` | Send Telegram messages/files/alerts | [communication](howto/communication.md) |
| `pos entertainment` | Scheduled auto-messages from public APIs | [entertainment](howto/entertainment.md) |

Every tool is `bin/pos-<category>-<command>`; run `pos <category> --help` to
list a category, and any tool's `--help`/`--help`-style usage for full flags.

## Cross-cutting concepts (read once)

These apply to several categories at once.

### Config files — `~/.config/linux_post_install/`

Runtime tool config lives here as `<tool>.env` files (`chmod 600`). Precedence
is always **flags > environment > config file**. `postinstall.sh` installs the
templates (without overwriting an existing file):

| File | Used by | Keys |
|------|---------|------|
| `telegram.env` | `pos communication telegram`, everything that alerts | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |
| `notify.env` | `lib/notify.sh` (all alerting) | `NOTIFY_PLATFORM` (e.g. `telegram,matrix`) |
| `system.env` | `pos system health`, `pos system backup` | `BACKUP_SERVICE_ROOTS`, `HEALTH_BACKUP_MAX_AGE_DAYS` |
| `compose.env` | `pos docker compose` | `TS_AUTHKEY`, `TZ`, `DNS_SERVER`, `SERVICES_BASE` |
| `entertainment.env` | `pos entertainment *` | plugin keys (`WEATHER_LAT`…), `ENABLED` |

```bash
pos communication telegram config set TELEGRAM_BOT_TOKEN=123:ABC
pos communication telegram config set TELEGRAM_CHAT_ID=98765
pos entertainment config set WEATHER_LAT=36.51 WEATHER_LON=40.75
```

### The notify system — `lib/notify.sh`

Any tool that "announces" something calls `notify_send`, which delivers to every
platform in `NOTIFY_PLATFORM` (default `telegram`). It is **silent-fail**: if no
platform is configured it warns and never breaks the calling tool.

```bash
# ~/.config/linux_post_install/notify.env
NOTIFY_PLATFORM=telegram        # comma-separated to send to all
```

Adding a platform later (e.g. Matrix/Synapse) = create `bin/pos-communication-<p>`
implementing `send <value> [--markdown]` and list it. See
[DOC/DEV.md → Alerting](DEV.md) for the contract.

### Scheduling

- **Daily health digest** (`pos system health --send` at 08:00) — `systemd/pos-health.{service,timer}`,
  enabled by postinstall once `telegram.env` exists. See [system](howto/system.md).
- **Entertainment auto-triggers** — per-plugin `pos entertainment enable <plugin> <interval>`,
  uses systemd user timers (or cron fallback). See [entertainment](howto/entertainment.md).

### Gotcha: run from anywhere

`install.sh` copies `bin/pos*` + `lib/*` to `/usr/local/bin`, so `pos` works
after the repo is deleted. After pulling new changes, re-run `./install.sh` (or
just copy the changed `bin/`/`lib/` files) to refresh the installed copies.

## How the guides relate to `DOC/POS.md`

- **`DOC/POS.md`** = reference. One table row per command, full flag lists,
  compose/ScaleTail config strategy. Use it when you need the exact flag.
- **This guide set** = how-to. Examples, recipes, config walk-throughs, and
  troubleshooting, linking back to POS.md rather than duplicating it.
