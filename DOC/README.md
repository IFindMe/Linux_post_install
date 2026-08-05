# Documentation

Everything in this folder is reference material for the `Linux_post_install` project. The root [README](../README.md) is the short intro + quick start; this folder holds the detail.

| Document | What it covers |
|----------|----------------|
| [SCRIPTS.md](SCRIPTS.md) | Core installer scripts: `install.sh`, `preinstall.sh`, `postinstall.sh`, `lib/common.sh`, `lib/flags.sh`, `lib/entertainment-lib.sh`, `features/autostart.sh` — purpose, how each works, configuration |
| [POS.md](POS.md) | The `pos` CLI: dispatcher, every `pos-*` command, Docker Compose / ScaleTail config, legacy wrappers, flag CLIs |
| [APPS.md](APPS.md) | Optional apps: `apps/install.sh` picker, installer conventions, full app catalog |
| [SYSTEMD.md](SYSTEMD.md) | Systemd units (`autostart.service`, `ssh-agent.service`), feature-flag gating, bash completion |
| [DEV.md](DEV.md) | Developer guide: architecture, conventions, how to add tools/apps/features, commit guidelines |
| [AGENT_Context_Project.md](AGENT_Context_Project.md) | Single-source context doc for AI agents working on the repo |
| [algorithm.md](algorithm.md) | ASCII diagrams: install flow, `pos` dispatch, compose `up`, config cascade, logging, vbox lifecycle |

## Quick navigation

- Just installed and want to use it? → [POS.md](POS.md)
- Adding a package? → [SCRIPTS.md → preinstall.sh](SCRIPTS.md#preinstallsh--system-packages)
- Adding a CLI tool or app? → [DEV.md](DEV.md)
- First deploy of a self-hosted service? → [POS.md → Docker Compose](POS.md#docker-compose--scaletail)
