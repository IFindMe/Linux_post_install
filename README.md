# Linux_post_install — Personal Bootstrap & Homelab Toolkit

> One command turns a bare Debian/Ubuntu install into a fully productive machine.

---

## What Is This

After reinstalling Linux, you usually need to install packages, set up SSH, configure the firewall, and install apps. This repo automates all of that in one go.

**What you get:**

- **25+ system packages** installed automatically (git, curl, tmux, ufw, fail2ban, etc.)
- **Unified `pos` CLI** — one command for network, Docker, media, system, and SSH tasks
- **119+ self-hosted services** via ScaleTail + Tailscale (Jellyfin, Home Assistant, etc.)
- **15 optional desktop apps** (VS Code, Docker Desktop, Brave, OBS, etc.) — pick what you want
- **systemd services** for SSH agent and boot-time automation
- **Everything in `/usr/local/bin/`** — you can delete the repo after install

---

## Quick Start

```bash
git clone https://gitea.skink-platy.ts.net/admin/Linux_post_install.git
cd Linux_post_install
./install.sh              # core: packages + CLI + services + ScaleTail
./install.sh --apps       # core + interactive app picker
./install.sh --full        # core + all apps (non-interactive)
```

**Flags:**

| Flag | What it does |
|------|-------------|
| `--apps` | Run interactive app picker after core install |
| `--full` | Core install + all apps (no prompts) |
| `--dry-run` | Preview without executing anything |
| `--skip <phase>` | Skip a phase (repeatable): `preinstall`, `scripts`, `postinstall`, `scalepoint` |
| `--steps <spec>` | Run specific phases only, e.g. `--steps 1,3` or `--steps 1-3` |
| `--no-color` | Disable colored output |

---

## What Gets Installed

| Phase | Script | What happens |
|-------|--------|-------------|
| 1 | `preinstall.sh` | `apt update` + 25+ packages + yt-dlp + fail2ban |
| 2 | `install.sh` | Copies all `bin/` tools to `/usr/local/bin/` |
| 3 | `postinstall.sh` | Configures fail2ban, SSH agent, PATH, bash completion, systemd services |
| 4 | ScaleTail clone | Downloads 119+ Docker Compose templates with Tailscale sidecar |
| 5 (opt) | `apps/install.sh` | Installs desktop apps you select |

---

## The `pos` CLI

After install, use the `pos` command for everything:

```bash
pos                          # list available categories
pos help network             # help for a specific category
```

### Network

```bash
pos network ip                               # Show interfaces, routes, public IP
pos network checkport 192.168.1.1:80         # Check if a TCP port is open
pos network scan 192.168.8.0/24              # Fast parallel ping sweep
```

### Docker

```bash
pos docker ps                                # List containers with health, IPs, ports
pos docker health                            # Health dashboard (exits 1 if unhealthy)
pos docker compose ls                        # List 119+ available services
pos docker compose up jellyfin               # Deploy with Tailscale HTTPS
pos docker compose down actual-budget        # Stop a stack
pos docker compose logs home-assistant -f    # Tail logs
pos docker compose update                    # Pull latest templates
pos docker compose config set TS_AUTHKEY=x   # Set global defaults
```

**First run with compose:**

```bash
pos docker compose config set TS_AUTHKEY=tskey-auth-xxxxx
pos docker compose up jellyfin
# Open https://jellyfin.tail-xxxxx.ts.net
```

Services are deployed to `/srv/<service>/` by default.

### VBox (disposable Docker containers)

```bash
pos vbox create lab1                         # Create — prompts to enter
pos vbox create lab1 --dir .                 # Bind mount current directory
pos vbox enter lab1                          # Auto-starts if stopped
pos vbox ls                                  # List vbox containers only
pos vbox stop/start/rm lab1
```

### Media

```bash
pos media mp3 https://youtube.com/watch?v=...    # Audio → MP3
pos media mp4 https://youtube.com/watch?v=...    # Video with format selection
```

### System

```bash
sudo pos system firewall                     # Interactive UFW manager
```

### SSH

```bash
pos ssh load-keys                            # Load all SSH keys into agent
```

The `ssh-agent.service` runs at boot. `SSH_AUTH_SOCK` is set in `~/.bashrc`.

### Legacy wrappers

These still work and forward to `pos`: `wr-ip`, `wr-checkport`, `wr-scan-ping`, `wr-docker`, `wr-compose`, `wr-ufw`, `mp3`, `mp4`, `vbox`, `ssh-load-all`.

---

## Optional Apps

Install with `./apps/install.sh` (interactive), `./apps/install.sh --all`, or by name:

| Category | Apps |
|----------|------|
| Browsers | Brave |
| Development | opencode, VS Code |
| Media | OBS Studio, scrcpy, VLC |
| Networking | NetBird, Tailscale, ZeroTier |
| Remote Access | Termius, VNC Viewer |
| System | Docker Engine, QEMU + KVM |
| Utilities | AFFiNE, btop, LocalSend |

---

## Development

See [DEV.md](DEV.md) for architecture, conventions, and how to add or modify tools.
