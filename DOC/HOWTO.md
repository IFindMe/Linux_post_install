# `pos` HOW-TO Guides

Hands-on, copy-paste guides for every `pos` category. These are the **tutorial**
layer: flags, examples, configuration, recipes, and troubleshooting. For the
authoritative one-line reference (every command + flag), see
[DOC/POS.md](POS.md).

## Quick start — pick your category

| Category | What you can do | Guide |
|----------|-----------------|-------|
| `pos network` | IP info, hotspot, scan, port check | [network](howto/network.md) |
| `pos docker` | Container dashboards, disposable VMs | [docker](howto/docker.md) |
| `pos system` | Backups, command bank, firewall, health dashboard, uninstall | [system](howto/system.md) |

Every tool is `bin/pos-<category>-<command>`; run `pos <category> --help` to
list a category, and any tool's `--help`/`--help`-style usage for full flags.

## Cross-cutting concepts (read once)

These apply to several categories at once.

### Config files — `~/.config/linux_post_install/`

Tools that need user settings read plain environment variables. Export them in
the environment or put them in a hand-written `<name>.env` file here
(`chmod 600`, never committed); an already-exported env var always wins. There
is no config editor and no shipped template — write the file yourself.

| File | Used by | Keys (examples) |
|------|---------|-----------------|
| `system.env` | `pos system health`, `pos system backup` | `BACKUP_SERVICE_ROOTS`, `HEALTH_BACKUP_MAX_AGE_DAYS`, `BACKUP_USB_ROOT`, … |

### Scheduling

pos ships no scheduler — nothing it installs runs on a timer by itself. If you
want an automatic run, use your own service-manager timer or crontab:

- **Daily health report** — a user crontab line like `0 8 * * * pos system health`
  (console-only; redirect the output to a file if you want a record). See [system](howto/system.md).

### Gotcha: run from anywhere

`install.sh` copies `bin/pos*` + `lib/*` to `/usr/local/bin`, so `pos` works
after the repo is deleted. After pulling new changes, re-run `./install.sh` (or
just copy the changed `bin/`/`lib/` files) to refresh the installed copies.

## How the guides relate to `DOC/POS.md`

- **`DOC/POS.md`** = reference. One table row per command, full flag lists,
  config strategy. Use it when you need the exact flag.
- **This guide set** = how-to. Examples, recipes, config walk-throughs, and
  troubleshooting, linking back to POS.md rather than duplicating it.
