# Core Scripts Reference

Everything that runs during the bootstrap install: `install.sh`, `preinstall.sh`, `postinstall.sh`, the shared libraries, and `features/`. For the `pos` CLI tools see [POS.md](POS.md), for apps see [APPS.md](APPS.md), for services see [SYSTEMD.md](SYSTEMD.md).

---

## Table of contents

- [install.sh — the orchestrator](#installsh--the-orchestrator)
- [preinstall.sh — system packages](#preinstallsh--system-packages)
- [postinstall.sh — user configuration](#postinstallsh--user-configuration)
- [lib/common.sh — shared library](#libcommonsh--shared-library)
- [lib/flags.sh — feature flags](#libflagssh--feature-flags)
- [lib/notify.sh — multi-platform alerting](#libnotifysh--multi-platform-alerting)
- [features/autostart.sh — boot-time feature](#featuresautostartsh--boot-time-feature)
- [features/usb-automount.sh — USB automount feature](#featuresusb-automountsh--usb-automount-feature)
- [x64_bin/ — precompiled binaries](#x64_bin--precompiled-binaries)

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
| 2 | scripts | Copies `bin/*` → `/usr/local/bin/` (755), `lib/common.sh` + `lib/flags.sh` + `lib/notify.sh` + `lib/entertainment-lib.sh` → `/usr/local/bin/` (644). Copies precompiled arch binaries from `x64_bin/` (or `arm64_bin/`) → `/usr/local/bin/`. With `--feature`: also installs `features/*` (see below) |
| 3 | postinstall | `postinstall.sh` — PATH, completion, SSH keys, systemd |
| 4 | scalepoint | Shallow-clones ScaleTail templates to `/usr/local/share/linux_post_install/scale-tail` |
| 5 (opt) | apps | `apps/install.sh` when `--apps` (interactive) or `--full` (all, non-interactive) |

**Precompiled arch binaries (Phase 2):** `install.sh` picks the source folder from the machine architecture — `x86_64` → `x64_bin/`, `aarch64`/`arm64` → `arm64_bin/` (added later) — and copies every file in it to `/usr/local/bin/` (755). These are manually-compiled tools not available as internet builds (currently `create_ap`, `wihotspot`, `wihotspot-gui`). Dropping an `arm64_bin/` folder later needs no code change.

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
    hostapd dnsmasq iptables iw
    ca-certificates gnupg lsb-release
    python3 python3-pip rclone
    libqrencode4 libgtk-3-0
)
```

Add or remove package names here. `nmap` and `fail2ban` are used later by `pos network scan` and `postinstall.sh`; `hostapd`, `dnsmasq`, `iptables`, `iw` and the GTK/Qr libs support the precompiled hotspot tools (see [x64_bin/ — precompiled binaries](#x64_bin--precompiled-binaries)).

---

## postinstall.sh — user configuration

**File:** `postinstall.sh` (runs as your user)
**Purpose:** Phase 3 — configures the user environment, SSH keys, and systemd services.

### How it works

1. **rclone config** — if `config/rclone.conf` exists (gitignored), installs it to `~/.config/rclone/rclone.conf` (600).
2. **PATH** — appends a `PATH` line to `~/.bashrc` if not already present.
3. **pos bash completion** — installs `completions/pos.bash` to `/usr/local/share/bash-completion/completions/` and sources it from `~/.bashrc`.
4. **SSH authorized keys** — if `config/authorized_keys` exists, appends missing keys to `~/.ssh/authorized_keys` (skips comments and duplicates, chmod 600).
5. **systemd services** — copies `systemd/*.service` to `/etc/systemd/system/`, daemon-reloads, then enables each service. **`autostart.service` is only enabled when the `autostart` feature flag is set**, and **`usb-automount.service` only when the `usb-automount` flag is set** (see [lib/flags.sh](#libflagssh--feature-flags)); otherwise they're skipped with a hint to run `./install.sh --feature`.

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

## lib/notify.sh — multi-platform alerting

**File:** `lib/notify.sh` (installed to `/usr/local/bin/notify.sh`)
**Purpose:** opt-in alerting helper for tools that announce events. Delivers to every platform in `NOTIFY_PLATFORM` via the sender contract `pos-communication-<platform> send <value> [--markdown]` (default platform: `telegram`).

Self-contained by design: defines **only** `notify_send()` + `notify_platforms()`, so sourcing it never clobbers a tool's own `log`/`warn`/`err`. **Silent-fails per platform** — a missing sender or failed send only warns and never changes the caller's exit code.

```bash
source "$(dirname "$0")/../lib/notify.sh" 2>/dev/null || source "$(dirname "$0")/notify.sh"
notify_send "Backup completed"
notify_send "**disk full**" --markdown
```

Platform selection: `~/.config/linux_post_install/notify.env` (`NOTIFY_PLATFORM=telegram,matrix`, comma-separated = fan out; env var wins over the file). Adding a platform = drop a `bin/pos-communication-<platform>` sender + list it — no change to `lib/notify.sh`. The telegram platform key maps to tool `pos-communication-telegram-sender` via `notify_sender_name()`.

---

## lib/entertainment-lib.sh — entertainment module

**File:** `lib/entertainment-lib.sh` (installed to `/usr/local/bin/entertainment-lib.sh`)
**Purpose:** shared logic for the `pos entertainment` tools — config (`entertainment.env`), `ENABLED` auto-trigger list parsing (`plugin, interval` pairs), plugin lookup by `# POS_PLUGIN:` marker, interval→schedule mapping, and scheduler reconciliation (systemd **user** timers — the only backend; requires a reachable user manager, `ensure_linger()` enables linger if needed).

Sourced by `bin/pos-entertainment-send|config|enable|disable|status` (after `lib/common.sh`). **Plugins must not source it** — their stdout is the sent message.

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

---

## features/usb-automount.sh — USB automount feature

**File:** `features/usb-automount.sh` (installed to `/usr/local/bin/usb-automount.sh` by `./install.sh --feature`)
**Purpose:** mounts USB storage automatically — at boot and on hotplug — so a plugged-in stick is immediately ready for `pos system backup`'s post-verify USB copy without manual mounting.

### How it works

1. Every run (boot via `usb-automount.service`, hotplug via its self-installed udev rule, or manual `sudo usb-automount.sh`) scans `lsblk -J` for unmounted removable block devices — partitions and raw whole-disk filesystems — and mounts each at `/media/<label>`.
2. vfat/exfat/ntfs mounts are world-writable (`-o umask=000`) so a non-root user can write; filesystems that reject `umask` fall back to a plain mount.
3. Idempotent: already-mounted devices are skipped, and repeated runs are no-ops.
4. First root run installs the hotplug rule `/etc/udev/rules.d/99-usb-automount.rules` (`SYSTEMD_WANTS="usb-automount.service"`) and reloads udev — an edited rule is never overwritten.

### Configuration

- Log file: `$HOME/.usb-automount.log` (edit the `LOG` variable at the top).
- Mount point: `/media/<label>` (bumps to `-2`, `-3` when the label is already in use as a mountpoint); mount options are tuned in `mount_one`.
- The script is user-customizable like any feature — a plain reinstall never overwrites your edits.

---

## x64_bin/ — precompiled binaries

**Folder:** `x64_bin/` (future: `arm64_bin/`)
**Purpose:** manually-compiled tools that are **not available as prebuilt binaries on the internet**. `install.sh` copies them verbatim into `/usr/local/bin/` on the matching architecture (see [install.sh — the orchestrator](#installsh--the-orchestrator)).

### Contents

| File | Type | Purpose | Runtime deps |
|------|------|---------|--------------|
| `create_ap` | bash script | Create a Wi-Fi access point from the CLI (NAT/Internet sharing) | `hostapd`, `dnsmasq`, `iptables`, `iw` (in `preinstall.sh`) |
| `wihotspot` | POSIX wrapper | Launches `wihotspot-gui` (path points at `/usr/local/bin/`) | — |
| `wihotspot-gui` | ELF x86-64 | GTK3 GUI for the hotspot (QR code via libqrencode) | `libgtk-3-0`, `libqrencode4` |

### Configuration

- Managed through the `pos network hotspot` command (see [POS.md → network](POS.md#network)): `hotspot` launches the GUI; `start`/`stop`/`status` wrap `create_ap`.
- Add a future `arm64_bin/` folder with the same filenames and it is installed automatically on `aarch64` machines — no `install.sh` change needed.
