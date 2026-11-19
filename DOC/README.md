# Documentation

Everything in this folder is reference material for the `Linux_post_install` project. The root [README](../README.md) is the short intro + quick start; this folder holds the detail.

| Document | What it covers |
|----------|----------------|
| [HOWTO.md](HOWTO.md) | Hands-on guides per category (network, docker, system): flags, recipes, config, troubleshooting |
| [SCRIPTS.md](SCRIPTS.md) | Core installer scripts: `install.sh`, `preinstall.sh`, `postinstall.sh`, `lib/common.sh`, `lib/flags.sh` — purpose, how each works, configuration |
| [POS.md](POS.md) | The `pos` CLI: dispatcher, every `pos-*` command, flag CLIs |
| [APPS.md](APPS.md) | Optional apps: `apps/install.sh` picker, installer conventions, full app catalog |
| [DEV.md](DEV.md) | Developer guide: architecture, conventions, how to add tools/apps, commit guidelines |
| [AGENT_Context_Project.md](AGENT_Context_Project.md) | Single-source context doc for coding agents working on the repo |
| [algorithm.md](algorithm.md) | ASCII diagrams: install flow, `pos` dispatch, logging, vbox lifecycle |

## Quick navigation

- Just installed and want to use it? → [POS.md](POS.md)
- Adding a package? → [SCRIPTS.md → preinstall.sh](SCRIPTS.md#preinstallsh--system-packages)
- Adding a CLI tool or app? → [DEV.md](DEV.md)
