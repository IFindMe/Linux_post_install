# AGENT Context — Linux_post_install Project

> **Purpose:** Single-source context document so any AI agent can understand the project, navigate the codebase, and make correct contributions.

---

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
│   ├── common.sh           # Shared library (colors, logging, spinner, timer, run)
│   └── flags.sh            # Feature flag store (flag_set/clear/is_set/value/list/status)
│
├── bin/                    # CLI tools — installed to /usr/local/bin/
│   ├── pos                 # Main dispatcher — smart arg matching to pos-* scripts
│   ├── pos-network-ip      # Show interfaces, routes, public IP + location
│   ├── pos-network-checkport  # TCP port checker
│   ├── pos-network-scan    # Parallel ping sweep of CIDR subnet
│   ├── pos-docker-ps       # Enhanced docker ps (health, IPs, ports, uptime)
│   ├── pos-docker-health   # Quick one-glance health dashboard
│   ├── pos-docker-compose  # Docker Compose service manager (largest script, 317 lines)
│   ├── pos-media-mp3       # Audio downloader (yt-dlp → MP3)
│   ├── pos-media-mp4       # Video downloader (yt-dlp → MP4, interactive format select)
│   ├── pos-system-firewall # Interactive UFW manager (menu-driven, 284 lines)
│   ├── pos-system-backup   # Encrypted folder snapshots (tar + gpg AES-256, --service) (115 lines)
│   ├── pos-ssh-load-keys   # Load SSH keys into ssh-agent
│   ├── pos-communication-telegram  # Send Telegram messages via Bot API
│   ├── pos-docker-vbox     # Disposable Docker-based "VMs" (pos docker vbox)
│   ├── pos-network-hotspot # Wi-Fi hotspot (create_ap + wihotspot-gui)
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
│       └── localsend.sh   # LocalSend (flatpak)
│
├── completions/
│   └── pos.bash            # Bash tab-completion for the pos CLI
│
├── config/
│   └── authorized_keys     # SSH public keys (gitignored)
│
├── compose/
│   └── scale-tail/         # Git submodule → ScaleTail templates (119+ services)
│
├── systemd/
│   ├── autostart.service   # Runs autostart.sh on boot
│   └── ssh-agent.service   # System-wide SSH agent socket
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
│   └─ Copies lib/common.sh + lib/flags.sh → /usr/local/bin/ (chmod 644)
│   └─ Copies x64_bin/* → /usr/local/bin/ on x86_64 (arm64_bin/ on aarch64)
│   └─ [if --feature] Copies features/* → /usr/local/bin/ (asks before overwriting),
│                      then sets the matching feature flag
│
├─ Phase 3: postinstall.sh       (runs as user)
│   └─ Configures fail2ban (SSH jail: 5 retries, 1h ban)
│   └─ PATH export in ~/.bashrc
│   └─ Bash completion for pos CLI
│   └─ Copies systemd/*.service → /etc/systemd/system/, enables them
│      (autostart.service only when the `autostart` flag is set)
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
| network | ip | `pos-network-ip` | Show interfaces, routes, public IP + location |
| network | checkport | `pos-network-checkport` | Check TCP port connectivity |
| network | scan | `pos-network-scan` | Parallel ping sweep of CIDR |
| docker | ps | `pos-docker-ps` | Enhanced container overview |
| docker | health | `pos-docker-health` | Quick health dashboard (exits 1 if unhealthy) |
| docker | compose | `pos-docker-compose` | Service manager (ls/up/down/restart/logs/update/config) |
| media | mp3 | `pos-media-mp3` | Download audio as MP3 |
| media | mp4 | `pos-media-mp4` | Download video with format select |
| system | firewall | `pos-system-firewall` | Interactive UFW management |
| system | backup | `pos-system-backup` | Encrypted folder snapshots (`tar` + gpg AES-256; `--service` picks from `/srv` and `~/srv`) |
| ssh | load-keys | `pos-ssh-load-keys` | Load SSH keys into agent |
| communication | telegram | `pos-communication-telegram` | Send Telegram messages via Bot API (`--send`, `test`, `config set`); config in `~/.config/linux_post_install/telegram.env` |
| docker | vbox | `pos-docker-vbox` | Disposable Docker "VMs" (`create/enter/start/stop/rm/ls`; label-filtered, auto-enter prompt) |

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
| `spawn "msg" cmd` | Runs with animated braille spinner, elapsed time, OK/FAIL status |
| `timer_start` / `timer_stop` | Elapsed time tracking |
| `confirm "prompt" [default]` | y/N or Y/n prompt |

**Auto-detects TTY** — disables colors when piped.

**Source pattern:**
```bash
source "$(dirname "$0")/../lib/common.sh"
```

**Scripts that do NOT source common.sh** (self-contained): `bin/pos`, `pos-network-ip`, `pos-network-checkport`, `pos-network-scan`, `pos-media-mp3`, `pos-media-mp4`, `pos-ssh-load-keys`, `pos-system-firewall`, `pos-communication-telegram`.

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

1. Create `apps/<name>.sh` following the template in DOC/DEV.md
2. It auto-appears in the interactive picker — no registration needed

---

## 8. Systemd Services

| Service | File | Purpose |
|---------|------|---------|
| `ssh-agent.service` | `systemd/ssh-agent.service` | System-wide SSH agent, socket at `/run/ssh-agent/socket` |
| `autostart.service` | `systemd/autostart.service` | Runs `autostart.sh` on boot |

All `.service` files in `systemd/` are automatically copied to `/etc/systemd/system/` and enabled by `postinstall.sh`.

---

## 9. Configuration Files

### Gitignored Secrets

- `config/rclone.conf` — rclone remote config (OAuth tokens)
- `config/authorized_keys` — SSH public keys

### Runtime Config

- `~/.config/linux_post_install/compose.env` — Docker Compose global defaults
- `~/.bashrc` — Modified by postinstall (PATH, bash completion)

### Feature Flags

System-wide flag store at `/usr/local/share/linux_post_install/flags/`:
- One file per flag; **presence = set**, **file content = optional value** (dir 755, files 644).
- Library: `lib/flags.sh` (installed as `/usr/local/bin/flags.sh`) — `flag_set <name> [value]`, `flag_clear <name>`, `flag_is_set <name>`, `flag_value <name>`, `flag_list`, `flag_status <name>`.
- CLI: `flag-reader` (list / status / `--raw`), `flag-set`, `flag-clear`.
- Set by `./install.sh --feature`; read by `postinstall.sh` to gate systemd enablement (e.g. `autostart.service` requires the `autostart` flag).
- Writes use `run` + `sudo`, so they respect `--dry-run`. `FLAGS_DIR` is env-overridable for tests.

---

## 10. Coding Conventions

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

## 11. Development Workflow

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

1. Create `bin/pos-<category>-<command>` from `templates/pos-tool.sh` — must be executable (`100755`); it auto-appears in `pos <category> --help` (filename-derived, no registration)
2. Register in `bin/pos` `usage()` CATEGORIES/EXAMPLES; add to `INTERACTIVE_CMDS` in `bin/pos` if it reads stdin
3. Add system deps to `PACKAGES` array in `preinstall.sh` (if needed)
4. Add config logic to `postinstall.sh` (if needed, with `.gitignore` for secrets); runtime tool config → `~/.config/linux_post_install/<tool>.env` (600)
5. Update docs: `DOC/POS.md` (section table + detail), `DOC/AGENT_Context_Project.md` (bin tree, dispatch table, self-contained list, file line-count table), root `README.md` only if the category list changes
6. Test: `bash -n bin/your-tool && shellcheck bin/your-tool && bin/pos help <full command> && bin/pos <category> --help`

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

## 12. Key File Quick Reference

| File | Lines | Purpose |
|------|-------|---------|
| `install.sh` | 192 | Main orchestrator — 4 phases with CLI flags, `--feature`, prebuilt arch bins |
| `preinstall.sh` | 54 | System packages + hotspot deps + yt-dlp + fail2ban |
| `postinstall.sh` | 97 | fail2ban config, PATH, bash completion, systemd (flag-gated) |
| `lib/common.sh` | 121 | Shared library |
| `lib/flags.sh` | 60 | Feature flag store (set/clear/is_set/value/list/status) |
| `bin/flag-reader` | 58 | Inspect flags (list/status/`--raw`) |
| `bin/flag-set` | 21 | Set a flag (optionally with a value) |
| `bin/flag-clear` | 21 | Unset a flag |
| `features/autostart.sh` | 14 | Boot-time feature (moved from `bin/`, flag-gated service) |
| `bin/pos` | 191 | CLI dispatcher with smart arg matching + logging + category help |
| `bin/pos-docker-compose` | 363 | Largest script — full compose management |
| `bin/pos-system-firewall` | 284 | Interactive UFW manager |
| `bin/pos-system-backup` | 115 | Encrypted folder snapshots: path mode + `--service` (`/srv`, `~/srv` picker), tar + gpg AES-256 |
| `bin/pos-docker-ps` | 127 | Enhanced container overview |
| `bin/pos-docker-health` | 109 | Quick health dashboard |
| `bin/pos-docker-vbox` | 156 | Docker-based disposable VMs (`pos docker vbox`; label-filtered, auto-enter prompt) |
| `bin/pos-network-hotspot` | 91 | Wi-Fi hotspot: `create_ap` (start with background prompt/`--foreground`, stop, status) + `wihotspot-gui` |
| `bin/pos-communication-telegram` | 138 | Telegram sender via Bot API: `--send`, `test`, `config set`; token masked; config `~/.config/linux_post_install/telegram.env` |
| `completions/pos.bash` | 122 | Dynamic bash completion |
| `apps/install.sh` | 171 | App install/uninstall picker/orchestrator |

---

## 13. Common Tasks for Agents

| Task | Where to Edit |
|------|---------------|
| Add a new CLI tool | Create `bin/pos-<cat>-<cmd>`, add deps in `preinstall.sh` |
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
| Modify UFW/firewall logic | Edit `bin/pos-system-firewall` |
| Modify pos logging | Edit log setup in `bin/pos` |
| Modify install phases/flags | Edit arg parsing in `install.sh` |
| Update documentation | Edit the relevant doc under `DOC/` (index: `DOC/README.md`) |
| Add a secret config file | Add to `config/`, update `.gitignore`, add copy logic in `postinstall.sh` |
