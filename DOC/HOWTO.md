# `pos` HOW-TO Guides

Hands-on, copy-paste guides for every `pos` category. These are the **tutorial**
layer: flags, examples, configuration, recipes, and troubleshooting. For the
authoritative one-line reference (every command + flag), see
[DOC/POS.md](POS.md).

## Quick start — pick your category

| Category | What you can do | Guide |
|----------|-----------------|-------|
| `pos ai` | Chat with Google Gemini from CLI or Telegram | [ai](howto/ai.md) |
| `pos network` | IP info, hotspot, scan, port check, aria2 download daemon | [network](howto/network.md) |
| `pos docker` | Compose services, container dashboards, disposable VMs | [docker](howto/docker.md) |
| `pos media` | Download audio/video via yt-dlp | [media](howto/media.md) |
| `pos system` | Backups, firewall, health dashboard | [system](howto/system.md) |
| `pos system schedule` | Scheduled jobs: run a command on a timer, notify on threshold/change/error or silently | [schedule](howto/schedule.md) |
| `pos ssh` | Load keys into the agent | [ssh](howto/ssh.md) |
| `pos share` | Share USB devices & filesystems over the network (USB, NFS, SMB) | [share](howto/share.md) |
| `pos communication` | Send Telegram/Matrix messages & alerts, /command listeners, Android mirroring (scrcpy) | [communication](howto/communication.md) |
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
| `telegram.env` | `pos communication telegram sender` / `listener`, everything that alerts | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |
| `matrix.env` | `pos communication matrix sender` / `listener` | `MATRIX_HOMESERVER`, `MATRIX_ACCESS_TOKEN`, `MATRIX_USER_ID`, `MATRIX_ROOM_ID` |
| `scrcpy.env` | `pos communication scrcpy` | `SCRCPY_SERIAL`, `SCRCPY_MAX_SIZE`, `SCRCPY_MAX_FPS`, `SCRCPY_BIT_RATE`, `SCRCPY_FULLSCREEN`, `SCRCPY_NEW_DISPLAY`, `SCRCPY_RECORD_DIR`, `SCRCPY_PUSH_TARGET`, `SCRCPY_EXTRA_FLAGS` |
| `notify.env` | `lib/notify.sh` (all alerting) | `NOTIFY_PLATFORM` (e.g. `telegram,matrix`) |
| `system.env` | `pos system health`, `pos system backup` | `BACKUP_SERVICE_ROOTS`, `HEALTH_BACKUP_MAX_AGE_DAYS` |
| `compose.env` | `pos docker compose` | `TS_AUTHKEY`, `TZ`, `DNS_SERVER`, `SERVICES_BASE` |
| `entertainment.env` | `pos entertainment *` | plugin keys (`WEATHER_LAT`…), `ENABLED` |
| `ai.env` | `pos ai gemini` | `AI_GEMINI_API_KEY`, `AI_GEMINI_MODEL` |
| `schedule.d/` | `pos system schedule` | one `<name>.env` per job: `INTERVAL`, `NOTIFY`, `MSG`, `RULE`, `COMMAND` |

```bash
pos config telegram                     # set TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID
pos config matrix                       # set MATRIX_HOMESERVER / MATRIX_ROOM_ID, then:
pos communication matrix sender login --user @you:example.org   # fetch an access token
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

Ship with `telegram` and `matrix` — add both to `NOTIFY_PLATFORM` to fan out
alerts (Matrix needs `pos config matrix` + a `login`-fetched token first).
Adding another platform = create `bin/pos-communication-<p>` implementing
`send <value> [--markdown]` and list it. See
[DOC/DEV.md → Alerting](DEV.md) for the contract.

### Scheduling

- **Daily health digest** — add a `daily` schedule job `pos system health --send --markdown`
  via `pos system schedule config` (the old `pos-health.{service,timer}` units are gone). See [system](howto/system.md).
- **Entertainment auto-triggers** — per-plugin `pos entertainment enable <plugin> <interval>`,
  uses systemd user timers (or cron fallback). See [entertainment](howto/entertainment.md).
- **`pos system schedule` jobs** — run any command on a per-job timer and notify
  on threshold/change/error/always or silently. See [schedule](howto/schedule.md).

### Gotcha: run from anywhere

`install.sh` copies `bin/pos*` + `lib/*` to `/usr/local/bin`, so `pos` works
after the repo is deleted. After pulling new changes, re-run `./install.sh` (or
just copy the changed `bin/`/`lib/` files) to refresh the installed copies.

## How the guides relate to `DOC/POS.md`

- **`DOC/POS.md`** = reference. One table row per command, full flag lists,
  compose/ScaleTail config strategy. Use it when you need the exact flag.
- **This guide set** = how-to. Examples, recipes, config walk-throughs, and
  troubleshooting, linking back to POS.md rather than duplicating it.
