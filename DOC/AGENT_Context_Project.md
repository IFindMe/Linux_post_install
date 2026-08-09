# AGENT Context — Linux_post_install Project

> **Purpose:** Single-source context document so any AI agent can understand the project, navigate the codebase, and make correct contributions.

---

## Document Map

> Auto-generated section index (line ranges). Run `make gen` to refresh.

<!-- GEN:START docmap -->
| ## 1. Project Overview | 28–43 |
| ## 2. Directory Structure | 44–183 |
| ## 3. Installation Flow | 184–236 |
| ## 4. The `pos` CLI System | 237–300 |
| ## 5. Shared Library — `lib/common.sh` | 301–332 |
| ## 6. Docker Compose / ScaleTail | 333–375 |
| ## 7. Optional Apps (`apps/`) | 376–405 |
| ## 8. Entertainment Module | 406–419 |
| ## 9. Systemd Services | 420–432 |
| ## 10. Configuration Files | 433–459 |
| ## 11. Coding Conventions | 460–492 |
| ## 12. Development Workflow | 493–545 |
| ## 13. Key File Quick Reference | 546–595 |
| ## 14. Common Tasks for Agents | 596–621 |
<!-- GEN:END docmap -->

## 1. Project Overview

**Linux_post_install** is a personal bootstrap and homelab toolkit for Debian/Ubuntu. One command turns a bare install into a fully productive machine:

- Automated system package installation (25+ packages)
- A unified CLI (`pos`) for network, Docker, media, system, and SSH tasks
- Optional desktop application installers (15 apps)
- Docker Compose service management via ScaleTail templates (119+ self-hosted services with Tailscale sidecar)
- Systemd service management for boot-time automation

**Repository:** `https://gitea.skink-platy.ts.net/admin/Linux_post_install`
**Target OS:** Debian / Ubuntu (uses `apt`)
**Shell:** Bash (`#!/usr/bin/env bash`)

---

## 2. Directory Structure

```
Linux_post_install/
├── install.sh              # Main orchestrator — entry point
├── preinstall.sh           # Phase 1: system packages via apt + yt-dlp
├── postinstall.sh          # Phase 3: PATH, bash completion, systemd services
│
├── lib/
│   ├── common.sh           # Shared library (colors, logging, spinner, timer, run, load_system_env)
│   ├── flags.sh            # Feature flag store (flag_set/clear/is_set/value/list/status)
│   ├── notify.sh           # Multi-platform alerting (notify_send) — sourced opt-in, silent-fails
│   └── entertainment-lib.sh # Entertainment module lib (ENABLED list, scheduler sync)
│
├── bin/                    # CLI tools — installed to /usr/local/bin/
│   ├── pos                 # Main dispatcher — smart arg matching to pos-* scripts
<!-- GEN:START tree -->
│   ├── pos-ai-gemini                       # Chat with Google Gemini (ask, chat, models, sessions)
│   ├── pos-communication-telegram-listener # Telegram bot listener: map /command → bash, run them on chat messages
│   ├── pos-communication-telegram-sender   # Send Telegram messages/files/links/stickers via Bot API (send, test)
│   ├── pos-config                          # Interactive editor for the tools' runtime config (reads # POS_CONFIG: registry)
│   ├── pos-docker-compose                  # Docker Compose service manager (ls/up/down/restart/logs/update/config)
│   ├── pos-docker-health                   # One-glance container health dashboard (exits 1 if unhealthy)
│   ├── pos-docker-ps                       # Enhanced container overview (health, IPs, ports, uptime)
│   ├── pos-docker-vbox                     # Disposable Docker-based VMs (create/enter/start/stop/rm/ls)
│   ├── pos-entertainment-config            # Show or edit the entertainment config (ENABLED auto-trigger list, weather location)
│   ├── pos-entertainment-disable           # Disable a plugin's auto-trigger (remove it from ENABLED)
│   ├── pos-entertainment-enable            # Enable an auto-trigger for a plugin on a schedule
│   ├── pos-entertainment-send              # Run a public-API plugin and send its output via Telegram (default sender)
│   ├── pos-entertainment-status            # Show enabled plugins and scheduler state
│   ├── pos-media-mp3                       # Download audio as MP3 (yt-dlp)
│   ├── pos-media-mp4                       # Download video as MP4 (interactive format select)
│   ├── pos-network-checkport               # Check TCP port connectivity
│   ├── pos-network-hotspot                 # Wi-Fi hotspot via create_ap + wihotspot-gui
│   ├── pos-network-ip                      # Show interfaces, routes, public IP + location
│   ├── pos-network-scan                    # Parallel ping sweep of CIDR
│   ├── pos-ssh-load-keys                   # Load all SSH keys into the agent
│   ├── pos-system-backup                   # Encrypted (AES-256) folder snapshots (tar + gpg)
│   ├── pos-system-firewall                 # Interactive UFW management
│   ├── pos-system-health                   # Host health dashboard (disk, RAM, services, backup age, fail2ban, docker); exit 1 if any FAIL
│   ├── pos-system-nfs-client               # Mount NFS shares (ephemeral or persistent systemd mount units)
│   ├── pos-system-nfs-server               # Manage the NFS kernel server (status, share/unshare exports, enable/disable)
│   ├── pos-tree                            # Show the pos CLI command tree: categories, commands, and subcommands
│   ├── pos-usb-server                      # USB Redirector server control (--ls, --share; prompts when args omitted)
<!-- GEN:END tree -->
│   ├── flag-reader         # Inspect feature flags (list/status/--raw)
│   ├── flag-set            # Set a feature flag (optionally with a value)
│   ├── flag-clear          # Unset a feature flag
│   ├── wr-*                # Legacy wrappers → pos (backward compat)
│   ├── mp3, mp4, vbox      # Legacy convenience wrappers → pos
│   └── ssh-load-all        # Legacy wrapper → pos ssh load-keys
│
├── features/               # User-customizable scripts (installed via --feature)
│   └── autostart.sh        # Boot-time script (via systemd, flag-gated)
│
├── entertainment/          # Public-API plugins for pos entertainment send (→ /usr/local/bin)
│   ├── weather.sh          # Current weather via Open-Meteo (no API key)
│   ├── joke.sh             # Random dad joke via icanhazdadjoke (no API key)
│   └── gold.sh             # Gold spot (XAU/USD) via goldprice.dev (no API key)
│
├── templates/              # Dev-only scaffolds — NOT installed by install.sh
│   ├── pos-tool.sh         # New `pos` CLI tool (→ bin/pos-<cat>-<cmd>)
│   ├── app.sh              # New optional app installer (→ apps/<cat>/<name>.sh)
│   └── feature.sh          # New feature script (→ features/<name>.sh)
│
├── x64_bin/                # Precompiled binaries, copied to /usr/local/bin on x86_64
│   ├── create_ap           # Wi-Fi AP CLI (bash script)
│   ├── wihotspot           # Wrapper → wihotspot-gui
│   └── wihotspot-gui       # GTK3 hotspot GUI (x86-64 ELF)
│                           # future: arm64_bin/ picked up automatically on aarch64
│
├── apps/                   # Optional desktop app installers (by category)
│   ├── install.sh          # Interactive picker / orchestrator
│   ├── browsers/
│   │   └── brave.sh       # Brave Browser (APT repo)
│   ├── development/
│   │   ├── opencode.sh    # opencode AI agent (official script)
│   │   └── vscode.sh      # VS Code (Microsoft APT repo)
│   ├── media/
│   │   ├── obs.sh         # OBS Studio (apt)
│   │   ├── scrcpy.sh      # scrcpy Android mirror (GitHub release)
│   │   └── vlc.sh         # VLC media player (apt)
│   ├── networking/
│   │   ├── netbird.sh     # NetBird VPN (official script)
│   │   ├── tailscale.sh   # Tailscale VPN (official script)
│   │   └── zerotier.sh    # ZeroTier VPN (official script)
│   ├── remote-access/
│   │   ├── termius.sh     # Termius SSH client (.deb)
│   │   └── vnc-viewer.sh  # TigerVNC Viewer (apt)
│   ├── system/
│   │   ├── docker.sh      # Docker Engine (get.docker.com)
│   │   └── qemu.sh        # QEMU + libvirt + KVM (apt)
│   └── utilities/
│       ├── affine.sh      # AFFiNE knowledge base (AppImage)
│       ├── btop.sh        # btop resource monitor (apt)
│       ├── localsend.sh   # LocalSend (flatpak)
│       └── tsui.sh        # Tailscale config TUI (official install script)
│
├── completions/
│   └── pos.bash            # Bash tab-completion for the pos CLI
│
├── config/
│   ├── authorized_keys     # SSH public keys (gitignored)
│   ├── entertainment.env   # Weather location template (auto-installed by postinstall)
│   └── ai.env              # Gemini API key + model template (auto-installed by postinstall)
│
├── compose/
│   └── scale-tail/         # Git submodule → ScaleTail templates (119+ services)
│
├── systemd/
│   ├── autostart.service   # Runs autostart.sh on boot
│   ├── ssh-agent.service   # System-wide SSH agent socket
│   ├── pos-health.service  # Runs the health digest as the installing user (triggered by timer)
│   └── pos-health.timer    # Daily 08:00 trigger for the health digest (enabled when Telegram is configured)
│
├── scripts/                # Dev tooling
│   ├── gen-docs.sh         # Regenerates code-derived doc sections + completion flags
│   ├── check-sync.sh       # `make check` gate (syntax, exec bits, doc/code sync, smoke)
│   └── install-hooks.sh    # Installs the opt-in pre-commit hook (`make hook`)
│
├── README.md               # User-facing intro + quick start (links into DOC/)
│
├── DOC/                    # All documentation
│   ├── README.md           # Docs index
│   ├── SCRIPTS.md          # Installer scripts, libs, features — reference
│   ├── POS.md              # pos CLI reference
│   ├── APPS.md             # Optional apps reference
│   ├── SYSTEMD.md          # Systemd units + completion
│   ├── DEV.md              # Developer guide
│   ├── HOWTO.md            # Hands-on guides index (per-category tutorials)
│   ├── howto/              # Per-category tutorials (network, docker, media, system, ssh, usb, communication, entertainment)
│   ├── AGENT_Context_Project.md  # This file — AI agent context
│   └── algorithm.md        # Algorithm diagrams
│
├── .gitignore              # Excludes secrets, Python artifacts, OS files
└── .gitmodules             # Submodule: compose/scale-tail → ScaleTail
```

---

## 3. Installation Flow

```
User runs: ./install.sh [--apps|--full|--feature|--dry-run|--skip <phase>|--steps <spec>]
│
├─ Phase 1: preinstall.sh        (requires root)
│   └─ apt update + installs 25+ packages + yt-dlp + fail2ban
│
├─ Phase 2: install.sh           (requires root)
│   └─ Copies bin/* → /usr/local/bin/ (chmod 755)
│   └─ Copies lib/common.sh + lib/flags.sh + lib/notify.sh + lib/entertainment-lib.sh → /usr/local/bin/ (chmod 644)
│   └─ Copies x64_bin/* → /usr/local/bin/ on x86_64 (arm64_bin/ on aarch64)
│   └─ [if --feature] Copies features/* → /usr/local/bin/ (asks before overwriting),
│                      then sets the matching feature flag
│
├─ Phase 3: postinstall.sh       (runs as user)
│   └─ Configures fail2ban (SSH jail: 5 retries, 1h ban)
│   └─ PATH export in ~/.bashrc
│   └─ Bash completion for pos CLI
│   └─ Copies systemd/*.service + systemd/*.timer → /etc/systemd/system/, enables them
│      (autostart.service only when the `autostart` flag is set;
│       pos-health.timer only when the user's Telegram config exists)
│
├─ Phase 4: ScaleTail clone
│   └─ Shallow-clones ScaleTail templates to /usr/local/share/linux_post_install/scale-tail
│
└─ [if --apps or --full]: apps/install.sh
    └─ Interactive picker (or --all for non-interactive)
```

**After install, the repo can be deleted** — all tools live in `/usr/local/bin/` and templates in `/usr/local/share/linux_post_install/`.

### install.sh Flags

| Flag | Purpose |
|------|---------|
| `--apps` | Run interactive app picker after core install |
| `--full` | Core install + all apps (non-interactive) |
| `--feature` | Install `features/` scripts to `/usr/local/bin/` (asks before overwriting), set their flags |
| `--dry-run` | Preview without executing |
| `--skip <phase>` | Skip a phase (repeatable): `preinstall`, `scripts`, `postinstall`, `scalepoint`, `apps` |
| `--steps <spec>` | Run only specific phases. Format: `1,3,4` or `1-3` |
| `--no-color` | Disable colored output |

### pos Output Logging

All non-interactive `pos` commands log output to `~/.local/share/linux_post_install/logs/`:
- Per-command files: `YYYYMMDD_HHMMSS_pos_<cmd>.log` (full stdout+stderr)
- Main log: `pos.log` (command + timestamp + exit code for every invocation)
- Interactive commands (`system-firewall`, `media-mp4`) only log invocation, not output

---

## 4. The `pos` CLI System

### How It Works

`bin/pos` is the main dispatcher. It:
1. Scans its own directory for all executable `pos-*` files
2. Extracts category-subcommand names from filenames
3. Uses variable-length argument matching to find the right script

**Example:** `pos docker compose up jellyfin`
- Tries `pos-docker-compose-up-jellyfin` (not found)
- Tries `pos-docker-compose-up` (not found)
- Finds `pos-docker-compose` (runs with args `up jellyfin`)

### Available Commands

| Category | Command | Script | Description |
|----------|---------|--------|-------------|
<!-- GEN:START dispatch -->
| ai | gemini | `pos-ai-gemini` | Chat with Google Gemini (ask, chat, models, sessions) |
| communication | telegram-listener | `pos-communication-telegram-listener` | Telegram bot listener: map /command → bash, run them on chat messages |
| communication | telegram-sender | `pos-communication-telegram-sender` | Send Telegram messages/files/links/stickers via Bot API (send, test) |
|  | config | `pos-config` | Interactive editor for the tools' runtime config (reads # POS_CONFIG: registry) |
| docker | compose | `pos-docker-compose` | Docker Compose service manager (ls/up/down/restart/logs/update/config) |
| docker | health | `pos-docker-health` | One-glance container health dashboard (exits 1 if unhealthy) |
| docker | ps | `pos-docker-ps` | Enhanced container overview (health, IPs, ports, uptime) |
| docker | vbox | `pos-docker-vbox` | Disposable Docker-based VMs (create/enter/start/stop/rm/ls) |
| entertainment | config | `pos-entertainment-config` | Show or edit the entertainment config (ENABLED auto-trigger list, weather location) |
| entertainment | disable | `pos-entertainment-disable` | Disable a plugin's auto-trigger (remove it from ENABLED) |
| entertainment | enable | `pos-entertainment-enable` | Enable an auto-trigger for a plugin on a schedule |
| entertainment | send | `pos-entertainment-send` | Run a public-API plugin and send its output via Telegram (default sender) |
| entertainment | status | `pos-entertainment-status` | Show enabled plugins and scheduler state |
| media | mp3 | `pos-media-mp3` | Download audio as MP3 (yt-dlp) |
| media | mp4 | `pos-media-mp4` | Download video as MP4 (interactive format select) |
| network | checkport | `pos-network-checkport` | Check TCP port connectivity |
| network | hotspot | `pos-network-hotspot` | Wi-Fi hotspot via create_ap + wihotspot-gui |
| network | ip | `pos-network-ip` | Show interfaces, routes, public IP + location |
| network | scan | `pos-network-scan` | Parallel ping sweep of CIDR |
| ssh | load-keys | `pos-ssh-load-keys` | Load all SSH keys into the agent |
| system | backup | `pos-system-backup` | Encrypted (AES-256) folder snapshots (tar + gpg) |
| system | firewall | `pos-system-firewall` | Interactive UFW management |
| system | health | `pos-system-health` | Host health dashboard (disk, RAM, services, backup age, fail2ban, docker); exit 1 if any FAIL |
| system | nfs-client | `pos-system-nfs-client` | Mount NFS shares (ephemeral or persistent systemd mount units) |
| system | nfs-server | `pos-system-nfs-server` | Manage the NFS kernel server (status, share/unshare exports, enable/disable) |
|  | tree | `pos-tree` | Show the pos CLI command tree: categories, commands, and subcommands |
| usb | server | `pos-usb-server` | USB Redirector server control (--ls, --share; prompts when args omitted) |
<!-- GEN:END dispatch -->

### Legacy Wrappers

These forward to `pos` transparently: `wr-ip`, `wr-checkport`, `wr-scan-ping`, `wr-docker`, `wr-compose`, `wr-ufw`, `mp3`, `mp4`, `vbox`, `ssh-load-all`.

### pos docker vbox Details

`pos-docker-vbox` manages disposable Docker containers as lightweight VMs:

- **Container labeling:** All created containers get `linux_post_install.vbox=true` label
- **`ls` filtering:** `docker ps --filter label=linux_post_install.vbox=true` — only shows vbox-managed containers
- **Post-create prompt:** After `create`, asks "Enter now? [Y/n]" using `confirm` helper
- **Working dir detection:** `enter` auto-detects bind mount path from container labels
- **Custom dirs:** `--dir <path>` or `--dir .` for current directory

---

## 5. Shared Library — `lib/common.sh`

Sourced by most scripts. Provides:

| Function | Purpose |
|----------|---------|
| `log "msg"` | Green `[+]` status message |
| `warn "msg"` | Yellow `[!]` warning |
| `err "msg"` | Red `ERROR:` + exit 1 |
| `ok "msg"` | Green `OK` prefix |
| `section "title"` | Cyan-bordered section header |
| `step N T "msg"` | Numbered step header (e.g., `[1/4] Installing`) |
| `run cmd` | Executes command, respects `$DRY_RUN` |
| `spawn "msg" cmd` | Runs with animated braille spinner, elapsed time, OK/FAIL status; respects `$DRY_RUN` |
| `timer_start` / `timer_stop` | Elapsed time tracking |
| `confirm "prompt" [default]` | y/N or Y/n prompt |
| `load_system_env` | Loads `~/.config/linux_post_install/system.env` (env already exported wins) |

**Auto-detects TTY** — disables colors when piped.

**Source pattern:**
```bash
source "$(dirname "$0")/../lib/common.sh"
```

**Scripts that do NOT source common.sh** (self-contained):
<!-- GEN:START selfcontained -->
`pos`, `pos-communication-telegram-listener`, `pos-communication-telegram-sender`, `pos-network-checkport`, `pos-network-hotspot`, `pos-network-ip`, `pos-network-scan`, `pos-ssh-load-keys`, `pos-system-firewall`.
<!-- GEN:END selfcontained -->

---

## 6. Docker Compose / ScaleTail

### Architecture

ScaleTail provides 119+ Docker Compose templates with a Tailscale sidecar pattern (`network_mode: service:tailscale`). Each service gets a `tail-xxxxx.ts.net` URL with optional automatic HTTPS.

```
/usr/local/share/linux_post_install/scale-tail/    # Templates (git repo)
└── services/<name>/
    ├── compose.yaml
    └── .env

~/.config/linux_post_install/compose.env           # Global defaults (TS_AUTHKEY, TZ, DNS_SERVER, SERVICES_BASE)

/srv/<service>/                         # Active deployments (default base)
    ├── compose.yaml                    # From template (refreshed on update)
    ├── .env                            # User config (preserved across updates)
    ├── config/
    └── data/
```

### Key Commands

| Command | Description |
|---------|-------------|
| `pos docker compose ls` | List all available ScaleTail services |
| `pos docker compose up <svc>` | Deploy service to SERVICES_BASE |
| `pos docker compose down <svc>` | Stop a deployed service |
| `pos docker compose restart <svc>` | Restart a service |
| `pos docker compose logs <svc> [-f]` | View/follow logs |
| `pos docker compose update` | Pull latest templates, refresh compose.yaml (preserves .env) |
| `pos docker compose config set K=V` | Set global config value |
| `pos docker compose config show` | Display current config |

### Global Config Keys

- `TS_AUTHKEY` — Tailscale auth key (required)
- `TZ` — Timezone
- `DNS_SERVER` — Custom DNS
- `SERVICES_BASE` — Deployment root (default: `/srv`)

---

## 7. Optional Apps (`apps/`)

### How They Work

- `apps/install.sh` auto-discovers all `apps/<category>/*.sh` files (excluding itself)
- Three modes: interactive (default), `--all`, or specific app names as arguments
- `--uninstall` switches to uninstall mode (same selection, invokes app scripts with `uninstall` argument)
- Interactive TUI groups apps by category with section headers
- Each app script is standalone, idempotent, sources `lib/common.sh`
- Every app script defines `install_<name>()` **and** `uninstall_<name>()`, dispatched via `case "${1:-}" in uninstall) ...`

### Installation Methods

| Method | Apps |
|--------|------|
| `apt install` | btop, obs, vlc, vnc-viewer, qemu |
| APT repo (GPG + repo) | brave, vscode |
| Official `curl \| sh` | docker, tailscale, netbird, zerotier, opencode |
| AppImage | affine |
| GitHub release binary | scrcpy |
| Flatpak | localsend |
| .deb package | termius |

### Adding a New App

1. Create `apps/<category>/<name>.sh` following the template in DOC/DEV.md
2. It auto-appears in the interactive picker — no registration needed

---

## 8. Entertainment Module

Public-API "entertainment" plugins (weather, joke, gold) that can auto-send their output to Telegram on a schedule.

- **CLI:** `pos entertainment {config|enable|disable|send|status}` — see the dispatch table in §4 and POS.md [entertainment](#entertainment).
- **Library:** `lib/entertainment-lib.sh` — config-file helpers, ENABLED-list parsing, plugin lookup, and scheduler sync (systemd user timers, crontab fallback).
- **Plugins:** `entertainment/*.sh` — standalone scripts that fetch a public API and **print the message to stdout** (what gets sent). Each declares its name with a `# POS_PLUGIN: <name>` header; a new plugin is auto-discovered.
- **Config:** `~/.config/linux_post_install/entertainment.env` (ENABLED auto-trigger list, weather location). Template: `config/entertainment.env`, auto-installed by postinstall.
- **Sending:** `pos entertainment send <plugin> [--print] [--markdown]` runs the plugin and delivers via `pos communication telegram sender send`.
- **Auto-trigger:** `pos entertainment enable <plugin> <interval>` writes the plugin into ENABLED and syncs a systemd user timer (allowed intervals: `5m 10m 15m 30m 45m hourly 2h 6h 12h daily weekly`, or `OnCalendar=…`); `disable` removes it.
- **Docs:** DEV.md "Adding an Entertainment Plugin" (§1 step list) and POS.md [entertainment](#entertainment).

---

## 9. Systemd Services

| Service | File | Purpose |
|---------|------|---------|
| `ssh-agent.service` | `systemd/ssh-agent.service` | System-wide SSH agent, socket at `/run/ssh-agent/socket` |
| `autostart.service` | `systemd/autostart.service` | Runs `autostart.sh` on boot |
| `pos-health.service` | `systemd/pos-health.service` | Runs `pos system health --send --markdown` once (oneshot) as the installing user |
| `pos-health.timer` | `systemd/pos-health.timer` | Daily 08:00 trigger for the digest (enabled only when `~/.config/linux_post_install/telegram.env` exists) |

All `.service` files in `systemd/` are automatically copied to `/etc/systemd/system/` and enabled by `postinstall.sh` (timers too, when present).

---

## 10. Configuration Files

### Gitignored Secrets

- `config/rclone.conf` — rclone remote config (OAuth tokens)
- `config/authorized_keys` — SSH public keys

### Runtime Config

- `~/.config/linux_post_install/compose.env` — Docker Compose global defaults
- `~/.config/linux_post_install/entertainment.env` — entertainment plugin defaults: weather location + `ENABLED` auto-trigger list (`plugin, interval` pairs scheduled via `pos entertainment enable/disable`, systemd user timers); auto-installed from `config/entertainment.env` by `postinstall.sh` (no clobber, template printed)
- `~/.config/linux_post_install/system.env` — shared "system" tool settings (loaded by `pos system health` / `pos system backup` via `load_system_env()` in `lib/common.sh`; env already exported wins over the file); template `config/system.env`
- `~/.config/linux_post_install/notify.env` — alerting platform selection (`NOTIFY_PLATFORM=telegram,matrix`, comma-separated = fan out); read by `lib/notify.sh`; template `config/notify.env`
- `~/.config/linux_post_install/ai.env` — Google Gemini config (`AI_GEMINI_API_KEY` secret, `AI_GEMINI_MODEL` default `gemini-2.5-flash`); read by `pos ai gemini`; template `config/ai.env`, auto-installed by postinstall, edit with `pos config ai`
- `~/.bashrc` — Modified by postinstall (PATH, bash completion)

### Feature Flags

System-wide flag store at `/usr/local/share/linux_post_install/flags/`:
- One file per flag; **presence = set**, **file content = optional value** (dir 755, files 644).
- Library: `lib/flags.sh` (installed as `/usr/local/bin/flags.sh`) — `flag_set <name> [value]`, `flag_clear <name>`, `flag_is_set <name>`, `flag_value <name>`, `flag_list`, `flag_status <name>`.
- CLI: `flag-reader` (list / status / `--raw`), `flag-set`, `flag-clear`.
- Set by `./install.sh --feature`; read by `postinstall.sh` to gate systemd enablement (e.g. `autostart.service` requires the `autostart` flag).
- Writes use `run` + `sudo`, so they respect `--dry-run`. `FLAGS_DIR` is env-overridable for tests.

---

## 11. Coding Conventions

### Script Standards

- **Shebang:** `#!/usr/bin/env bash`
- **Strict mode:** `set -euo pipefail`
- **Help:** Every script accepts `-h`/`--help` via `case` pattern
- **Idempotency:** Check existence before creating/modifying
- **Exit codes:** 0 = success, 1 = error

### Naming Conventions

- `pos-<category>-<command>` — canonical tool names
- `wr-*` — legacy wrappers
- `apps/<category>/<name>.sh` — optional app installers
- Hyphens for word separation, lowercase always

### Error Handling

- `command -v <tool> &>/dev/null` to check tool availability
- `set -euo pipefail` for fail-fast
- `err()` for fatal errors, `warn()` for non-fatal
- Confirmation prompts for destructive actions

### Security

- Never hardcode secrets in scripts
- Use `chmod 600` for sensitive files
- Validate user input before shell commands
- Use `sudo` only where necessary

---

## 12. Development Workflow

### Adding a New Feature

1. Create `features/<name>.sh` from `templates/feature.sh` (installed on demand via `./install.sh --feature`; never overwritten without asking)
2. `install.sh` auto-discovers it and sets its flag — no registration needed
3. If a systemd service depends on it, gate the service on `flag_is_set <name>` in `postinstall.sh`
4. Update `DOC/AGENT_Context_Project.md` file table if line counts change

### Adding a New App

1. Create `apps/<category>/<name>.sh` from `templates/app.sh` (per DOC/DEV.md)
2. It auto-appears in the interactive picker — no registration needed
3. Update `DOC/APPS.md` catalog table (name, category, purpose, install method)
4. Test: `bash -n apps/<cat>/<name>.sh && shellcheck apps/<cat>/<name>.sh`

### Adding a New Tool

0. Define the exact CLI verb (`pos <category> <command> [<subcommand>]`) and its runtime context before writing code: a **dev/repo-only** tool (e.g. reads repo files, like `pos tree`) or a **runtime** tool that must work from `/usr/local/bin` after the repo is deleted. Category-less `bin/pos-<cmd>` is for dispatcher/dev-level commands that fit no category (`pos-config`, `pos-tree`); everything else goes in a category.
1. Create `bin/pos-<category>-<command>` (or `bin/pos-<cmd>` for category-less) from `templates/pos-tool.sh` — must be executable (`100755`); it auto-appears in `pos <category> --help` (filename-derived, no registration)
2. Add the `# POS: <cat> <cmd> — <one-line description>` header right after the shebang (plus `# POS_FLAGS: ...` for flag-style tools and `# POS_SUBCMDS: ...` for multi-command tools) — this is the single source of truth for the generated docs; nested tools (`pos-<cat>-<a>-<b>`) auto-list under their parent tool
3. Add to `INTERACTIVE_CMDS` in `bin/pos` if it reads stdin
4. Add system deps to `PACKAGES` array in `preinstall.sh` (if needed); non-apt/manual installers → `command -v` guard in the tool instead
5. Add config logic to `postinstall.sh` (if needed, with `.gitignore` for secrets); runtime tool config → `~/.config/linux_post_install/<tool>.env` (600)
6. Update docs: `DOC/POS.md` (section table + detail — hand-written); `DOC/AGENT_Context_Project.md` generated sections (bin tree, dispatch table, self-contained list, line-count table) and completion flags update via `make gen` — never hand-edit between `GEN:START`/`GEN:END` markers; root `README.md` only if the category list changes
7. Test: `make gen && make check` — `make check` (bash -n + doc/code sync + smoke) is the definition of done; also `bin/pos help <full command> && bin/pos <category> --help`

### Testing

```bash
# Syntax check all scripts
for f in bin/* apps/*/*.sh lib/common.sh install.sh preinstall.sh postinstall.sh; do
    bash -n "$f" || echo "FAIL: $f"
done

# ShellCheck linting
shellcheck bin/my-script

# Test in Docker
docker run --rm -it -v $PWD:/repo ubuntu:22.04 bash
# inside: cd /repo && ./install.sh

# Test apps interactively
./apps/install.sh --all
./apps/install.sh docker vscode
```

### Commit Conventions

Use conventional prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`

---

## 13. Key File Quick Reference

| File | Lines | Purpose |
|------|-------|---------|
| `install.sh` | 206 | Main orchestrator — 4 phases with CLI flags, `--feature`, prebuilt arch bins |
| `preinstall.sh` | 55 | System packages + hotspot deps + yt-dlp + fail2ban |
| `postinstall.sh` | 152 | fail2ban config, PATH, bash completion, systemd (flag-gated) |
| `lib/common.sh` | 144 | Shared library (log/warn/err/run/spawn, dry-run aware, `load_system_env`) |
| `lib/flags.sh` | 60 | Feature flag store (set/clear/is_set/value/list/status) |
| `lib/notify.sh` | 76 | Multi-platform alerting (`notify_send`) — opt-in source, silent-fails |
| `lib/entertainment-lib.sh` | 350 | Entertainment module lib (ENABLED parsing, scheduler sync) |
| `bin/flag-reader` | 58 | Inspect flags (list/status/`--raw`) |
| `bin/flag-set` | 21 | Set a flag (optionally with a value) |
| `bin/flag-clear` | 21 | Unset a flag |
| `features/autostart.sh` | 14 | Boot-time feature (moved from `bin/`, flag-gated service) |
<!-- GEN:START filetable -->
| `bin/pos` | 277 | CLI dispatcher with smart arg matching + logging + category help |
| `bin/pos-ai-gemini` | 311 | Chat with Google Gemini (ask, chat, models, sessions) |
| `bin/pos-communication-telegram-listener` | 563 | Telegram bot listener: map /command → bash, run them on chat messages |
| `bin/pos-communication-telegram-sender` | 221 | Send Telegram messages/files/links/stickers via Bot API (send, test) |
| `bin/pos-config` | 80 | Interactive editor for the tools' runtime config (reads # POS_CONFIG: registry) |
| `bin/pos-docker-compose` | 366 | Docker Compose service manager (ls/up/down/restart/logs/update/config) |
| `bin/pos-docker-health` | 110 | One-glance container health dashboard (exits 1 if unhealthy) |
| `bin/pos-docker-ps` | 128 | Enhanced container overview (health, IPs, ports, uptime) |
| `bin/pos-docker-vbox` | 158 | Disposable Docker-based VMs (create/enter/start/stop/rm/ls) |
| `bin/pos-entertainment-config` | 99 | Show or edit the entertainment config (ENABLED auto-trigger list, weather location) |
| `bin/pos-entertainment-disable` | 32 | Disable a plugin's auto-trigger (remove it from ENABLED) |
| `bin/pos-entertainment-enable` | 49 | Enable an auto-trigger for a plugin on a schedule |
| `bin/pos-entertainment-send` | 93 | Run a public-API plugin and send its output via Telegram (default sender) |
| `bin/pos-entertainment-status` | 49 | Show enabled plugins and scheduler state |
| `bin/pos-media-mp3` | 35 | Download audio as MP3 (yt-dlp) |
| `bin/pos-media-mp4` | 38 | Download video as MP4 (interactive format select) |
| `bin/pos-network-checkport` | 45 | Check TCP port connectivity |
| `bin/pos-network-hotspot` | 93 | Wi-Fi hotspot via create_ap + wihotspot-gui |
| `bin/pos-network-ip` | 69 | Show interfaces, routes, public IP + location |
| `bin/pos-network-scan` | 271 | Parallel ping sweep of CIDR |
| `bin/pos-ssh-load-keys` | 31 | Load all SSH keys into the agent |
| `bin/pos-system-backup` | 126 | Encrypted (AES-256) folder snapshots (tar + gpg) |
| `bin/pos-system-firewall` | 291 | Interactive UFW management |
| `bin/pos-system-health` | 209 | Host health dashboard (disk, RAM, services, backup age, fail2ban, docker); exit 1 if any FAIL |
| `bin/pos-system-nfs-client` | 138 | Mount NFS shares (ephemeral or persistent systemd mount units) |
| `bin/pos-system-nfs-server` | 134 | Manage the NFS kernel server (status, share/unshare exports, enable/disable) |
| `bin/pos-tree` | 110 | Show the pos CLI command tree: categories, commands, and subcommands |
| `bin/pos-usb-server` | 218 | USB Redirector server control (--ls, --share; prompts when args omitted) |
| `completions/pos.bash` | 282 | Dynamic bash completion |
<!-- GEN:END filetable -->
| `apps/install.sh` | 171 | App install/uninstall picker/orchestrator |

---

## 14. Common Tasks for Agents

| Task | Where to Edit |
|------|---------------|
| Add a new CLI tool | Create `bin/pos-<cat>-<cmd>` with a `# POS:` header, chmod +x, add deps (apt → `preinstall.sh` PACKAGES; non-apt → `command -v` guard), then `make gen && make check` |
| Regenerate doc tables / completion flags | `make gen` (see `scripts/gen-docs.sh`; never hand-edit between `GEN:START`/`GEN:END` markers) |
| Verify repo self-consistency | `make check` (runs `scripts/check-sync.sh`; also the pre-commit hook after `make hook`)
| Add a new app installer | Create `apps/<name>.sh` (auto-discovered) |
| Add a feature | Create `features/<name>.sh` (installed on demand via `./install.sh --feature`) |
| Add a systemd service | Create `systemd/<name>.service` (auto-installed by postinstall; gate on a flag if it backs a feature) |
| Add a precompiled binary | Drop it in `x64_bin/` (or `arm64_bin/` later) — auto-copied by Phase 2 |
| Inspect/set feature flags | `flag-reader`, `flag-set`, `flag-clear` (or source `lib/flags.sh`) |
| Modify package list | Edit `PACKAGES` array in `preinstall.sh` |
| Change PATH or bash config | Edit `postinstall.sh` |
| Modify fail2ban config | Edit jail.local section in `postinstall.sh` |
| Add bash completion | Edit `completions/pos.bash` |
| Modify Docker Compose logic | Edit `bin/pos-docker-compose` |
| Modify Docker health check | Edit `bin/pos-docker-health` |
| Modify vbox (Docker VM) logic | Edit `bin/pos-docker-vbox` |
| Modify USB forwarding logic | Edit `bin/pos-usb-server` |
| Modify AI/Gemini logic | Edit `bin/pos-ai-gemini` (config scope `ai` via `pos config ai`; `AI_GEMINI_API_KEY`/`AI_GEMINI_MODEL` in `~/.config/linux_post_install/ai.env`) |
| Modify UFW/firewall logic | Edit `bin/pos-system-firewall` |
| Modify pos logging | Edit log setup in `bin/pos` |
| Modify install phases/flags | Edit arg parsing in `install.sh` |
| Update documentation | Edit the relevant doc under `DOC/` (index: `DOC/README.md`) |
| Add a secret config file | Add to `config/`, update `.gitignore`, add copy logic in `postinstall.sh` |
