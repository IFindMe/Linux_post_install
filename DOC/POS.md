# `pos` CLI Reference

`pos` is the unified command-line interface installed to `/usr/local/bin/`. Every tool is a small script in `bin/` with a `pos-<category>-<command>` name. This document explains the dispatcher and every command.

- [The dispatcher — `bin/pos`](#the-dispatcher--binpos)
- [Logging behavior](#logging-behavior)
- [Commands](#commands)
  - [network](#network)
  - [docker](#docker)
  - [system](#system)
  - [flags](#flags)
  - [tree](#tree)

---

## The dispatcher — `bin/pos`

**Purpose:** turn `pos <category> <command> [args]` into a call to the matching `pos-*` script.

### How it works

`pos` scans its own directory for executable `pos-*` files and tries **variable-length argument matching**, longest first. For `pos system bank alias remove work`:

```
tries pos-system-bank-alias-remove   (not found)
tries pos-system-bank-alias          (found) → runs with args "remove work"
```

`pos help <full command>` runs that tool's `--help` (e.g. `pos help system bank`, `pos help system backup` — the words are joined with dashes). `pos <category>` and `pos <category> --help` list that category's subcommands (derived from `bin/pos-<category>-*` filenames, no script execution). Running `pos` with no args prints the built-in usage text (which doubles as the category cheat-sheet).

---

## Logging behavior

Every non-interactive `pos` invocation logs to `~/.local/share/linux_post_install/logs/`:

- Per-command files: `YYYYMMDD_HHMMSS_pos_<args>.log` (full stdout + stderr).
- `pos.log`: one line per invocation — command, log file, exit code.
- **Interactive** commands (`pos system firewall`, `pos system backup`) only log the invocation, not their output.

---

## Commands

Category-less tools (`tree`) live outside any category and are documented in their own `###` sections below.

### network

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos network ip` | `bin/pos-network-ip` | Show interfaces, default route, public IP + location | None. Public IP via `https://ifconfig.me`; location via `ip-api.com` (5s timeouts) |
| `pos network checkport <ip:port>` | `bin/pos-network-checkport` | Check if a TCP port is open | None. Uses `/dev/tcp` with a 2s timeout; exit 0/1 via OPEN/CLOSED |
| `pos network scan <cidr> [--full] [--retries N]` | `bin/pos-network-scan` | Two-phase nmap scan | See below |
| `pos network hotspot [cmd]` | `bin/pos-network-hotspot` | Wi-Fi hotspot via `create_ap` (CLI) or `wihotspot-gui` (GUI) | Uses the precompiled binaries from `x64_bin/`; see below |

**`pos network scan` in detail:**

- Phase 1 — fast host discovery (`nmap -sn -T5`), prints the live host list.
- Phase 2 (only with `--full`) — service/version scan (`-sV -sC`), plus OS detection and NSE scripts if run with privileges; shows ports, OS, SSH host keys, HTTP titles, NetBIOS info.
- Accepts a bare IP (treated as `/32`) or a CIDR.
- Auto-raises to `sudo nmap` when possible (root, passwordless sudo, or an interactive terminal with `--full`).
- `--retries N` tunes discovery retries (default 1).

**`pos network hotspot` in detail:**

Backed by the precompiled binaries shipped in `x64_bin/` (see [SCRIPTS.md → x64_bin/](SCRIPTS.md#x64_bin--precompiled-binaries)). Needs root for the CLI commands (uses `sudo`):

| Command | Behavior |
|---------|----------|
| `pos network hotspot` | Launches the `wihotspot-gui` (GTK3 GUI) |
| `pos network hotspot start <wifi-iface> [<internet-iface>] <ssid> [<passphrase>]` | Asks whether to run in the background; `y` starts `create_ap --daemon` (logs to `/var/log/linux_post_install_hotspot.log`), `n` runs in the foreground (blocks until Ctrl+C) |
| `pos network hotspot start --foreground <wifi-iface> [<internet-iface>] <ssid> [<passphrase>]` | Skips the prompt, runs in the foreground |
| `pos network hotspot stop [<id>]` | Stops the running access point via `create_ap --stop`; `<id>` is an interface name or PID, auto-detected if omitted |
| `pos network hotspot status` | Runs `create_ap --list-running` |

### docker

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos docker ps` | `bin/pos-docker-ps` | Enhanced container list: name, image, health, uptime, IPs, ports, ID, plus a healthy/unhealthy summary | None. Requires Docker + Python 3 |
| `pos docker health` | `bin/pos-docker-health` | One-glance health dashboard; **exits 1** if any container is unhealthy | None. Checks all containers including stopped ones |
| `pos docker stack [-a]` | `bin/pos-docker-stack` | Containers grouped by compose stack (project); `-a` includes stopped; non-compose containers under `Standalone` | None. Requires Docker |

**`pos docker stack [-a|--all]`** — containers grouped by their Docker Compose project (stack). Each stack is a section (project name, sorted) whose lines show container name, status, and port mappings (`-` when none). Containers with no compose project land in a `Standalone` section at the end. Default shows running containers; `-a|--all` includes stopped/exited (like `docker ps -a`). Status is colored when output goes to a terminal: `Up*` green, `Exited*`/`Dead*`/`Created*` red, `Paused*`/`Restarting*` yellow. Ends with a summary line (`Stacks: N  containers: N  standalone: N`); exit 0 even when no containers exist.

#### Docker vbox

**File:** `bin/pos-docker-vbox`
**Purpose:** manage disposable Docker containers as lightweight "VMs". Each container gets a bind-mounted host directory so files persist after the container is removed. Containers carry the label `linux_post_install.vbox=true`.

| Command | Behavior |
|---------|----------|
| `pos docker vbox create <name> [image] [--dir <path>]… [--device </dev/node>]… [--gpu] [--port H:C]… [--cpus N] [--memory SIZE] [--network MODE]` | Creates a container from `ubuntu:22.04` (or the given image), bind-mounting `~/<name>` (or the first `--dir`; repeatable for extra same-path mounts) as the working directory; optional flags add GPU (`--gpus all`), device passthrough, port publishes and cpu/memory limits; prompts to enter immediately |
| `pos docker vbox enter <name>` | Shell into the container (auto-starts it if stopped); detects the working dir from the container mounts |
| `pos docker vbox start/stop/rm <name>` | Start, stop, or force-remove the container |
| `pos docker vbox ls` | List vbox containers only (label filter) |

**`pos docker vbox menu`** — bare invocation on a terminal (or the explicit `menu` subcommand) opens an interactive hub wrapping these verbs: list, create (categorized flow: name → category hub with live basket counts — image quick-picks, GPU/Nvidia with automatic toolkit/device-node detection, host devices, dir mounts, ports, CPU/RAM → review screen rendering the exact `docker create` plan before anything runs; 'n' returns to the hub with edits preserved), enter (hands the terminal to the container shell — `exit` returns to the menu), start/stop (pick a VM), and remove (y/N confirm naming the VM; `rm -f` removes the container, the host folder is kept). Arguments stay scriptable; without a terminal the menu fails closed with a pointer to these subcommands.

### system

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `sudo pos system firewall` | `bin/pos-system-firewall` | Interactive UFW ("UFW POWER") menu: add/delete rules, status, enable/disable/reset, default policies | Must run as root. Every command is previewed and confirmed before execution; supports `--dry-run`; keeps a history of executed commands |
| `pos system backup <folder-path>` | `bin/pos-system-backup` | Create a gpg-encrypted (AES-256) `tar.gz` snapshot of a folder and verify it | Prompts twice for a password (never stored; the passphrase is fed to gpg on an internal fd — `--passphrase-fd`, never via argv, so it cannot leak through `ps`). Uses `sudo tar`; needs `gnupg` (in `preinstall.sh` PACKAGES) only when encrypting. Artifact `<name>_<date>.tar.gz[.gpg]` in the current directory, `chmod 600`; `--no-encrypt` (or `BACKUP_ENCRYPT=0`) keeps a plain `.tar.gz` with no password prompt (headless/cron safe). Once the archive verifies, connected USB storage is offered (detected via `lsblk` TRAN with `lsusb`/by-id cross-check; unmounted sticks get a mount offer first — see `DOC/howto/system.md`; or pinned with `BACKUP_USB_ROOT`): the copy lands in `<usb>/backups/` and is proven 100% by sha256 before it is reported. Bare invocation on a terminal (or the `menu` subcommand) opens an interactive menu wrapping these modes (encrypted backup with typed folder, encrypted backup picked from the service roots, unencrypted variant) — each runs only after an explicit y/N confirm naming the folder; arguments stay scriptable |
| `pos system backup --service` | `bin/pos-system-backup` | Lists folders under `/srv` and `~/srv`, lets you pick one, then runs the same backup | Roots via `BACKUP_SERVICE_ROOTS` (space-separated, default `/srv $HOME/srv`), set in the environment or a hand-written `~/.config/linux_post_install/system.env` |
| `pos system health` | `bin/pos-system-health` | Host health dashboard: disk per mount, RAM/swap, backup age, fail2ban, docker containers. Exits 1 if any check FAILs | Console-only reporter — health never sends notifications; forward the output with a wrapper of your own (e.g. a cron job or your own timer redirecting it). `HEALTH_BACKUP_MAX_AGE_DAYS` (default 2) and `BACKUP_SERVICE_ROOTS` are read from the environment or a hand-written `~/.config/linux_post_install/system.env`; `--help` shows the effective values |
| `pos system uninstall` | `bin/pos-system-uninstall` | Safe, interactive uninstaller for the pos toolkit — scans and removes binaries, shell integration, config, and data in three tiers | Tier 1 (always): binaries in `/usr/local/bin/` (pos, pos-*, libs, prebuilt hotspot binaries), leftovers from older installs (pos-managed systemd units + old feature scripts — pos ships none anymore), the flag store under `/usr/local/share/linux_post_install/`, shell integration in `~/.bashrc` (PATH, completion), completion file. Tier 2 (`--config`): `~/.config/linux_post_install/` (.env files, authorized_keys). Tier 3 (`--data`): `~/.local/share/linux_post_install/` (logs, captured output). Flags: `--yes` (skip prompts, tier 1 only), `--config` (include tier 2), `--data` (include tier 3). Combine all three for nuclear removal. Git repo is never removed |
| `pos system bank` | `bin/pos-system-bank` | Persistent command bank for saving and running shell commands — list, add, show, run, edit, remove, alias | Commands stored in `~/.config/linux_post_install/bank.env` (pipe-delimited: `name\|description\|command`, chmod 600, managed by the tool). Parameterized `{param}` templates are substituted at run time. Interactive menu on a TTY with no args. `BANK_FILE` env seam overrides the path. `alias` subcommand manages bash aliases in `~/.bashrc` inside a managed `# >>> pos bank aliases …` block (`BASH_RC_FILE` env seam) |

To run the dashboard periodically, use your own scheduling — pos ships no scheduler: add a cron entry (`crontab -e`, e.g. `0 9 * * * pos system health`) or your own timer in your service manager, redirecting the output if you want a record. A legacy install may still have old `pos-health.{service,timer}` units or `schedule.d/` jobs — `pos system uninstall` sweeps leftover pos-managed units; stale schedule files under `~/.config/linux_post_install/schedule.d/` can simply be deleted (pos no longer reads them).

#### system bank

**File:** `bin/pos-system-bank`

Persistent command bank for saving and running shell commands. Commands are stored in `~/.config/linux_post_install/bank.env` (pipe-delimited: `name|description|command`, chmod 600, managed by the tool). Supports parameterized templates with `{param}` placeholders that are substituted at run time (quoted for safe shell evaluation).

On a TTY with no arguments, `pos system bank` opens an interactive menu (list / add / run / edit / remove).

| Command | Purpose |
|---------|---------|
| `pos system bank list` | List all saved commands |
| `pos system bank add <name> [desc] [cmd]` | Add a new command (interactive for missing args) |
| `pos system bank show <name>` | Show command details and detected parameters |
| `pos system bank run <name> [key=val …]` | Run a command (interactive for missing params) |
| `pos system bank edit <name>` | Edit an existing command |
| `pos system bank remove <name>` | Remove a command (also drops aliases pointing at it) |
| `pos system bank alias <name> [alias_name]` | Add/update a bash alias for a bank command (default alias name = bank name) |
| `pos system bank alias list` | List bash aliases from `~/.bashrc` |
| `pos system bank alias remove <alias_name>` | Remove a bash alias |

Aliases are bash aliases written into `~/.bashrc` inside a managed block
(`# >>> pos bank aliases … <<<`, `bashrc`-path seam: `BASH_RC_FILE`), as
`alias <alias_name>='pos system bank run <name>'` — retyping the same alias
name retargets the line; removing the last alias removes the whole block.
An alias name already defined outside the block is refused, and aliasing a
command that also exists on `PATH` prints a non-blocking warning (the alias
will shadow it in interactive shells).

Example with parameters:

```
pos system bank add convert "Convert video" "ffmpeg -i {input} -crf {quality} {output}"
pos system bank run convert input=clip.mp4 quality=23 output=clip.mkv
```

### flags

Feature-flag management CLIs (see [SCRIPTS.md → lib/flags.sh](SCRIPTS.md#libflagssh--flag-store)):

| Command | Purpose |
|---------|---------|
| `flag-reader` | List all flags + status (`set: <name>` / `unset: <name>`) |
| `flag-reader <name>` | Check one flag; exit 0 if set, 1 if not |
| `flag-reader --raw <name>` | Print only the stored value (script-friendly) |
| `flag-set <name> [value]` | Set a flag, optionally with a value (requires sudo) |
| `flag-clear <name>` | Unset a flag (requires sudo) |

### tree

**File:** `bin/pos-tree`

`pos tree` prints the `pos` command tree — every category, command, and subcommand the dispatcher can reach, annotated with each tool's `# POS:` description. Data is derived live from the `bin/pos-*` filenames and their `# POS_SUBCMDS:` headers, so it always matches what `pos` can actually run.

| Command | Purpose |
|---------|---------|
| `pos tree` | Full command tree |
| `pos tree --depth N` | Limit nesting depth (1 = root only) |
