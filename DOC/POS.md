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
  - [vbox](#vbox)
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

`pos help <command>` runs `<that command> --help`. Running `pos` with no args prints the built-in usage text (which doubles as the category cheat-sheet).

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
| `pos network ip` | `bin/pos-network-ip` | Show interfaces, default route, public IP | None. Public IP via `https://ifconfig.me` (5s timeout) |
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

### vbox

**File:** `bin/pos-vbox`
**Purpose:** manage disposable Docker containers as lightweight "VMs". Each container gets a bind-mounted host directory so files persist after the container is removed. Containers carry the label `linux_post_install.vbox=true`.

| Command | Behavior |
|---------|----------|
| `pos vbox create <name> [image] [--dir <path>]` | Creates a container from `ubuntu:22.04` (or the given image), bind-mounting `~/<name>` (or `--dir`, or `.` for cwd) as the working directory; prompts to enter immediately |
| `pos vbox enter <name>` | Shell into the container (auto-starts it if stopped); detects the working dir from the container mounts |
| `pos vbox start/stop/rm <name>` | Start, stop, or force-remove the container |
| `pos vbox ls` | List vbox containers only (label filter) |

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
| `vbox` | `pos vbox` |
| `ssh-load-all` | `pos ssh load-keys` |
