# Development Guide

How this repo works, how to add features, and what to keep in mind when editing.

---

## Architecture

### Installation Phases

```
                  install.sh
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    preinstall.sh   bin/*    postinstall.sh
    (packages)   → /usr/local/bin  (config + services)
```

| Phase | Script | Responsibility |
|-------|--------|----------------|
| Pre | `preinstall.sh` | System packages, apt repos, global binaries (yt-dlp) |
| Install | `install.sh` | Copies `bin/*` → `/usr/local/bin/` (chmod 755), `lib/common.sh` + `lib/flags.sh` + `lib/entertainment-lib.sh` → `/usr/local/bin/` (chmod 644) |
| Post | `postinstall.sh` | User config (SSH keys, PATH, bash completion), systemd services |

Each phase is independent and runs only if the corresponding script exists.

### Directory Layout

| Directory | Purpose | Installed To |
|-----------|---------|-------------|
| `bin/` | Daily-use CLI tools and wrappers | `/usr/local/bin/` |
| `apps/<category>/` | Optional desktop app installers | run on demand |
| `lib/` | Shared libraries: `common.sh` (helpers), `flags.sh` (feature flags), `notify.sh` (multi-platform alerting), `entertainment-lib.sh` (entertainment scheduling) | sourced at build time |
| `config/` | Gitignored user config files | `~/.config/<app>/` (via postinstall) |
| `entertainment/` | Public-API plugins for the entertainment module | `/usr/local/bin` (via install.sh Phase 2) |
| `compose/` | ScaleTail templates (git submodule) | `/usr/local/share/linux_post_install/scale-tail` |
| `systemd/` | Systemd unit files | `/etc/systemd/system/` (via postinstall) |

### The `pos` CLI

`bin/pos` is a smart dispatcher. It scans its own directory for executable `pos-*` files and uses variable-length argument matching:

```
pos docker compose up jellyfin
  → tries pos-docker-compose-up-jellyfin  (not found)
  → tries pos-docker-compose-up           (not found)
  → finds pos-docker-compose              → runs with args "up jellyfin"
```

All non-interactive commands log to `~/.local/share/linux_post_install/logs/`.

`pos help <full command>` shows a tool's help, e.g. `pos help communication telegram-sender` (all words joined with dashes → `pos-communication-telegram-sender --help`). `pos <category>` or `pos <category> --help` shows a category's subcommands (derived from the `pos-<category>-*` filenames in `bin/` — no script execution, so it works even for root-only/interactive tools like `system-firewall`).

**When adding a command, `bin/pos` itself has one thing to keep in sync:**

- **The usage text** (`usage()` function) — the CATEGORIES block is **auto-derived** from the `pos-*` filenames in `bin/` (no manual edit, can't drift). The EXAMPLES block is the only hand-maintained part: add a line there only if you want the tool showcased in `pos --help`.
- **`INTERACTIVE_CMDS`** (space-separated list above the dispatch loop) — commands that **read stdin** (password prompts, selection menus: `system-firewall`, `media-mp4`, `system-backup`, `share-usb-server`, `communication-telegram-listener`) must be added here. Everything else is piped through `tee` for logging, which would hang or swallow an interactive prompt. sudo's own password prompt is unaffected — it reads from `/dev/tty`. Trade-off: it's all-or-nothing **per script** — adding a flag-style tool with *any* prompting subcommand (e.g. `share-usb-server --share`) means *every* subcommand of that script skips output logging (e.g. `pos share usb server --ls` loses the `tee` log too).

### Shared Library (`lib/common.sh`)

Sourced by most scripts. Key functions:

| Function | Purpose |
|----------|---------|
| `log "msg"` | Green `[+]` status message |
| `warn "msg"` | Yellow `[!]` warning |
| `err "msg"` | Red `ERROR:` + exit 1 |
| `ok "msg"` | Green `OK` prefix |
| `section "title"` | Cyan-bordered section header |
| `step N T "msg"` | Numbered step header |
| `run cmd` | Executes command, respects `$DRY_RUN` |
| `spawn "msg" cmd` | Animated braille spinner + elapsed time |
| `timer_start` / `timer_stop` | Elapsed time tracking |
| `confirm "prompt"` | y/N prompt with optional default |

---

## Adding a New CLI Tool

Start from the template: `cp templates/pos-tool.sh bin/pos-<category>-<command> && chmod +x bin/pos-<category>-<command>`.

### 1. Create the script

```bash
#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

usage() {
    cat <<EOF
Usage: my-tool <argument>
EOF
    exit 0
}

case "${1:-}" in
    -h|--help|"") usage ;;
esac

# --- script logic ---
```

**Conventions:**
- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail`
- `--help` flag: accept `-h` / `--help` via `case` pattern
- Shared library: always source `common.sh` for colors, logging, spinners
- Exit codes: `0` success, `1` error
- No shared lib? Inline fallbacks:
  ```bash
  log()  { echo "[+] $*"; }
  warn() { echo "[!] $*"; }
  err()  { echo "ERROR: $*" >&2; exit 1; }
  ```
  If you skip `common.sh`, `make gen` adds the tool to the "Scripts that do NOT source common.sh" list in `DOC/AGENT_Context_Project.md` automatically.

### 2. Make it discoverable

- The dispatcher auto-discovers executable `bin/pos-*` files — no registration needed. The file **must be executable** (`chmod +x`, committed as mode `100755`); the dispatcher and `install.sh` skip non-executables.
- `pos <category> --help` (and bare `pos <category>`) is derived from the `pos-<category>-*` filenames too — a new tool appears in its category's help automatically, with no registration (see [The `pos` CLI](#the-pos-cli)).
- **Add the `# POS:` header** (single source of truth for the docs) right after the shebang/strict-mode lines:
  ```bash
  # POS: <category> <command> — one-line description rendered by `make gen`
  # POS_FLAGS: --flag1 --flag2      # ONLY for flag-style tools
  # POS_SUBCMDS: sub1 sub2          # ONLY for multi-command tools
  ```
  The description feeds the dispatch table, bin tree and file table in `DOC/AGENT_Context_Project.md`; `POS_FLAGS` feeds flag completion and `POS_SUBCMDS` feeds subcommand completion in `completions/pos.bash` (both update via `make gen`). `make gen` only reads the text after the first `— ` — the `<category> <command>` words before it are convention-only (for nested tools, keep the full path there, e.g. `# POS: communication telegram-listener — …`).
- **Category-less vs categorized:** most tools are `bin/pos-<category>-<command>`. Use category-less `bin/pos-<cmd>` (e.g. `pos-config`, `pos-tree`) only for dispatcher/dev-level commands that fit no category — they dispatch and document like any tool but show with an empty category in the generated tables.
- Nested tools (e.g. `bin/pos-communication-telegram-listener`) are auto-detected from filenames: the trailing segment (`listener`) is offered as a subcommand of the parent tool (`communication-telegram`) in `pos <category> --help` and tab-completion, instead of appearing as a flat sibling (`telegram-listener`). The flat dash-form (`pos communication telegram-listener`) still dispatches.
- Optionally add an EXAMPLES line in `bin/pos` `usage()` to showcase the tool in `pos --help`.
- If the command **reads stdin** (prompts/selection), add it to `INTERACTIVE_CMDS` in `bin/pos` — see [The `pos` CLI](#the-pos-cli).

### 3. Add system dependencies

Add package names to the `PACKAGES` array in `preinstall.sh`:

```bash
PACKAGES=(
    ...
    your-package
)
```

**Not in apt?** If the dependency ships as a manual installer (no package — e.g. `usbsrv`, the USB Redirector server), do **not** put it in `PACKAGES` (that would break `preinstall.sh`). Instead, add a `command -v <binary> || err "… install from <URL>"` guard in the tool itself and note the manual install in `usage()`/`DOC/POS.md`.

### 4. Config files (if needed)

Two kinds of config, don't mix them up:

- **Machine defaults shipped by the installer:** place the file in `config/` and add copy logic to `postinstall.sh`. If it contains secrets, add to `.gitignore` and document in `DOC/`.
- **Runtime tool config set by the user:** `~/.config/linux_post_install/<tool>.env` with `chmod 600`. Load it with env-var precedence (flags > environment > file). Patterns: `pos-docker-compose` (`compose.env`), `pos-communication-telegram-sender` (`telegram.env`, edited via `pos config telegram` — token masked), and the shared ones below. Never store tokens in the repo.
  - `system.env` — shared "system" settings loaded by `pos-system-*` tools via `load_system_env()` in `lib/common.sh` (currently `BACKUP_SERVICE_ROOTS`, `HEALTH_BACKUP_MAX_AGE_DAYS`). Env already exported wins over the file.
  - `notify.env` — alerting platform selection (`NOTIFY_PLATFORM=telegram,matrix`), read by `lib/notify.sh`.

### 5. Add SSH keys (if needed)

Place public keys in `config/authorized_keys` (one per line). `postinstall.sh` reads this file automatically.

### 6. Update the docs

- `DOC/POS.md`: add the command to the section table + a detail block (commands, behavior, configuration). This is the one hand-written doc.
- `DOC/AGENT_Context_Project.md` generated sections (bin tree, dispatch table, no-common.sh list, line-count table) and the `completions/pos.bash` flags block are produced by `make gen` — do **not** hand-edit between the `GEN:START`/`GEN:END` markers.
- Root `README.md`: only if the `pos` category list in the help text changes.

### 7. Test

```bash
chmod +x bin/your-tool
bash -n bin/your-tool
shellcheck bin/your-tool
./bin/your-tool --help
bin/pos help <full command>   # confirm dispatch works
bin/pos <category> --help     # confirm category listing includes the new tool (first tool in a new category)
make gen                      # regenerate doc tables + completion flags
make check                    # full self-consistency gate (syntax, exec bits, doc/code sync, smoke)
```

`make check` is the definition of done — the same check runs as a pre-commit hook once you've run `make hook`.

---

## Adding an Entertainment Plugin

The `entertainment` module routes public-API data to Telegram via the single runner `pos entertainment send <plugin>` (`bin/pos-entertainment-send`). Auto-triggering is config-driven: `ENABLED` in `entertainment.env` holds `plugin, interval` pairs; the tools `pos entertainment config|enable|disable|status` (`bin/pos-entertainment-*`) reconcile the schedule. All shared logic (ENABLED parsing, interval→schedule mapping, scheduler sync) lives in `lib/entertainment-lib.sh` — sourced by the `pos-entertainment-*` tools (never by plugins). The scheduler is **systemd user timers** — the only backend (requires a reachable user systemd manager).

### 1. Create the plugin

Drop an executable script in `entertainment/<name>.sh` with a `# POS_PLUGIN: <name>` marker on line 3 (this is what makes it a plugin — the installed runner lists plugins by this marker, not by `.sh` files, since `/usr/local/bin` is shared with other tooling). Declare every config key the plugin reads with `# POS_KEYS: <KEY> <description> (required|optional)` lines right after it — `pos entertainment config` prints these in its Keys section and uses them to warn/not-warn on `config set`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# POS_PLUGIN: myplugin
# POS_KEYS: MYPLUGIN_URL <feed url> (required)
# POS_KEYS: MYPLUGIN_TAG <filter tag> (optional)
err() { echo "ERROR: $*" >&2; exit 1; }

command -v curl &>/dev/null || err "curl not found"

data="$(curl -fsS --max-time 20 https://api.example.com/foo)"
printf 'Title: %s\n' "$data"
```

**Contract:** plugins are **self-contained** — do **not** source `lib/common.sh`. Its `log`/`warn`/`ok` helpers print to **stdout**, and the runner captures stdout as the message to send (helper chatter would be sent to Telegram). All stdout is the message; errors go to stderr and exit nonzero. Plugins must be non-interactive (no prompts) — the module is designed for systemd user timers.

### 2. Config (if needed)

Read runtime values from `~/.config/linux_post_install/entertainment.env` (chmod 600, env precedence) — same pattern as `telegram.env`. Example: `weather.sh` uses `WEATHER_LAT`/`WEATHER_LON`. Declare each key with a `# POS_KEYS:` header line (see step 1) so `pos entertainment config` lists it and `config set` recognizes it.

### 3. Deps

`curl` and `jq` are already in `preinstall.sh` PACKAGES. Anything else: guard with `command -v … || err "…"` and, if apt-available, add to PACKAGES.

### 4. Done

Plugins are not `pos-*` tools, so `make gen`/`make check` don't scan them — verify with `bash -n entertainment/<name>.sh` and a live `pos entertainment send <name> --print` run. Document the plugin in `DOC/POS.md`'s entertainment plugin table.

---

## Adding an Optional App

Start from the template: `cp templates/app.sh apps/<category>/<name>.sh`.

### 1. Create the installer

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_myapp() {
    command -v myapp &>/dev/null && { log "myapp already installed"; return 0; }
    spawn "Installing myapp" sudo apt install -y myapp
}

uninstall_myapp() {
    command -v myapp &>/dev/null || { log "myapp not installed"; return 0; }
    spawn "Removing myapp" sudo apt purge -y myapp
    spawn "Cleaning up dependencies" sudo apt autoremove -y
}

case "${1:-}" in
    uninstall) uninstall_myapp ;;
    *) install_myapp ;;
esac
```

Place it in `apps/<category>/<name>.sh`. It auto-appears in the picker — no registration needed.

**Categories:** `browsers`, `development`, `media`, `networking`, `remote-access`, `system`, `utilities`

**Docs:** add a row to the catalog table in `DOC/APPS.md` (name, category, purpose, install method).

### 2. Conventions

- Idempotent: check `command -v` (or `flatpak list` / file existence) before installing **and** uninstalling
- Every app **must** provide an `uninstall_<name>()` function and dispatch on `uninstall` via the `case` above — `apps/install.sh --uninstall` depends on it
- APT packages → `sudo apt install -y` inside `spawn`, remove with `sudo apt purge -y` + `sudo apt autoremove -y`
- Repo-based apps (apt repo added at install) → also remove the `.list` file and keyring in uninstall
- Official scripts → `curl ... | sh` inside `spawn`
- Flatpak → `flatpak install -y flathub <app-id>` inside `spawn`, remove with `flatpak uninstall -y <app-id>`
- `.deb` files → download to temp, `sudo apt install -y ./file.deb` inside `spawn`
- File/AppImage installs → remove the installed files, symlinks, and desktop entries in uninstall
- `usermod` for groups → print re-login reminder

---

## Editing an Existing Tool

1. Find the script in `bin/`
2. Understand its contract (args, output, exit codes)
3. Make the change — keep it idempotent
4. Update `DOC/POS.md` (or the relevant doc) if behaviour changed
5. Run `shellcheck` on the modified file

---

## Best Practices

### Alerting

To notify on events, source the shared helper instead of calling a platform tool directly:

```bash
source "$(dirname "$0")/../lib/notify.sh" 2>/dev/null || source "$(dirname "$0")/notify.sh"
notify_send "Backup completed"
notify_send "**disk full**" --markdown
```

`notify_send` is deliberately dependency-free (defines only itself, so it never clobbers a tool's own `log`/`warn`/`err`) and **silent-fails**: if no platform is configured it warns and returns 0, never breaking the caller's flow or exit code. Source it opt-in in any tool that should alert; for failure alerts use `trap 'notify_send "..." ERR'`.

**Multi-platform routing:** `notify_send` delivers to every platform listed in `NOTIFY_PLATFORM` (env or `~/.config/linux_post_install/notify.env`, default `telegram`, comma-separated to send to all). Adding a new platform (e.g. Matrix/Synapse) means creating a `bin/pos-communication-<platform>` tool that implements the **sender contract**:

```bash
pos-communication-<platform> send <value> [--markdown]   # exit 0 on delivery
```

then listing it in `NOTIFY_PLATFORM`. Platform keys map to tool names via `notify_sender_name()` in `lib/notify.sh` — the telegram platform key stays `telegram` but its tool is `pos-communication-telegram-sender`. `pos-communication-telegram-sender` already follows this (`--markdown` is an alias for `--parse-mode markdown`). No changes to `lib/notify.sh` are needed for a new platform.

### Idempotency

Check before creating, use `>>` with grep guards, don't overwrite user configs.

### Error Handling

```bash
set -euo pipefail
command -v docker &>/dev/null || { echo "docker not found"; exit 1; }
[[ -n "${1:-}" ]] || { echo "Usage: my-tool <arg>"; exit 1; }
```

### Portability

Targets **Debian** and **Ubuntu**. Use `apt`, assume bash at `/usr/bin/env bash`, check tools with `command -v`.

### Dry-run Support

Scripts support `--dry-run`. Use the `run()` helper:

```bash
run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log "(dry-run) $*"
    else
        "$@"
    fi
}
run sudo apt install -y git
```

### Security

- Never hardcode secrets — put them in `config/` (gitignored) or, for runtime tool config, `~/.config/linux_post_install/<tool>.env`
- `chmod 600` for sensitive files
- Mask secrets in `config` output (see `pos-communication-telegram-sender`'s `mask_token`)
- Validate input before shell commands
- Use `sudo` only where needed

### Naming

- CLI tools: `bin/pos-<category>-<command>`
- Legacy wrappers: `bin/wr-*`
- App installers: `apps/<category>/<name>.sh`
- Features: `features/<name>.sh`
- Lowercase with hyphens

---

## Features & Flags

`features/` holds scripts the user is likely to customize (e.g. `autostart.sh`). Unlike `bin/` (synced on every install), features are installed on demand and **never overwritten without asking**.

### Adding a Feature

Start from the template: `cp templates/feature.sh features/<name>.sh`.

1. Create `features/<name>.sh` following the CLI tool template (shebang, `set -euo pipefail`, `--help`).
2. Nothing else is registered — `./install.sh --feature` auto-discovers it, copies it to `/usr/local/bin/`, asks before overwriting an existing file, and sets its flag.
3. If the feature backs a systemd service, gate the service on the flag in `postinstall.sh` (see below).

### Flag System

System-wide flag store at `/usr/local/share/linux_post_install/flags/` (presence = set, content = optional value). Sourced via `lib/flags.sh` (or the installed `/usr/local/bin/flags.sh`):

```bash
source "$(dirname "$0")/lib/flags.sh" 2>/dev/null || source "$(dirname "$0")/flags.sh"

flag_set autostart        # green flag
flag_set app "2.1"        # green flag with a value
flag_is_set autostart     # test (0/1) — the primitive consumers use
flag_value app            # → "2.1"
flag_list                 # names of all set flags
flag_clear autostart
```

Writes use `run` + `sudo`, so they respect `--dry-run`. CLI equivalents: `flag-reader`, `flag-set`, `flag-clear`.

**Example — service gated on a flag** (in `postinstall.sh`'s systemd loop):

```bash
if [ "$svc_name" = "myapp.service" ] && ! flag_is_set myapp; then
    warn "myapp feature not installed — skipping myapp.service"
    continue
fi
```

---

## Working with Systemd

Create `systemd/<name>.service` — `postinstall.sh` copies it to `/etc/systemd/system/` and enables it automatically.

```ini
[Unit]
Description=My Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/your-script.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## Working with Config Files

1. Place the file in `config/`
2. Add copy logic to `postinstall.sh`:

```bash
if [ -f config/your-config.conf ]; then
    mkdir -p "$HOME/.config/your-app"
    cp config/your-config.conf "$HOME/.config/your-app/your-config.conf"
    chmod 600 "$HOME/.config/your-app/your-config.conf"
fi
```

---

## Docker Compose / ScaleTail

The installer clones [ScaleTail](https://github.com/tailscale-dev/ScaleTail) templates to `/usr/local/share/linux_post_install/scale-tail/` — 119+ self-hosted services with a Tailscale sidecar pattern. Each service gets a `tail-xxxxx.ts.net` URL via `network_mode: service:tailscale`.

### Config Strategy — Three Layers

Values cascade from least to most specific:

```
Template .env          (per-service defaults from ScaleTail)
       ↓
Global config          (~/.config/linux_post_install/compose.env)
       ↓
Per-service .env       (/srv/<service>/.env) — created on first deploy, NEVER overwritten
```

On first `pos docker compose up <service>`:
1. Template `.env` is copied to `/srv/<service>/.env`
2. Matching keys from global config are filled in
3. If `TS_AUTHKEY` is still empty, you're prompted to enter it
4. After that, the per-service `.env` is **never touched** — not even by `update`

### Layout

| Path | Purpose | Mutability |
|------|---------|------------|
| `/usr/local/share/linux_post_install/scale-tail/services/<name>/` | ScaleTail templates (git repo) | Read-only |
| `~/.config/linux_post_install/compose.env` | Your global defaults | Edit via `config set` or `config edit` |
| `/srv/<service>/` | Active deployment | Per-service `.env` preserved forever |

### Key Commands

| Command | Behaviour |
|---------|-----------|
| `pos docker compose up <service>` | Deploys to `$SERVICES_BASE/<service>/`, creates `config/` + `data/`, generates `.env` from global defaults |
| `pos docker compose down <service>` | Stops the stack |
| `pos docker compose update` | `git pull` templates + refreshes `compose.yaml` for all deployed services (`.env` untouched) |
| `pos docker compose config set K=V` | Sets a global default in `~/.config/linux_post_install/compose.env` |
| `pos docker compose config show` | Displays current global config and `SERVICES_BASE` |
| `pos docker compose config edit` | Opens global config in `$EDITOR` |

### Global Config Keys

| Key | Required | Default | Purpose |
|-----|----------|---------|---------|
| `TS_AUTHKEY` | Yes | — | Tailscale auth key for sidecar networking |
| `TZ` | No | `Europe/Amsterdam` | Timezone for services |
| `DNS_SERVER` | No | `9.9.9.9` | Custom DNS server |
| `SERVICES_BASE` | No | `/srv` | Root directory for all deployments |

---

## Commit Guidelines

- Use conventional prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
- Explain *why*, not just *what*
- One logical change per commit

```
feat: add pos-disk-usage for monitoring disk space
fix: pos-network-ip fails when no default route exists
docs: add example output for pos-network-scan
```

---

## Useful Commands

```bash
# Syntax check a single script
bash -n bin/my-script

# ShellCheck linting
shellcheck bin/my-script

# Check all scripts
for f in bin/* apps/*/*.sh lib/common.sh install.sh preinstall.sh postinstall.sh; do
    bash -n "$f" || echo "FAIL: $f"
done

# Init submodule
git submodule update --init

# Pull latest ScaleTail templates
git submodule update --remote compose/scale-tail

# Test install in Docker
docker run --rm -it -v $PWD:/repo ubuntu:22.04 bash
# inside: cd /repo && ./install.sh

# Test app installers
./apps/install.sh
./apps/install.sh --all
./apps/install.sh docker vscode
```
