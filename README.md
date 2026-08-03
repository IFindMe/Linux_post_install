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
./install.sh --feature    # core + install features/ scripts (prompts on overwrite)
```

**Flags:**

| Flag | What it does |
|------|-------------|
| `--apps` | Run interactive app picker after core install |
| `--full` | Core install + all apps (no prompts) |
| `--feature` | Install `features/` scripts to `/usr/local/bin/` (asks before overwriting), sets their feature flags |
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
| opt | `./install.sh --feature` | Installs `features/` scripts (never overwrites without asking) |

---

## Features & Flags

`features/` holds scripts you're likely to customize (like `autostart.sh`), kept out of `bin/` so a plain re-install never resets them.

```bash
./install.sh --feature       # install features/ — asks before overwriting
```

- Each feature is copied to `/usr/local/bin/`; if the file already exists you're asked **"Overwrite? [y/N]"** — your existing config is kept by default.
- A successful install sets a **feature flag** at `/usr/local/share/linux_post_install/flags/` (presence = set, file content = optional value).
- Flags drive systemd: e.g. `autostart.service` is enabled only when the `autostart` flag is green.

Inspect and manage flags:

```bash
flag-reader                 # list all flags + status
flag-reader autostart       # check one flag (exit 0 if set)
flag-reader --raw autostart # print the raw value only (script-friendly)
flag-set autostart prod     # set a flag, optionally with a value
flag-clear autostart        # unset a flag
```

Any project script can `source lib/flags.sh` (or the installed `/usr/local/bin/flags.sh`) and use `flag_set`, `flag_is_set`, `flag_value`, `flag_clear`.

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
```

#### Compose (ScaleTail — 119+ self-hosted services)

Each service runs with a Tailscale sidecar and gets its own `tail-xxxxx.ts.net` URL.

**Quick start:**

```bash
# 1. Set your Tailscale auth key (required once)
pos docker compose config set TS_AUTHKEY=tskey-auth-xxxxx

# 2. Deploy a service
pos docker compose up jellyfin

# 3. Open https://jellyfin.tail-xxxxx.ts.net
```

**All commands:**

```bash
pos docker compose ls                        # List available service templates
pos docker compose installed                 # List deployed services
pos docker compose up jellyfin               # Deploy or start a service
pos docker compose down actual-budget        # Stop a service
pos docker compose logs home-assistant -f    # Tail logs
pos docker compose restart home-assistant    # Restart a service
pos docker compose update                    # Pull latest templates + refresh deployed compose files
pos docker compose config                    # Show current configuration
pos docker compose config set TZ=Asia/Tokyo  # Set a global default
pos docker compose config edit               # Open config in editor
```

**Config strategy — three layers:**

| Layer | File | Purpose |
|-------|------|---------|
| Template defaults | `/usr/local/share/linux_post_install/scale-tail/services/<name>/.env` | Per-service defaults from ScaleTail |
| Global config | `~/.config/linux_post_install/compose.env` | Your defaults — applies to all services |
| Per-service | `/srv/<service>/.env` | Actual config — created on first deploy, **never overwritten** |

Set global defaults once, then every `up` fills them into the new service's `.env`.

**Paths:**

- Templates: `/usr/local/share/linux_post_install/scale-tail/services/`
- Deployments: `/srv/<service>/` (configurable via `SERVICES_BASE`)
- Global config: `~/.config/linux_post_install/compose.env`

**Config keys:**

| Key | What it does |
|-----|-------------|
| `TS_AUTHKEY` | Tailscale auth key (required for sidecar networking) |
| `TZ` | Timezone for the service |
| `DNS_SERVER` | Custom DNS server |
| `SERVICES_BASE` | Where services are deployed (default: `/srv`)

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

Install with `./apps/install.sh` (interactive), `./apps/install.sh --all`, or by name.
Uninstall the same way with `--uninstall`:

```bash
./apps/install.sh --uninstall                  # interactive uninstall selection
./apps/install.sh --uninstall --all            # uninstall everything
./apps/install.sh --uninstall brave vscode     # uninstall specific apps
```

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
