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
| Install | `install.sh` | Copies `bin/*` → `/usr/local/bin/` (chmod 755), `lib/common.sh` → `/usr/local/bin/common.sh` |
| Post | `postinstall.sh` | User config (SSH keys, PATH, bash completion), systemd services |

Each phase is independent and runs only if the corresponding script exists.

### Directory Layout

| Directory | Purpose | Installed To |
|-----------|---------|-------------|
| `bin/` | Daily-use CLI tools and wrappers | `/usr/local/bin/` |
| `apps/<category>/` | Optional desktop app installers | run on demand |
| `lib/` | Shared library (`common.sh`) | sourced at build time |
| `config/` | Gitignored user config files | `~/.config/<app>/` (via postinstall) |
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

### 2. Add system dependencies

Add package names to the `PACKAGES` array in `preinstall.sh`:

```bash
PACKAGES=(
    ...
    your-package
)
```

### 3. Add config files (if needed)

Place defaults in `config/` and add copy logic to `postinstall.sh`. If they contain secrets, add to `.gitignore` and document in README.

### 4. Add SSH keys (if needed)

Place public keys in `config/authorized_keys` (one per line). `postinstall.sh` reads this file automatically.

### 5. Update README

Add a section under the relevant category in README.md.

### 6. Test

```bash
bash -n bin/your-tool
shellcheck bin/your-tool
./bin/your-tool --help
```

---

## Adding an Optional App

### 1. Create the installer

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_myapp() {
    command -v myapp &>/dev/null && { log "myapp already installed"; return 0; }
    spawn "Installing myapp" sudo apt install -y myapp
}

install_myapp
```

Place it in `apps/<category>/<name>.sh`. It auto-appears in the picker — no registration needed.

**Categories:** `browsers`, `development`, `media`, `networking`, `remote-access`, `system`, `utilities`

### 2. Conventions

- Idempotent: check `command -v` before installing
- APT packages → `sudo apt install -y` inside `spawn`
- Official scripts → `curl ... | sh` inside `spawn`
- Flatpak → `flatpak install -y flathub <app-id>` inside `spawn`
- `.deb` files → download to temp, `sudo apt install -y ./file.deb` inside `spawn`
- `usermod` for groups → print re-login reminder

---

## Editing an Existing Tool

1. Find the script in `bin/`
2. Understand its contract (args, output, exit codes)
3. Make the change — keep it idempotent
4. Update README if behaviour changed
5. Run `shellcheck` on the modified file

---

## Best Practices

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

- Never hardcode secrets — put them in `config/` (gitignored)
- `chmod 600` for sensitive files
- Validate input before shell commands
- Use `sudo` only where needed

### Naming

- CLI tools: `bin/pos-<category>-<command>`
- Legacy wrappers: `bin/wr-*`
- App installers: `apps/<category>/<name>.sh`
- Lowercase with hyphens

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
