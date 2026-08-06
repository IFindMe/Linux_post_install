# `pos` CLI Reference

`pos` is the unified command-line interface installed to `/usr/local/bin/`. Every tool is a small script in `bin/` with a `pos-<category>-<command>` name. This document explains the dispatcher and every command.

- [The dispatcher — `bin/pos`](#the-dispatcher--binpos)
- [Logging behavior](#logging-behavior)
- [Commands](#commands)
  - [network](#network)
  - [docker](#docker)
  - [media](#media)
  - [system](#system)
  - [ssh](#ssh)
  - [usb](#usb)
  - [communication](#communication)
  - [entertainment](#entertainment)
  - [flags](#flags)
- [Legacy wrappers](#legacy-wrappers)

---

## The dispatcher — `bin/pos`

**Purpose:** turn `pos <category> <command> [args]` into a call to the matching `pos-*` script.

### How it works

`pos` scans its own directory for executable `pos-*` files and tries **variable-length argument matching**, longest first. For `pos docker compose up jellyfin`:

```
tries pos-docker-compose-up-jellyfin   (not found)
tries pos-docker-compose-up            (not found)
tries pos-docker-compose               (found) → runs with args "up jellyfin"
```

`pos help <full command>` runs that tool's `--help` (e.g. `pos help communication telegram`, `pos help docker compose` — the words are joined with dashes). `pos <category>` and `pos <category> --help` list that category's subcommands (derived from `bin/pos-<category>-*` filenames, no script execution). Running `pos` with no args prints the built-in usage text (which doubles as the category cheat-sheet).

---

## Logging behavior

Every non-interactive `pos` invocation logs to `~/.local/share/linux_post_install/logs/`:

- Per-command files: `YYYYMMDD_HHMMSS_pos_<args>.log` (full stdout + stderr).
- `pos.log`: one line per invocation — command, log file, exit code.
- **Interactive** commands (`pos system firewall`, `pos media mp4`, `pos system backup`) only log the invocation, not their output.

---

## Commands

### network

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos network ip` | `bin/pos-network-ip` | Show interfaces, default route, public IP + location | None. Public IP via `https://ifconfig.me`; location via `ip-api.com` (5s timeouts) |
| `pos network checkport <ip:port>` | `bin/pos-network-checkport` | Check if a TCP port is open | None. Uses `/dev/tcp` with a 2s timeout; exit 0/1 via OPEN/CLOSED |
| `pos network scan <cidr> [--full] [--retries N]` | `bin/pos-network-scan` | Two-phase nmap scan | See below |
| `pos network hotspot [cmd]` | `bin/pos-network-hotspot` | Wi-Fi hotspot via `create_ap` (CLI) or `wihotspot-gui` (GUI) | Uses the precompiled binaries from `x64_bin/`; see below |

**`pos network scan` in detail:**

- Phase 1 — fast host discovery (`nmap -sn -T5`), prints the live host list.
- Phase 2 (only with `--full`) — service/version scan (`-sV -sC`), plus OS detection and NSE scripts if run with privileges; shows ports, OS, SSH host keys, HTTP titles, NetBIOS/SMB info.
- Accepts a bare IP (treated as `/32`) or a CIDR.
- Auto-raises to `sudo nmap` when possible (root, passwordless sudo, or an interactive terminal with `--full`).
- `--retries N` tunes discovery retries (default 1).

**`pos network hotspot` in detail:**

Backed by the precompiled binaries shipped in `x64_bin/` (see [SCRIPTS.md → x64_bin/](SCRIPTS.md#x64_bin--precompiled-binaries)). Needs root for the CLI commands (uses `sudo`):

| Command | Behavior |
|---------|----------|
| `pos network hotspot` | Launches the `wihotspot-gui` (GTK3 GUI) |
| `pos network hotspot start <wifi-iface> [<internet-iface>] <ssid> [<passphrase>]` | Asks whether to run in the background; `y` starts `create_ap --daemon` (logs to `/var/log/linux_post_install_hotspot.log`), `n` runs in the foreground (blocks until Ctrl+C) |
| `pos network hotspot start --foreground <wifi-iface> [<internet-iface>] <ssid> [<passphrase>]` | Skips the prompt, runs in the foreground |
| `pos network hotspot stop [<id>]` | Stops the running access point via `create_ap --stop`; `<id>` is an interface name or PID, auto-detected if omitted |
| `pos network hotspot status` | Runs `create_ap --list-running` |

### docker

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos docker ps` | `bin/pos-docker-ps` | Enhanced container list: name, image, health, uptime, IPs, ports, ID, plus a healthy/unhealthy summary | None. Requires Docker + Python 3 |
| `pos docker health` | `bin/pos-docker-health` | One-glance health dashboard; **exits 1** if any container is unhealthy | None. Checks all containers including stopped ones |
| `pos docker compose …` | `bin/pos-docker-compose` | ScaleTail service manager | See [Docker Compose / ScaleTail](#docker-compose--scaletail) below |

#### Docker Compose / ScaleTail

**`pos docker compose ls`** — list available ScaleTail service templates.

**`pos docker compose installed`** — list deployed services under `$SERVICES_BASE`.

**`pos docker compose up <service>`** — deploy a service:

1. If not yet deployed, creates `$SERVICES_BASE/<service>/` with `config/` and `data/`, copies the template's `compose.yaml`.
2. If no `.env` exists, copies the template's `.env` (or writes a default) and fills in your global config values (`TS_AUTHKEY`, `TZ`, `DNS_SERVER`).
3. If `TS_AUTHKEY` is still empty, prompts for it.
4. Offers to edit `.env` before starting (default **yes** on first deploy).
5. Runs `docker compose up -d`.

**`pos docker compose down/restart/logs <service>`** — stop, restart, or tail logs of a deployment.

**`pos docker compose update`** — `git pull` the ScaleTail templates, then refresh the `compose.yaml` of every deployed service. **Per-service `.env` files are never touched.**

**`pos docker compose config [show]`** — show the global config file and `SERVICES_BASE`.

**`pos docker compose config set KEY=VALUE`** — set/update a global default in `~/.config/linux_post_install/compose.env`.

**`pos docker compose config edit`** — open the global config in `$EDITOR` (creates a default file first).

Configuration (three layers, most specific wins):

| Layer | File | Notes |
|-------|------|-------|
| Template defaults | `/usr/local/share/linux_post_install/scale-tail/services/<name>/.env` | Read-only |
| Global config | `~/.config/linux_post_install/compose.env` | Edited via `config set` / `config edit` |
| Per-service | `$SERVICES_BASE/<service>/.env` | Created on first `up`, **never overwritten** |

Global config keys:

| Key | Required | Default | Purpose |
|-----|----------|---------|---------|
| `TS_AUTHKEY` | yes | — | Tailscale auth key for the sidecar |
| `TZ` | no | `Europe/Amsterdam` | Service timezone |
| `DNS_SERVER` | no | `9.9.9.9` | DNS server |
| `SERVICES_BASE` | no | `/srv` | Deployment root |

#### Docker vbox

**File:** `bin/pos-docker-vbox`
**Purpose:** manage disposable Docker containers as lightweight "VMs". Each container gets a bind-mounted host directory so files persist after the container is removed. Containers carry the label `linux_post_install.vbox=true`.

| Command | Behavior |
|---------|----------|
| `pos docker vbox create <name> [image] [--dir <path>]` | Creates a container from `ubuntu:22.04` (or the given image), bind-mounting `~/<name>` (or `--dir`, or `.` for cwd) as the working directory; prompts to enter immediately |
| `pos docker vbox enter <name>` | Shell into the container (auto-starts it if stopped); detects the working dir from the container mounts |
| `pos docker vbox start/stop/rm <name>` | Start, stop, or force-remove the container |
| `pos docker vbox ls` | List vbox containers only (label filter) |

The standalone `vbox` command still works and forwards to `pos docker vbox` (see [Legacy wrappers](#legacy-wrappers)).

### media

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos media mp3 <url>` | `bin/pos-media-mp3` | Download audio as MP3 via yt-dlp, with thumbnail + metadata | Output to `~/Music/%(title)s.%(ext)s`, `--audio-quality 0` |
| `pos media mp4 <url>` | `bin/pos-media-mp4` | Download video via yt-dlp with **interactive format selection** | Lists formats (`yt-dlp -F`), asks for a format ID, saves to `~/Videos/` |

### system

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `sudo pos system firewall` | `bin/pos-system-firewall` | Interactive UFW ("UFW POWER") menu: add/delete rules, status, enable/disable/reset, default policies | Must run as root. Every command is previewed and confirmed before execution; supports `--dry-run`; keeps a history of executed commands |
| `pos system backup <folder-path>` | `bin/pos-system-backup` | Create a gpg-encrypted (AES-256) `tar.gz` snapshot of a folder and verify it | Prompts twice for a password (never stored). Uses `sudo tar`; needs `gnupg` (in `preinstall.sh` PACKAGES). Artifact `<name>_<date>.tar.gz.gpg` in the current directory, `chmod 600` |
| `pos system backup --service` | `bin/pos-system-backup` | Lists folders under `/srv` and `~/srv`, lets you pick one, then runs the same backup | Roots via `BACKUP_SERVICE_ROOTS` (space-separated, default `/srv $HOME/srv`) |

### ssh

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos ssh load-keys` | `bin/pos-ssh-load-keys` | Load all `~/.ssh/id_*` private keys into the ssh-agent | Uses `SSH_AUTH_SOCK` (default `/run/ssh-agent/socket`, provided by `ssh-agent.service`); skips `.pub`, `known_hosts`, `authorized_keys`, `config`; validates keys before adding |

### usb

**File:** `bin/pos-usb-server`
**Purpose:** control the USB Redirector server (`usbsrv`) — share local USB devices over the network and manage connected clients. Requires `usbsrv` (manual install from incentivespro.com — not in `PACKAGES`).

| Command | Behavior |
|---------|----------|
| `pos usb server --ls` | List host USB devices and connected clients |
| `pos usb server --ls-shared` | List shared or in-use devices only |
| `pos usb server --share [dev-id] [client-id]` | Share a device and connect it to a client; interactive picker when IDs are omitted (`-share` + `-connect-to CLIENT-DEV`) |
| `pos usb server --unshare [dev-id]` | Stop sharing a device |
| `pos usb server --auto-share on\|off` | Toggle automatic sharing of new devices |
| `pos usb server --callback [addr:port]` | Create a callback connection to a client |
| `pos usb server --close-callback [target\|all]` | Close a client callback |
| `pos usb server --auto-connect on\|off [client]` | Toggle remote auto-connect for a client |
| `pos usb server --disconnect [dev-id\|all]` | Disconnect a device from its clients |
| `pos usb server --nickname [dev-id] [nick]` | Set a device nickname (empty nick removes it) |
| `pos usb server --timeout [dev-id] [sec]` | Set device inactivity timeout (0 disables) |
| `pos usb server --port [num]` | Set the TCP port (restart server to apply) |
| `pos usb server --info` / `--version` | Show server info / version |

Subcommands that need input prompt interactively when args are omitted.

### communication

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos communication telegram send "text"` | `bin/pos-communication-telegram` | Send a message, link, or media file (auto-detects the type) to a Telegram chat via the Bot API | Token + chat ID from `~/.config/linux_post_install/telegram.env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, chmod 600). Precedence: `--token`/`--chat-id` flags > env > config file |

`pos communication telegram` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication telegram send "text"` | POSTs `sendMessage` to the Bot API (60s timeout); prints `[+] message sent to chat <id>` or fails with a nonzero exit |
| `pos communication telegram send <value>` | **Auto-detects the type** when `--type` is omitted: existing file → `file` (except `.webp` → sticker, `.gif` → animation, images → photo, video/audio/voice extensions → their type), value starting with `http://`/`https://`/`www.` → `link`, otherwise `message` |
| `pos communication telegram send <path> --type file [--caption "…"]` | Uploads a file as a `sendDocument` via multipart (`document=@path`); `--caption` adds a caption. Path must exist and be readable |
| `pos communication telegram send <path> [--caption "…"]` | Media uploads via their Bot API endpoint: `--type photo` → `sendPhoto`, `video` → `sendVideo`, `audio` → `sendAudio`, `voice` → `sendVoice`, `animation` → `sendAnimation`, `sticker` (`.webp`) → `sendSticker` (captions not supported for stickers) |
| `pos communication telegram send "url" --type link [--no-preview]` | Sends a link as a message (URLs auto-linkify); `--no-preview` adds `disable_web_page_preview=true` |
| `pos communication telegram send "text" --parse-mode <mode>` | Send with Telegram formatting; `<mode>` is `plain` (default), `markdown`, or `html` (passed as `parse_mode` to the API — also applies to captions). Markdown/HTML use raw Telegram syntax — unescaped characters may be rejected by the API (400) |
| `pos communication telegram send … --token <t> --chat-id <id>` | One-shot override of token/chat ID |
| `pos communication telegram --send "text"` | Legacy alias for `send "text"` (kept for the entertainment runner) |
| `pos communication telegram test` | Sends a canned test message using the current config |
| `pos communication telegram config` | Shows current config (bot token masked) |
| `pos communication telegram config set TELEGRAM_BOT_TOKEN=...` | Saves a bot token (600 perms) |
| `pos communication telegram config set TELEGRAM_CHAT_ID=...` | Saves the target chat ID |

`send` option validation: `--caption` is only valid with media types (file/photo/video/audio/voice/animation), `--no-preview` only with `--type message`/`link`, and `--type` only accepts `message|file|link|sticker|photo|video|audio|voice|animation`. An explicit `--type` always overrides auto-detection.

The bot token is a secret — it is stored only in `~/.config/linux_post_install/telegram.env` and never in the repo. Requires network access to `api.telegram.org`.

### entertainment

**File:** `bin/pos-entertainment-send`
**Purpose:** run a public-API plugin and send its output to Telegram by default. Plugins are standalone scripts in `entertainment/` that fetch a public API and **print the message to stdout** — that stdout is what gets sent.

| Command | Behavior |
|---------|----------|
| `pos entertainment send` | List available plugins + usage |
| `pos entertainment send <plugin> [--print] [--markdown] [args…]` | Run the plugin, send its output to Telegram (silent) |
| `pos entertainment send <plugin> --print` | Print the output locally; do not send |
| `pos entertainment send <plugin> --markdown` | Send with `--parse-mode markdown` (via `pos communication telegram`) |
| `pos entertainment config` | Show the config file (`~/.config/linux_post_install/entertainment.env`) |
| `pos entertainment config set KEY=VALUE…` | Set keys (any UPPER_SNAKE key; warns if no installed plugin uses it) and re-sync the schedule |
| `pos entertainment enable <plugin> [interval]` | Add plugin to `ENABLED` + schedule it (systemd user timer or cron, auto-detected) |
| `pos entertainment disable <plugin>` | Remove plugin from `ENABLED` + remove its scheduled job |
| `pos entertainment status` | Enabled plugins + scheduler + schedule state |

**Plugin lookup order:** `$ENTERTAINMENT_DIR` → repo `entertainment/` → `/usr/local/bin/` (installed by `install.sh` Phase 2, beside the runner). A plugin name matches the file name with or without the `.sh` suffix.

Plugins:

| Plugin | Source API | Config |
|--------|-----------|--------|
| `weather` | Open-Meteo (no API key) | `~/.config/linux_post_install/entertainment.env`: `WEATHER_LAT`, `WEATHER_LON` (required), `WEATHER_CITY` (optional label) |
| `joke` | icanhazdadjoke.com (no API key) | None |
| `gold` | goldprice.dev (no API key, anonymous free tier) | None |

**Config auto-install:** `postinstall.sh` copies the repo's `config/entertainment.env` (a commented template showing each key's syntax) to `~/.config/linux_post_install/entertainment.env` on install — but only if you haven't already created your own (no clobber), and prints the template so you can fill in your location. Fill in `WEATHER_LAT`/`WEATHER_LON` (and optionally `WEATHER_CITY`) to enable the weather plugin.

**Adding a plugin:** drop an executable script in `entertainment/` (e.g. `myfeed.sh`) with a `# POS_PLUGIN: <name>` marker on line 3 — the runner lists and validates plugins by this marker, so non-plugin `.sh` files in the shared `/usr/local/bin` are ignored. The plugin must be non-interactive and print the message to stdout; errors go to stderr (exit nonzero). If it needs coordinates/tokens, read them from `~/.config/linux_post_install/entertainment.env` (chmod 600, env precedence). No registration needed. Dependencies beyond `curl`/`jq` (both in `preinstall.sh` PACKAGES) should be guarded with `command -v … || exit 1`.

**Declaring config keys (pattern):** document every key the plugin reads with one `# POS_KEYS:` line right after `# POS_PLUGIN:` — `KEY`, a description, and `(required)`/`(optional)`:

```
# POS_PLUGIN: myfeed
# POS_KEYS: MYFEED_URL <feed url> (required)
# POS_KEYS: MYFEED_TAG <filter tag> (optional)
```

The plugin itself still reads the keys as plain env vars (`${MYFEED_URL:-}`). The declaration is what `pos entertainment config` uses to print its Keys section and to decide whether `config set` warns about an undeclared key — add the line whenever a plugin gets a new config key.

**Automation (auto-trigger):** enable plugins on a schedule via the `ENABLED` key in the config — a comma-separated list of `plugin, interval` pairs:

```
ENABLED="weather, 5m gold, 1h joke, daily"
```

`pos entertainment enable <plugin> [interval]` appends/updates one entry and re-syncs; `pos entertainment disable <plugin>` removes it; `pos entertainment config set ENABLED="…"` replaces the whole list. The scheduler backend is auto-detected on each sync:

- **systemd** (when a user systemd manager is reachable): one **user timer** per enabled plugin (`~/.config/systemd/user/pos-entertainment-<plugin>.{service,timer}`), running `pos entertainment send <plugin>` as your user on that schedule (`OnCalendar` + `Persistent=true`). `pos entertainment enable` also tries `sudo loginctl enable-linger $USER` once so timers fire without login.
- **cron** (fallback when no systemd user manager, e.g. this dev box): a managed block in your user crontab (`# POS-ENTERTAINMENT-BEGIN`…`END`), one line per plugin. Cron runs as your user and fires without login.

Either way the job runs as you, so it reads your `$HOME` configs (weather location, Telegram token) natively — no `Environment=HOME=` hacks.

Intervals: `5m 10m 15m 30m 45m hourly 2h 6h 12h daily weekly`, or a raw `OnCalendar=…` spec (systemd mode only; cron mode uses the named intervals). Default when omitted: `daily`.

`pos entertainment status` shows the enabled plugins, the detected scheduler, and each plugin's interval + next/next-ish fire time (`systemctl --user list-timers` or the crontab block).

Notes:
- The runner is headless/timer-friendly — no TTY prompts, exit 0 on success / 1 on failure.
- Scheduling is per-user for the user who runs `enable`; if you manage a different machine's user (e.g. via `runuser`/`sudo -u`), run the `enable`/`disable` commands as that user.

### flags

Feature-flag management CLIs (see [SCRIPTS.md → lib/flags.sh](SCRIPTS.md#libflagssh--feature-flags)):

| Command | Purpose |
|---------|---------|
| `flag-reader` | List all flags + status (`set: <name>` / `unset: <name>`) |
| `flag-reader <name>` | Check one flag; exit 0 if set, 1 if not |
| `flag-reader --raw <name>` | Print only the stored value (script-friendly) |
| `flag-set <name> [value]` | Set a flag, optionally with a value (requires sudo) |
| `flag-clear <name>` | Unset a flag (requires sudo) |

---

## Legacy wrappers

Thin 2-line scripts that `exec pos … "$@"`. All of them still work:

| Wrapper | Forwards to |
|---------|-------------|
| `wr-ip` | `pos network ip` |
| `wr-checkport` | `pos network checkport` |
| `wr-scan-ping` | `pos network scan` |
| `wr-docker` | `pos docker` |
| `wr-compose` | `pos docker compose` |
| `wr-ufw` | `pos system firewall` |
| `mp3` | `pos media mp3` |
| `mp4` | `pos media mp4` |
| `vbox` | `pos docker vbox` |
| `ssh-load-all` | `pos ssh load-keys` |
