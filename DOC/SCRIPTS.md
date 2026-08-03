# Core Scripts Reference

Everything that runs during the bootstrap install: `install.sh`, `preinstall.sh`, `postinstall.sh`, the shared libraries, and `features/`. For the `pos` CLI tools see [POS.md](POS.md), for apps see [APPS.md](APPS.md), for services see [SYSTEMD.md](SYSTEMD.md).

---

## Table of contents

- [install.sh — the orchestrator](#installsh--the-orchestrator)
- [preinstall.sh — system packages](#preinstallsh--system-packages)
- [postinstall.sh — user configuration](#postinstallsh--user-configuration)
- [lib/common.sh — shared library](#libcommonsh--shared-library)
- [lib/flags.sh — feature flags](#libflagssh--feature-flags)
- [features/autostart.sh — boot-time feature](#featuresautostartsh--boot-time-feature)

---

## install.sh — the orchestrator

**File:** `install.sh` (run as `./install.sh`)
**Purpose:** the entry point. Coordinates all four install phases and the optional apps/features installs.

### How it works

1. **Pre-parse `--no-color`** before anything else, so colors are disabled early (`TERM=dumb` is exported).
2. Source `lib/common.sh` (logging, `run`, `spawn`, …) and `lib/flags.sh` (feature flags).
3. Parse CLI options.
4. For each phase, `should_run <num> <name>` decides whether to run it:
   - `--skip <phase>` removes a phase (takes precedence).
   - `--steps <spec>` restricts the run to the listed phases only (`1,3,4` or `1-3`).
   - Phase map: `1=preinstall`, `2=scripts`, `3=postinstall`, `4=scalepoint` (+ `apps` handled separately).

The phases:

| # | Phase | Script/action |
|---|-------|----------------|
| 1 | preinstall | `preinstall.sh` — apt packages + yt-dlp |
| 2 | scripts | Copies `bin/*` → `/usr/local/bin/` (755), `lib/common.sh` + `lib/flags.sh` → `/usr/local/bin/` (644). With `--feature`: also installs `features/*` (see below) |
| 3 | postinstall | `postinstall.sh` — PATH, completion, SSH keys, systemd |
| 4 | scalepoint | Shallow-clones ScaleTail templates to `/usr/local/share/linux_post_install/scale-tail` |
| 5 (opt) | apps | `apps/install.sh` when `--apps` (interactive) or `--full` (all, non-interactive) |

**Feature block (Phase 2, only with `--feature`):** for every file in `features/` it copies it to `/usr/local/bin/<name>`. If the destination already exists it asks **"Overwrite existing …? [y/N]"** (default keeps your file), then always sets the feature flag via `flag_set` (name derived as `<filename without .sh>`).

### Configuration

No config file — everything is command-line:

| Option | Effect |
|--------|--------|
| `--apps` | Run the interactive app picker after core install |
| `--full` | Core install + every app (non-interactive) |
| `--feature` | Install `features/` scripts to `/usr/local/bin/` (prompts on overwrite), sets their flags |
| `--dry-run` | Log every action instead of executing. **Note:** applies to `install.sh` itself; `postinstall.sh` runs as a subprocess and does not inherit `DRY_RUN` |
| `--skip <phase>` | Skip a phase (repeatable): `preinstall`, `scripts`, `postinstall`, `scalepoint`, `apps` |
| `--steps <spec>` | Run only listed phases: `1,3,4` or `1-3` |
| `--no-color` | Disable colored output |
| `-h`, `--help` | Show usage |

---

## preinstall.sh — system packages

**File:** `preinstall.sh`
**Purpose:** Phase 1 — installs the base system packages and yt-dlp.
**Run:** automatically by `install.sh`, or standalone with `--dry-run`.

### How it works

1. `apt update`.
2. Installs the package list.
3. Downloads the latest `yt-dlp` binary to `/usr/local/bin/yt-dlp` and makes it executable.
4. Verifies a couple of tools (`git --version`, `yt-dlp --version`).

### Configuration

The package list is the `PACKAGES` array:

```bash
PACKAGES=(
    git curl wget vim nano tmux tree jq
    unzip zip rsync htop btop telnet
    net-tools iputils-ping traceroute tcpdump nmap
    openssh-client openssh-server ufw fail2ban
    ca-certificates gnupg lsb-release
    python3 python3-pip rclone
)
```

Add or remove package names here. `nmap` and `fail2ban` are used later by `pos network scan` and `postinstall.sh`.

---

## postinstall.sh — user configuration

**File:** `postinstall.sh` (runs as your user)
**Purpose:** Phase 3 — configures the user environment, SSH keys, and systemd services.

### How it works

1. **rclone config** — if `config/rclone.conf` exists (gitignored), installs it to `~/.config/rclone/rclone.conf` (600).
2. **PATH** — appends a `PATH` line to `~/.bashrc` if not already present.
3. **pos bash completion** — installs `completions/pos.bash` to `/usr/local/share/bash-completion/completions/` and sources it from `~/.bashrc`.
4. **SSH authorized keys** — if `config/authorized_keys` exists, appends missing keys to `~/.ssh/authorized_keys` (skips comments and duplicates, chmod 600).
5. **systemd services** — copies `systemd/*.service` to `/etc/systemd/system/`, daemon-reloads, then enables each service. **`autostart.service` is only enabled when the `autostart` feature flag is set** (see [lib/flags.sh](#libflagssh--feature-flags)); otherwise it's skipped with a hint to run `./install.sh --feature`.

### Configuration

- SSH keys: `config/authorized_keys` (one per line, gitignored).
- rclone config: `config/rclone.conf` (gitignored).
- The PATH line and completion line are embedded strings at the top of the file — edit there to change them.
- The `autostart` flag (set by `./install.sh --feature`) controls whether `autostart.service` gets enabled.

---

## lib/common.sh — shared library

**File:** `lib/common.sh` (installed to `/usr/local/bin/common.sh`)
**Purpose:** colors, logging, timers, spinners, dry-run-aware execution, and prompts. Sourced by most scripts.

### How it works

Auto-disables colors when stdout is not a TTY. The `run` helper is the dry-run hook: scripts that want `--dry-run` support run every side-effecting command through `run`.

### Configuration / API

| Function | Purpose |
|----------|---------|
| `log "msg"` | Green `[+]` status line |
| `warn "msg"` | Yellow `[!]` warning |
| `err "msg"` | Red `ERROR:` line to stderr, then `exit 1` |
| `ok "msg"` | Green `OK` prefix line |
| `section "title"` | Cyan-bordered section header |
| `step N T "msg"` | Numbered step header (`[N/T] msg`) |
| `run cmd…` | Executes the command, or logs `(dry-run)` when `DRY_RUN=1` |
| `spawn "msg" cmd…` | Runs with an animated spinner + elapsed time; prints captured stderr and exits on failure |
| `timer_start` / `timer_stop` | Track and print elapsed time |
| `confirm "prompt" [default]` | Yes/no prompt; default `y` (`[Y/n]`) unless `n` given (`[y/N]`) |

---

## lib/flags.sh — feature flags

**File:** `lib/flags.sh` (installed to `/usr/local/bin/flags.sh`)
**Purpose:** a system-wide, per-feature flag store. Flags mark features as installed/opted-in and gate behavior (e.g. systemd enablement) elsewhere.

### How it works

One file per flag in `$FLAGS_DIR`. **Presence = set, file content = optional value.** Reads are plain file ops; writes go through `run` + `sudo` so they respect `--dry-run`. Installed by `./install.sh --feature`; also usable directly:

```bash
source lib/flags.sh
flag_set autostart            # bare flag
flag_set app "2.1"            # flag with a value
flag_is_set autostart         # 0 if set, 1 if not
flag_value app                # prints "2.1"
flag_list                     # names of all set flags
flag_clear autostart
```

### Configuration

| Setting | Location |
|---------|----------|
| `FLAGS_DIR` (env) | Default `/usr/local/share/linux_post_install/flags` (dir 755, files 644). Overridable via environment for testing |
| CLI wrappers | `flag-reader`, `flag-set`, `flag-clear` (see [POS.md](POS.md)) |

---

## features/autostart.sh — boot-time feature

**File:** `features/autostart.sh` (installed to `/usr/local/bin/autostart.sh` by `./install.sh --feature`)
**Purpose:** runs once at boot via `autostart.service` (only when the `autostart` flag is green) and logs basic connectivity status.

### How it works

Appends timestamped lines to `~/.autostart.log`:

```
[<date>] autostart running
[<date>] Network: online   # ping 8.8.8.8 succeeded
[<date>] autostart complete
```

### Configuration

- Log file: `$HOME/.autostart.log` (edit the `LOG` variable at the top).
- The script is the one you're *most* likely to customize — this is exactly why it lives in `features/` instead of `bin/`: a plain reinstall never overwrites your edits.
