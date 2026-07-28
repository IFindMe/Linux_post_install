# myLinux — Personal Bootstrap & Homelab Toolkit

> One command to turn a bare Debian/Ubuntu install into a usable machine.

```
 Clone          Install          Pre           Wrapper Scripts          Post
───────▶  ───────────▶  ───────────────────▶  ──────────────────▶  ────────────────▶
 git clone   ./install.sh   apt packages       bin/ → /usr/local   SSH, rclone, svc
```

---

## Quick Start

```bash
git clone https://github.com/IFindMe/myLinux.git
cd myLinux
./install.sh              # core bootstrap + ScaleTail templates
./install.sh --apps        # core + interactive app picker
./install.sh --full        # core + all apps (non-interactive)
```

**Advanced flags:**

```bash
./install.sh --skip postinstall --skip scalepoint   # skip specific phases
./install.sh --steps 1,3                            # run only phases 1 and 3
./install.sh --no-color                             # disable colored output
./install.sh --apps --dry-run                       # preview without executing
```

The machine returns to a productive state with minimal manual work. The installer copies all tools to `/usr/local/bin/` and clones ScaleTail templates to `/usr/local/share/mylinux/` — you can delete the repo after install, everything still works.

---

## What It Does

| Step | Script | What Happens |
|------|--------|--------------|
| 1 | `preinstall.sh` | apt update + installs 25+ system packages + yt-dlp + fail2ban |
| 2 | `install.sh` | copies all `bin/` scripts to `/usr/local/bin` |
| 3 | `postinstall.sh` | configures fail2ban, systemd services, PATH, bash completion |
| 4 | `apps/install.sh` | *(optional)* desktop apps installed via `--apps` or `--full` |

---

## Repository Structure

```
myLinux/
├── apps/                 # Optional desktop applications (by category)
│   ├── install.sh        # Interactive selector (y/n per app)
│   ├── browsers/
│   │   └── brave.sh      # Brave Browser
│   ├── development/
│   │   ├── opencode.sh   # opencode AI coding agent
│   │   └── vscode.sh     # VS Code
│   ├── media/
│   │   ├── obs.sh        # OBS Studio
│   │   ├── scrcpy.sh     # Android screen mirroring
│   │   └── vlc.sh        # VLC media player
│   ├── networking/
│   │   ├── netbird.sh    # NetBird VPN
│   │   ├── tailscale.sh  # Tailscale VPN
│   │   └── zerotier.sh   # ZeroTier VPN
│   ├── remote-access/
│   │   ├── termius.sh    # Termius SSH client
│   │   └── vnc-viewer.sh # TigerVNC Viewer
│   ├── system/
│   │   ├── docker.sh     # Docker Engine + group setup
│   │   └── qemu.sh       # QEMU + libvirt + KVM
│   └── utilities/
│       ├── affine.sh     # AFFiNE knowledge base
│       ├── btop.sh       # Resource monitor
│       └── localsend.sh  # LocalSend file sharing
├── bin/                  # Unified CLI + wrappers (installed to /usr/local/bin)
│   ├── pos               # Main dispatcher — pos <category> <cmd>
│   ├── pos-network-*     # pos network {ip,checkport,scan}
│   ├── pos-docker-*      # pos docker {ps,health,compose}
│   ├── pos-media-*       # pos media {mp3,mp4}
│   ├── pos-ssh-load-keys # pos ssh load-keys
│   ├── pos-system-firewall # pos system firewall
│   ├── pos-vbox          # pos vbox {create,enter,stop,start,rm,ls}
│   ├── wr-*  → pos       # Backward-compat wrappers
│   ├── mp3/mp4 → pos     # Backward-compat wrappers
│   ├── vbox → pos        # Backward-compat wrapper
│   ├── ssh-load-all → pos# Backward-compat wrapper
│   └── autostart.sh      # Boot-time script (via systemd)
<<<<<<< HEAD
├── config/
│   ├── authorized_keys   # SSH public keys (read by postinstall)
│   └── rclone.conf       # rclone Google Drive config (gitignored)
=======
├── config/                 # User config files (gitignored)
│   ├── authorized_keys     # SSH public keys (gitignored — add your own)
│   └── rclone.conf         # rclone config (gitignored — add your own)
>>>>>>> bba577c (Initial commit)
├── lib/
│   └── common.sh         # Shared library (colors, logging, spinner, timer)
├── systemd/
│   ├── autostart.service # Runs autostart.sh on boot
│   └── ssh-agent.service # SSH agent system service
├── install.sh            # Main installer (orchestrator)
├── preinstall.sh         # Package installation
├── postinstall.sh        # User configuration
├── .gitignore            # Prevents secrets from being committed
├── DEV.md                # Development guide
└── README.md             # This file
```

---

## Tools Reference

All tools are accessible via the unified `pos` CLI. Backward-compatible wrappers (`wr-*`, `mp3`, `mp4`, `vbox`, `ssh-load-all`) still work — they forward to `pos` transparently.

```bash
pos                          # Show available categories
pos help <category>          # Show help for a specific command
```

### Network

```bash
pos network ip                                      # Show interfaces, routes, public IP
pos network checkport 192.168.1.1:80                # Check if a TCP port is open
pos network scan 192.168.8.0/24                     # Fast parallel ping sweep
```

### Docker

```bash
pos docker ps                                       # Enhanced container overview (health, IPs, ports)
pos docker health                                   # Quick one-glance health dashboard (exits 1 if unhealthy)

pos docker compose ls                               # List 119+ ScaleTail services
pos docker compose up jellyfin                      # Deploy with Tailscale sidecar HTTPS
pos docker compose down actual-budget               # Stop a stack
pos docker compose logs home-assistant -f            # Tail logs
pos docker compose update                           # Pull latest ScaleTail + refresh compose files
pos docker compose config set TS_AUTHKEY=...         # Set global defaults
```

First-run flow for compose:
```bash
pos docker compose config set TS_AUTHKEY=tskey-auth-xxxxx
pos docker compose up jellyfin
# Open https://jellyfin.tail-xxxxx.ts.net
```

| Command | What it does |
|---------|-------------|
| `pos docker compose ls` | List all 119 ScaleTail services |
| `pos docker compose up <service>` | Copy service → `SERVICES_BASE/<service>/`, create `config/` + `data/`, fill `.env`, `docker compose up -d` |
| `pos docker compose down <service>` | Stop a stack |
| `pos docker compose logs <service>` | View container logs |
| `pos docker compose update` | `git pull` ScaleTail templates + refresh `compose.yaml` (preserves `.env`) |
| `pos docker compose config` | Show/edit global defaults (`TS_AUTHKEY`, `TZ`, `DNS_SERVER`, `SERVICES_BASE`) |

Services are deployed with a standard layout under `SERVICES_BASE` (default `/srv`):
```
/srv/<service>/
├── compose.yaml     # Refreshed by update (preserves .env)
├── .env             # Your config
├── config/
└── data/
```

```bash
pos vbox create lab1                                # Create — asks "Enter now?" after
pos vbox create lab1 --dir .                        # Bind current directory
pos vbox enter lab1                                 # Auto-starts if stopped
pos vbox ls                                         # Only shows vbox-managed containers
pos vbox stop/start/rm lab1
```

### Media

```bash
pos media mp3 https://youtube.com/watch?v=...       # Audio → MP3 with thumbnail + metadata
pos media mp4 https://youtube.com/watch?v=...        # Video with interactive format selection
```

### System

```bash
sudo pos system firewall                            # Interactive UFW management (menu-driven)
```

```
==============================
   UFW POWER — human friendly
==============================
1) Add rule (port/service/ip/directional)
2) Delete rule (by number or text)
3) Show status (simple / verbose / numbered)
4) Enable UFW
...
```

### SSH

```bash
pos ssh load-keys                                   # Load all SSH keys into ssh-agent
```

The `ssh-agent.service` runs at boot socket at `/run/ssh-agent/socket`. `SSH_AUTH_SOCK` is set in `~/.bashrc`.

### Autostart

#### `autostart.sh`
Runs at boot via systemd. Customize it with commands you want executed on every startup.

---

## Pre-install (Packages)

Installed by `preinstall.sh`:

| Category | Packages |
|----------|----------|
| Essentials | git, curl, wget, ca-certificates, gnupg |
| Editors | vim, nano |
| Terminal | tmux, tree, htop, btop |
| Network | net-tools, iputils-ping, traceroute, tcpdump, nmap |
| Firewall | ufw, fail2ban |
| Compression | unzip, zip, rsync |
| Dev | python3, python3-pip, jq |
| Cloud | rclone |
| Media | yt-dlp (latest from GitHub) |
| SSH | openssh-client, openssh-server |

---

## Post-install (Configuration)

Applied by `postinstall.sh`:

- **SSH agent** — enables `ssh-agent.service`, sets `SSH_AUTH_SOCK` in `~/.bashrc`
- **rclone config** — copies rclone remote configuration if present
- **PATH** — ensures `/usr/local/bin` is in `~/.bashrc`
- **Bash completion** — tab completion for the `pos` CLI
- **systemd services** — enables and starts all `systemd/*.service` units

---

## Goal

After reinstalling Debian or Ubuntu:

```bash
git clone https://github.com/IFindMe/myLinux.git
cd myLinux
./install.sh
```

The machine should return to a usable state with minimal manual configuration.

---

## Optional Apps

Install individual apps via `apps/install.sh` or batch with `--apps` (interactive) / `--full` (all):

### Browsers
| App | Method | Script |
|-----|--------|--------|
| Brave Browser | APT repo | `apps/browsers/brave.sh` |

### Development
| App | Method | Script |
|-----|--------|--------|
| opencode | official install script | `apps/development/opencode.sh` |
| VS Code | Microsoft APT repo | `apps/development/vscode.sh` |

### Media
| App | Method | Script |
|-----|--------|--------|
| OBS Studio | apt package | `apps/media/obs.sh` |
| scrcpy | GitHub release (prebuilt) | `apps/media/scrcpy.sh` |
| VLC | apt package | `apps/media/vlc.sh` |

### Networking / VPN
| App | Method | Script |
|-----|--------|--------|
| NetBird | official install script | `apps/networking/netbird.sh` |
| Tailscale | APT repo | `apps/networking/tailscale.sh` |
| ZeroTier | curl install script | `apps/networking/zerotier.sh` |

### Remote Access
| App | Method | Script |
|-----|--------|--------|
| Termius | .deb package (official) | `apps/remote-access/termius.sh` |
| VNC Viewer (TigerVNC) | apt package | `apps/remote-access/vnc-viewer.sh` |

### System / Virtualization
| App | Method | Script |
|-----|--------|--------|
| Docker Engine | get.docker.com + usermod | `apps/system/docker.sh` |
| QEMU + libvirt + KVM | apt + usermod groups | `apps/system/qemu.sh` |

### Utilities
| App | Method | Script |
|-----|--------|--------|
| AFFiNE | AppImage (GitHub releases) | `apps/utilities/affine.sh` |
| btop | apt package | `apps/utilities/btop.sh` |
| LocalSend | flatpak (flathub) | `apps/utilities/localsend.sh` |

---

## Shared Library

`lib/common.sh` provides consistent output helpers used by all scripts:

- `log`, `warn`, `err`, `ok` — status messages
- `section`, `step` — section headers and progress
- `run` — executes with `set -x` tracing, respects `DRY_RUN`
- `spawn` — runs with animated spinner, supports `confirm`
- `timer_start`, `timer_stop` — elapsed time tracking

```bash
source "$(dirname "$0")/lib/common.sh"
section "Setting up..."
spawn "Installing package" sudo apt install -y some-package
ok "Done in ${ELAPSED}s"
```

---

## Development

See [DEV.md](DEV.md) for architecture, conventions, and how to add or modify tools.
