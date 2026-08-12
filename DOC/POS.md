# `pos` CLI Reference

`pos` is the unified command-line interface installed to `/usr/local/bin/`. Every tool is a small script in `bin/` with a `pos-<category>-<command>` name. This document explains the dispatcher and every command.

- [The dispatcher — `bin/pos`](#the-dispatcher--binpos)
- [Logging behavior](#logging-behavior)
- [Commands](#commands)
  - [ai](#ai)
  - [network](#network)
  - [docker](#docker)
  - [media](#media)
  - [system](#system)
  - [ssh](#ssh)
  - [share](#share)
  - [communication](#communication)
  - [entertainment](#entertainment)
  - [flags](#flags)
  - [config](#config)
  - [tree](#tree)
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

Category-less tools (`config`, `tree`) live outside any category and are documented in their own `###` sections below.

### ai

**File:** `bin/pos-ai-gemini`
**Purpose:** chat with Google Gemini via the REST API (`generativelanguage.googleapis.com`). One tool, three subcommands: `ask` (one-shot, scriptable), `chat` (interactive multi-turn REPL), and `models` (list `generateContent`-capable ids).

| Command | Behavior |
|---------|----------|
| `pos ai gemini ask "<prompt>"` | One-shot; POSTs `generateContent` and prints **only** the answer text to stdout (pipe/script/Telegram-friendly). The prompt may also be piped in via stdin when no argument is given |
| `pos ai gemini chat` | Interactive REPL with multi-turn history (the `contents[]` array is appended per turn); `q`/`quit`/`exit` or Ctrl+C quit, `/reset` clears the history, empty input re-prompts |
| `pos ai gemini models` | Lists models that support `generateContent` and flags the configured default |
| `pos ai gemini --model <id> …` | Overrides the model for one invocation |

`pos ai gemini` with no subcommand prints usage (never blocks on stdin). `ask`/`chat` time out after 60s per request; on a non-2xx response the API's `error.message` is shown and the tool exits non-zero.

**Configuration** (`~/.config/linux_post_install/ai.env`, edit with `pos config ai`):

| Key | Required | Default | Purpose |
|-----|----------|---------|---------|
| `AI_GEMINI_API_KEY` | yes | — | API key from aistudio.google.com (secret — masked in `pos config ai`) |
| `AI_GEMINI_MODEL` | no | `gemini-2.5-flash` | Model id used by `ask`/`chat`/`models` |

Precedence: `--model` flag > `AI_GEMINI_MODEL` env > config file > `gemini-2.5-flash`. `postinstall.sh` copies the repo's `config/ai.env` template to `~/.config/linux_post_install/ai.env` on install (no clobber). Dependencies: `curl` + `jq` (both in `preinstall.sh` PACKAGES).

**Messaging bridges:** the Telegram and Matrix listeners forward non-command messages starting with `ai ` (case-insensitive) to `pos ai gemini ask` and reply with the model's answer — see [communication → listener](#communication). The Telegram bridge uses one session per chat (`telegram-<chat id>`), the Matrix bridge one per room (`matrix-<room>`).

### network

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos network ip` | `bin/pos-network-ip` | Show interfaces, default route, public IP + location | None. Public IP via `https://ifconfig.me`; location via `ip-api.com` (5s timeouts) |
| `pos network checkport <ip:port>` | `bin/pos-network-checkport` | Check if a TCP port is open | None. Uses `/dev/tcp` with a 2s timeout; exit 0/1 via OPEN/CLOSED |
| `pos network scan <cidr> [--full] [--retries N]` | `bin/pos-network-scan` | Two-phase nmap scan | See below |
| `pos network hotspot [cmd]` | `bin/pos-network-hotspot` | Wi-Fi hotspot via `create_ap` (CLI) or `wihotspot-gui` (GUI) | Uses the precompiled binaries from `x64_bin/`; see below |
| `pos network download <cmd>` | `bin/pos-network-download` | aria2 RPC daemon + queue control (add/torrent/metalink, watch, limits) | `aria2c`/`jq`/`curl`; daemon = systemd user service; secret in `~/.config/linux_post_install/download.env`; see below |

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

**`pos network download` in detail:**

Runs a persistent `aria2c` JSON-RPC daemon (`localhost:6800`) as a **systemd user service** (`pos-aria2.service`, enabled with `systemctl --user enable --now`; prints a linger warning on headless boxes). `start` installs the unit and generates a random `RPC_SECRET` into `~/.config/linux_post_install/download.env` (chmod 600); the secret is also respected as the `RPC_SECRET` env var. Unit flags: `--continue=true --max-connection-per-server=16 --split=16 --seed-time=0 --dir=$HOME/Downloads`.

| Command | Behavior |
|---------|----------|
| `pos network download start` / `stop` | Install+enable the systemd user service / stop and remove it |
| `pos network download status` | Daemon health + global transfer stats (`getGlobalStat`) |
| `pos network download add <url>...` | Enqueue HTTP/FTP downloads (auto-starts the daemon); options `--dir`, `--out`, `--split`, `--tmux` |
| `pos network download torrent <file|magnet>...` | Enqueue `.torrent` files (base64 via `addTorrent`) or magnet links; `--seed` keeps seeding (default `--seed-time=0`), `--dir`, `--tmux` |
| `pos network download metalink <file|url>...` | Enqueue `.metalink` files or URLs; `--tmux` |
| `pos network download list` | Table of active / waiting / finished downloads (GID, status, %, dl/up speeds, name) |
| `pos network download info <gid>` | Full `tellStatus` dump (status, progress, speeds, ETA, error) |
| `pos network download files <gid>` / `peers <gid>` | Files of a download / peers of a torrent |
| `pos network download pause\|resume [gid\|all]` | Pause/resume one or all (default `all`) |
| `pos network download remove [gid\|all]` | Remove one or all; `--force` = `forceRemove` (kills immediately) |
| `pos network download purge` | Clear finished/error history |
| `pos network download move <gid> <pos>` | Reorder the waiting queue (`changePosition`) |
| `pos network download limit [gid] <speed>` | Speed limit, global or per-download (`--upload` = upload speed; `0` = unlimited); accepts `2M`/`512K` |
| `pos network download set <k=v>...` | Set global aria2 options (`--gid <gid>` = per-download) |
| `pos network download watch [gid]` | Live table, 2 s refresh; with a GID it exits when that download completes |

**`--tmux`:** after enqueueing, `add`/`torrent`/`metalink` open a detached tmux session `dl-<name>` running `watch <gid>` (name from `--out` or the URL basename, sanitized and truncated to 40 chars; `-2` suffix on collision). The session closes itself when the download finishes — attach with `tmux attach -t dl-<name>`.

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
| `sudo pos system firewall` | `bin/pos-system-firewall` | Interactive UFW ("UFW POWER") menu: add/delete rules, status, enable/disable/reset, default policies | Must run as root. Every command is previewed and confirmed before execution; supports `--dry-run`; keeps a history of executed commands. Executed mutating changes are announced via `lib/notify.sh` |
| `pos system backup <folder-path>` | `bin/pos-system-backup` | Create a gpg-encrypted (AES-256) `tar.gz` snapshot of a folder and verify it | Prompts twice for a password (never stored). Uses `sudo tar`; needs `gnupg` (in `preinstall.sh` PACKAGES). Artifact `<name>_<date>.tar.gz.gpg` in the current directory, `chmod 600`. Success/failure are announced via `lib/notify.sh` |
| `pos system backup --service` | `bin/pos-system-backup` | Lists folders under `/srv` and `~/srv`, lets you pick one, then runs the same backup | Roots via `BACKUP_SERVICE_ROOTS` (space-separated, default `/srv $HOME/srv`) or `~/.config/linux_post_install/system.env` |
| `pos system health [--send] [--markdown]` | `bin/pos-system-health` | Host health dashboard: disk per mount, RAM/swap, failed systemd units, backup age, fail2ban, docker containers. Exits 1 if any check FAILs | `--send`/`--markdown` are notification-only: they send the summary via `lib/notify.sh` to every platform in `NOTIFY_PLATFORM` and do NOT print the dashboard (so wrappers like the Telegram listener don't echo it back — pair with the listener's `@quiet` marker). `HEALTH_BACKUP_MAX_AGE_DAYS` (default 2) and `BACKUP_SERVICE_ROOTS` come from `~/.config/linux_post_install/system.env`; `--help` shows the effective values. Platform list from `~/.config/linux_post_install/notify.env` |
| `pos system event-trigger <cmd>` | `bin/pos-system-event-trigger` | State-based rule monitors: `run`, `config`, `list`, `enable [interval]`, `disable`, `status`. Each line of `~/.config/linux_post_install/event.env` is an independent rule `["msg" if ] <check-command> <op> <threshold>` (op `> < >= <= == !=`, unit suffix ok: `60c`, `80%`); the check command's first numeric output is compared float-safe. Alerts once on false→true, plus one recovery message on true→false — no repeats while the condition holds, via `lib/notify.sh` | `config` is an interactive editor that validates rules by test-running the check; `run` is what the systemd user timer (`pos-event-trigger.timer` + oneshot `.service`, interval set at `enable`) executes; supports `--dry-run`; rules are arbitrary shell commands (chmod 600, same trust model as the Telegram map); template `config/event.env` auto-installed no-clobber by postinstall |

`systemd/pos-health.service` + `systemd/pos-health.timer` run `pos system health --send --markdown` daily at 08:00 as the installing user. `postinstall.sh` enables the timer automatically once `~/.config/linux_post_install/telegram.env` exists — re-run postinstall after configuring a notify platform to pick it up. The service also loads `system.env` + `notify.env` via `EnvironmentFile=`.

### ssh

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos ssh load-keys` | `bin/pos-ssh-load-keys` | Load all `~/.ssh/id_*` private keys into the ssh-agent | Uses `SSH_AUTH_SOCK` (default `/run/ssh-agent/socket`, provided by `ssh-agent.service`); skips `.pub`, `known_hosts`, `authorized_keys`, `config`; validates keys before adding |

### share

Share files and devices over the network (USB over network, NFS, SMB/Samba).

**File:** `bin/pos-share-usb-server`
**Purpose:** control the USB Redirector server (`usbsrv`) — share local USB devices over the network and manage connected clients. Requires `usbsrv` (manual install from incentivespro.com — not in `PACKAGES`).

| Command | Behavior |
|---------|----------|
| `pos share usb server --ls` | List host USB devices and connected clients |
| `pos share usb server --ls-shared` | List shared or in-use devices only |
| `pos share usb server --share [dev-id] [client-id]` | Share a device and connect it to a client; interactive picker when IDs are omitted (`-share` + `-connect-to CLIENT-DEV`) |
| `pos share usb server --unshare [dev-id]` | Stop sharing a device |
| `pos share usb server --auto-share on\|off` | Toggle automatic sharing of new devices |
| `pos share usb server --callback [addr:port]` | Create a callback connection to a client |
| `pos share usb server --close-callback [target\|all]` | Close a client callback |
| `pos share usb server --auto-connect on\|off [client]` | Toggle remote auto-connect for a client |
| `pos share usb server --disconnect [dev-id\|all]` | Disconnect a device from its clients |
| `pos share usb server --nickname [dev-id] [nick]` | Set a device nickname (empty nick removes it) |
| `pos share usb server --timeout [dev-id] [sec]` | Set device inactivity timeout (0 disables) |
| `pos share usb server --port [num]` | Set the TCP port (restart server to apply) |
| `pos share usb server --info` / `--version` | Show server info / version |

Subcommands that need input prompt interactively when args are omitted.

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos share nfs server <cmd>` | `bin/pos-share-nfs-server` | Manage the NFS kernel server: `status`, `share <path> [client]`, `unshare <path>`, `list`, `reload`, `enable`, `disable` | Requires `nfs-kernel-server` (added to `preinstall.sh` PACKAGES). Exports live in `/etc/exports`; `share` is idempotent (replaces any existing line for the path) and runs `exportfs -ra`. Default client `*(rw,sync,no_subtree_check)` — the tool warns you to restrict it; help prints Tailscale CGNAT (`100.64.0.0/10`), WireGuard (`10.10.0.0/24`) and LAN examples. Mutating commands announce via `lib/notify.sh` |
| `pos share nfs client <cmd>` | `bin/pos-share-nfs-client` | Mount and manage NFS shares: `mount <server:export> <local-dir>`, `unmount <local-dir>`, `list`, `persist <server:export> <local-dir>`, `unpersist <local-dir>` | Requires `nfs-common` (added to `preinstall.sh` PACKAGES). `persist` writes a systemd `.mount` unit (`systemd-escape --path --suffix=mount`) with `After=network-online.target` / `Wants=network-online.target` — mounts only once all interfaces are up, no fstab edits to break boot — then `daemon-reload` + `enable --now`. `unpersist` stops/disables/removes the unit. `mount`/`persist` announce via `lib/notify.sh` |
| `pos share smb server <cmd>` | `bin/pos-share-smb-server` | Manage the Samba server: `status`, `share <path> [name] [--read-only|--guest|--users u1,u2]`, `unshare <name>`, `list`, `adduser <user>`, `deluser <user>`, `reload`, `enable`, `disable` | Requires `samba` (added to `preinstall.sh` PACKAGES). Shares are idempotent marker blocks (`# >>> pos-managed share: <name>` … `# <<< end pos-managed share`) in `/etc/samba/smb.conf` — hand edits outside the markers survive; `share` validates with `testparm` before applying and hot-reloads via `smbcontrol smbd reload-config`. Defaults rw + browsable; warns when unrestricted (guest or no `valid users`). `adduser`/`deluser` manage Samba accounts via `smbpasswd`. Mutating commands announce via `lib/notify.sh` |
| `pos share smb client <cmd>` | `bin/pos-share-smb-client` | Mount and manage SMB/CIFS shares: `mount <//server/share> <local-dir> [user]`, `unmount <local-dir>`, `list`, `persist <//server/share> <local-dir> [user]`, `unpersist <local-dir>` | Requires `cifs-utils` (added to `preinstall.sh` PACKAGES). With a user you are prompted for the Samba password — one-shot mounts use a throwaway chmod-600 credentials file, `persist` keeps one at `/etc/samba/credentials/<name>` (chmod 600). `persist` writes a systemd `.mount` unit (`systemd-escape --path --suffix=mount`) with `x-systemd.automount` + `_netdev` — mounts on first access, never blocks boot — then `daemon-reload` + `enable --now`. `unpersist` stops/disables/removes the unit + credentials. `mount`/`persist` announce via `lib/notify.sh` |

### communication

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos communication telegram sender send "text"` | `bin/pos-communication-telegram-sender` | Send a message, link, or media file (auto-detects the type) to a Telegram chat via the Bot API | Token + chat ID from `~/.config/linux_post_install/telegram.env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, chmod 600). Precedence: `--token`/`--chat-id` flags > env > config file |
| `pos communication telegram listener` | `bin/pos-communication-telegram-listener` | Telegram bot listener: map `/command` → bash commands and run them from chat; interactive editor for the map | Same `telegram.env` (the bot is the owner, `TELEGRAM_CHAT_ID`). Map lives in `~/.config/linux_post_install/telegram_commands.env` (`/cmd=bash command` lines, chmod 600) |
| `pos communication matrix sender send "text"` | `bin/pos-communication-matrix-sender` | Send a text message (plain or `--markdown`) to a Matrix room via the client-server API; also `login` (password → access token) and `test` | Homeserver + room from `~/.config/linux_post_install/matrix.env` (`MATRIX_HOMESERVER`, `MATRIX_ACCESS_TOKEN`, `MATRIX_USER_ID`, `MATRIX_ROOM_ID`, chmod 600, secrets masked by `pos config matrix`). Precedence: `--room` flag > env > config file |
| `pos communication matrix listener` | `bin/pos-communication-matrix-listener` | Matrix listener: map `/command` → bash commands and run them from room messages; interactive editor for the map | Same `matrix.env` (reacts to `MATRIX_USER_ID`'s own messages; watches `MATRIX_ROOM_ID` or all joined rooms). Map lives in `~/.config/linux_post_install/matrix_commands.env` (`/cmd=bash command` lines, chmod 600) |

`pos communication telegram sender` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication telegram sender send "text"` | POSTs `sendMessage` to the Bot API (60s timeout); prints `[+] message sent to chat <id>` or fails with a nonzero exit |
| `pos communication telegram sender send <value>` | **Auto-detects the type** when `--type` is omitted: existing file → `file` (except `.webp` → sticker, `.gif` → animation, images → photo, video/audio/voice extensions → their type), value starting with `http://`/`https://`/`www.` → `link`, otherwise `message` |
| `pos communication telegram sender send <path> --type file [--caption "…"]` | Uploads a file as a `sendDocument` via multipart (`document=@path`); `--caption` adds a caption. Path must exist and be readable |
| `pos communication telegram sender send <path> [--caption "…"]` | Media uploads via their Bot API endpoint: `--type photo` → `sendPhoto`, `video` → `sendVideo`, `audio` → `sendAudio`, `voice` → `sendVoice`, `animation` → `sendAnimation`, `sticker` (`.webp`) → `sendSticker` (captions not supported for stickers) |
| `pos communication telegram sender send "url" --type link [--no-preview]` | Sends a link as a message (URLs auto-linkify); `--no-preview` adds `disable_web_page_preview=true` |
| `pos communication telegram sender send "text" --parse-mode <mode>` | Send with Telegram formatting; `<mode>` is `plain` (default), `markdown`, or `html` (passed as `parse_mode` to the API — also applies to captions). Markdown/HTML use raw Telegram syntax — unescaped characters may be rejected by the API (400) |
| `pos communication telegram sender send … --token <t> --chat-id <id>` | One-shot override of token/chat ID |
| `pos communication telegram sender test` | Sends a canned test message using the current config |

`send` option validation: `--caption` is only valid with media types (file/photo/video/audio/voice/animation), `--no-preview` only with `--type message`/`link`, and `--type` only accepts `message|file|link|sticker|photo|video|audio|voice|animation`. An explicit `--type` always overrides auto-detection.

The bot token is a secret — it is stored only in `~/.config/linux_post_install/telegram.env` and never in the repo. Edit `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` interactively with `pos config telegram` (masked input + display). Requires network access to `api.telegram.org`.

`pos communication telegram listener` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication telegram listener` | Interactive editor for the `/command` → bash map (`a`dd / `e`dit / `r`emove / `t`est / `q`uit); test-runs run `bash -n` first and may execute the command live |
| `pos communication telegram listener --status` | Shows service state (running/autostart), config + map file paths, and the mapped commands |
| `pos communication telegram listener --enable` | Installs + starts a systemd **user** service (`pos-telegram-listener.service`); the daemon polls `getUpdates` and runs mapped commands |
| `pos communication telegram listener --disable` | Stops, disables, and removes the service |
| `pos communication telegram listener --sync-commands` | Push the mapped `/commands` to the bot's `/` menu (`setMyCommands`) — also run automatically after every map edit, on `--enable`, and at daemon start |
| `pos communication telegram listener --run` | Run the polling loop in the foreground (what the service executes) |

The map file is re-read for every message — edits apply without a restart. The listener only reacts to the owner chat (`TELEGRAM_CHAT_ID`); anyone else's message is ignored. `/help` lists mapped commands; an unmapped command replies "Unknown command". Non-command text starting with `ai ` (case-insensitive, e.g. `ai what is Nvidia`) is forwarded to Gemini via `pos ai gemini ask` and the answer is replied verbatim; an AI failure replies the error plus a `pos config ai` hint. Commands run as your user via `timeout 60 bash -c "…"` (stdout + stderr are replied, truncated to ~3800 chars; empty output → `OK`), so `sudo` inside them needs a NOPASSWD rule. A map value prefixed with `@quiet ` runs the command but does NOT reply — for commands that already send their own notification (e.g. `/status=@quiet pos system health --send`), avoiding a double message. `--enable` warns if linger is off — the service stops when you log out unless you run `sudo loginctl enable-linger $(whoami)`.

Map entries may carry an optional **description** shown in the bot's `/` menu: `/cmd::short description=bash command` (the description falls back to the bash command, truncated to ~40 chars, when omitted). After every add/edit/remove the command list is pushed to the bot via `setMyCommands`, so the menu stays in sync; an empty map clears the menu. Telegram only registers lowercase `[a-z0-9_]` names (1–32 chars) — commands like `/Status` or `/my-cmd` are skipped from the menu with a warning but still resolve when typed.

`pos communication matrix sender` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication matrix sender send "text"` | PUTs an `m.room.message` (`m.text`) to the homeserver's client-server API v3 (60s timeout); prints `[+] m.text sent to room <room>` or fails with a nonzero exit. Room id/alias is URL-encoded automatically; a unique transaction id (`<timestamp>ns`) is generated per message |
| `pos communication matrix sender send "text" --markdown` | Sends with `format: org.matrix.custom.html` — a best-effort markdown → HTML conversion (`**bold**`, `__bold__`, `*em*`, `_em_`, `` `code` ``, ``` ```fences``` ``, `~~strike~~`, `[link](url)`, headers, list items). Deliberately simple; it never fails the send |
| `pos communication matrix sender send "text" --room <id\|alias>` | One-shot override of the room for this send only (e.g. `--room '#ops:example.org'`) |
| `pos communication matrix sender login --user <@id>` | Prompts (masked) for the account password, POSTs `m.login.password` to `/login`, and saves the returned `access_token` + `user_id` to `matrix.env` |
| `pos communication matrix sender test` | Sends a canned test message (`Test message from pos <timestamp>`) using the current config |

The access token is a secret — it is stored only in `~/.config/linux_post_install/matrix.env` and never in the repo. `pos config matrix` edits `MATRIX_HOMESERVER`, `MATRIX_ACCESS_TOKEN` (masked), `MATRIX_USER_ID`, `MATRIX_ROOM_ID`. Requires network access to your homeserver. The sender implements the `lib/notify.sh` sender contract, so `matrix` can be added to `NOTIFY_PLATFORM` for multi-platform alerting.

`pos communication matrix listener` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication matrix listener` | Interactive editor for the `/command` → bash map (`a`dd / `e`dit / `r`emove / `t`est / `q`uit); test-runs run `bash -n` first and may execute the command live |
| `pos communication matrix listener --status` | Shows service state (running/autostart), config + map file paths, and the mapped commands |
| `pos communication matrix listener --enable` | Installs + starts a systemd **user** service (`pos-matrix-listener.service`); the daemon long-polls `/sync` and runs mapped commands |
| `pos communication matrix listener --disable` | Stops, disables, and removes the service |
| `pos communication matrix listener --run` | Run the polling loop in the foreground (what the service executes) |

The daemon long-polls `/sync` (30s timeout, per-sync `since` token, compact filter that drops presence/account_data/device noise and only requests `m.room.message` timeline events). It reacts only to messages **from `MATRIX_USER_ID`** (your own account — resolved via `/account/whoami` if unset); a `MATRIX_ROOM_ID` restricts it to one room, otherwise every joined room is watched. `/` and `!` prefixes both resolve (`!status` = `/status`). `/help` lists mapped commands; an unmapped command replies "Unknown command". Non-command text starting with `ai ` (case-insensitive, e.g. `ai what is Nvidia`) is forwarded to Gemini via `pos ai gemini ask` with a per-room session (`matrix-<room>`; `ai /reset` clears it) and the answer is replied verbatim with markdown stripped. Replies are sent as `m.text` threaded with `m.in_reply_to` on your message. Commands run as your user via `timeout 60 bash -c "…"` (stdout + stderr are replied, truncated to ~3800 chars; empty output → `OK`; non-zero exit is prefixed with `exit <rc>`), so `sudo` inside them needs a NOPASSWD rule. A map value prefixed with `@quiet ` runs the command but does NOT reply — for commands that already send their own notification (e.g. `/status=@quiet pos system health --send`). Map lines may carry a `/cmd::description=…` description. `--enable` warns if linger is off — the service stops when you log out unless you run `sudo loginctl enable-linger $(whoami)`.

### entertainment

**File:** `bin/pos-entertainment-send`
**Purpose:** run a public-API plugin and send its output to Telegram by default. Plugins are standalone scripts in `entertainment/` that fetch a public API and **print the message to stdout** — that stdout is what gets sent.

| Command | Behavior |
|---------|----------|
| `pos entertainment send` | List available plugins + usage |
| `pos entertainment send <plugin> [--print] [--markdown] [args…]` | Run the plugin, send its output to Telegram (silent) |
| `pos entertainment send <plugin> --print` | Print the output locally; do not send |
| `pos entertainment send <plugin> --markdown` | Send with `--parse-mode markdown` (via `pos communication telegram sender`) |
| `pos entertainment config` | Show the config file (`~/.config/linux_post_install/entertainment.env`) |
| `pos entertainment config set KEY=VALUE…` | Set keys (any UPPER_SNAKE key; warns if no installed plugin uses it) and re-sync the schedule |
| `pos entertainment enable <plugin> [interval]` | Add plugin to `ENABLED` + schedule it as a systemd user timer |
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

`pos entertainment enable <plugin> [interval]` appends/updates one entry and re-syncs; `pos entertainment disable <plugin>` removes it; `pos entertainment config set ENABLED="…"` replaces the whole list. Scheduling uses **systemd user timers** (requires a reachable user systemd manager):

- One **user timer** per enabled plugin (`~/.config/systemd/user/pos-entertainment-<plugin>.{service,timer}`), running `pos entertainment send <plugin>` as your user on that schedule (`OnCalendar` + `Persistent=true`). `pos entertainment enable` also tries `sudo loginctl enable-linger $USER` once so timers fire without login.

The job runs as you, so it reads your `$HOME` configs (weather location, Telegram token) natively — no `Environment=HOME=` hacks.

Intervals: `5m 10m 15m 30m 45m hourly 2h 6h 12h daily weekly`, or a raw `OnCalendar=…` spec. Default when omitted: `daily`.

`pos entertainment status` shows the enabled plugins, the scheduler, and each plugin's interval + next fire time (`systemctl --user list-timers`).

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

### config

`pos config` is the interactive editor for the tools' runtime config (see [DEV.md](DEV.md#config-files) and §10 of AGENT_Context). Every tool exposes its configuration by declaring a `# POS_CONFIG:` header; `pos config` reads those at runtime — it knows nothing about the variables themselves. Values live in `~/.config/linux_post_install/<scope>.env` (chmod 600).

| Command | Purpose |
|---------|---------|
| `pos config` | Scope picker (on a TTY), otherwise the scope list |
| `pos config <scope>` | Edit that scope's variables (masked secrets, validation, `-` to clear) |
| `pos config <scope> set KEY=VALUE` | Set a value non-interactively (each tool's `config set` form) |

### tree

`pos tree` prints the `pos` command tree — every category, command, and subcommand the dispatcher can reach, annotated with each tool's `# POS:` description. Data is derived live from the `bin/pos-*` filenames and their `# POS_SUBCMDS:` headers, so it always matches what `pos` can actually run.

| Command | Purpose |
|---------|---------|
| `pos tree` | Full command tree |
| `pos tree --depth N` | Limit nesting depth (1 = root only) |

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
