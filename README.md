# Linux_post_install — Personal Bootstrap & Homelab Toolkit

> One command turns a bare Debian/Ubuntu install into a fully productive machine.

## What is this

After reinstalling Linux you usually need to install packages, set up SSH, configure a firewall, and install apps. This repo automates all of that in one go.

It is a **personal toolkit** — a bootstrap script, a unified `pos` CLI for everyday tasks, optional app installers, and self-hosted services via ScaleTail + Tailscale.

**What you get:**

- 25+ system packages installed automatically
- The `pos` CLI: network, Docker, media, system, SSH, communication (Telegram), and vbox tools
- Wi-Fi hotspot tools (`create_ap`, `wihotspot-gui`) via `pos network hotspot`
- 15 optional desktop apps (VS Code, Brave, OBS, Tailscale, …) — pick what you want
- 119+ self-hosted services with Tailscale access (Jellyfin, Home Assistant, …)
- systemd services for SSH agent and boot-time automation
- Everything lands in `/usr/local/bin/` — you can delete the repo after install

## Quick Start

```bash
git clone https://gitea.skink-platy.ts.net/admin/Linux_post_install.git
cd Linux_post_install
./install.sh              # core: packages + CLI + services + ScaleTail
./install.sh --feature    # also install features/ scripts (asks before overwriting)
./install.sh --apps       # also install optional desktop apps (interactive)
```

| Flag | What it does |
|------|-------------|
| `--feature` | Install `features/` scripts to `/usr/local/bin/`, sets their flags |
| `--apps` | Interactive app picker after core install |
| `--full` | Core install + all apps (non-interactive) |
| `--dry-run` | Preview without executing |
| `--skip <phase>` | Skip a phase: `preinstall`, `scripts`, `postinstall`, `scalepoint`, `apps` |
| `--steps <spec>` | Run only specific phases, e.g. `--steps 1,3` |
| `--no-color` | Disable colored output |

## Documentation

| Topic | Where |
|-------|-------|
| Docs index | [DOC/README.md](DOC/README.md) |
| Core scripts (installer, libs, features) — how they work + config | [DOC/SCRIPTS.md](DOC/SCRIPTS.md) |
| `pos` CLI reference (all commands, compose config, wrappers) | [DOC/POS.md](DOC/POS.md) |
| Optional apps (picker + full catalog) | [DOC/APPS.md](DOC/APPS.md) |
| Systemd services & bash completion | [DOC/SYSTEMD.md](DOC/SYSTEMD.md) |
| Developer guide (add tools/apps/features) | [DOC/DEV.md](DOC/DEV.md) |
| Algorithm diagrams | [DOC/algorithm.md](DOC/algorithm.md) |
