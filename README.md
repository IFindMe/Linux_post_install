# Linux_post_install — Personal Bootstrap & Homelab Toolkit

> One command turns a bare Debian/Ubuntu install into a fully productive machine.

## What is this

After reinstalling Linux you usually need to install packages, set up SSH, configure a firewall, and install apps. This repo automates all of that in one go.

It is a **personal toolkit** — a bootstrap script, a unified `pos` CLI for everyday tasks, and optional app installers.

**What you get:**

- 25+ system packages installed automatically
- The `pos` CLI: network, Docker (vbox VMs), and system tools
- Wi-Fi hotspot tools (`create_ap`, `wihotspot-gui`) via `pos network hotspot`
- `pos tree` — browse the whole CLI: categories, commands, and subcommands
- 16 optional desktop apps (VS Code, Brave, OBS, Tailscale, …) — pick what you want
- Everything lands in `/usr/local/bin/` — you can delete the repo after install

## Quick Start

```bash
git clone https://gitea.skink-platy.ts.net/admin/Linux_post_install.git
cd Linux_post_install
./install.sh              # core: packages + CLI
./install.sh --apps       # also install optional desktop apps (interactive)
```

| Flag | What it does |
|------|-------------|
| `--apps` | Interactive app picker after core install |
| `--full` | Core install + all apps (non-interactive) |
| `--dry-run` | Preview without executing |
| `--force` | Re-install even if the version matches |
| `--skip <phase>` | Skip a phase: `preinstall`, `scripts`, `postinstall`, `apps` |
| `--steps <spec>` | Run only specific phases, e.g. `--steps 1,3` |
| `--no-color` | Disable colored output |

## Documentation

| Topic | Where |
|-------|-------|
| Docs index | [DOC/README.md](DOC/README.md) |
| `pos` HOW-TO guides (recipes + troubleshooting) | [DOC/HOWTO.md](DOC/HOWTO.md) |
| Core scripts (installer, libs) — how they work | [DOC/SCRIPTS.md](DOC/SCRIPTS.md) |
| `pos` CLI reference (all commands) | [DOC/POS.md](DOC/POS.md) |
| Optional apps (picker + full catalog) | [DOC/APPS.md](DOC/APPS.md) |
| Developer guide (add tools/apps) | [DOC/DEV.md](DOC/DEV.md) |
| Algorithm diagrams | [DOC/algorithm.md](DOC/algorithm.md) |
