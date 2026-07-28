# Development Guide

How this repo works, how to add features, and what to keep in mind when editing.

---

## Concepts

### Three-Phase Installation

The installer runs in three sequential phases:

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
| Pre | `preinstall.sh` | System packages, apt repositories, global binaries (yt-dlp) |
| Install | `install.sh` | Copies everything in `bin/` to `/usr/local/bin` with `chmod 755` |
| Post | `postinstall.sh` | User config (SSH, rclone), `~/.bashrc`, systemd services |

Each phase is independent and is only run if the corresponding file exists.

### Script Categories

| Directory | Purpose | Installed To |
|-----------|---------|--------------|
| `bin/` | Daily-use tools and wrappers | `/usr/local/bin/` |
| `apps/<category>/` | Optional desktop apps (by category) | run on demand |
| `lib/` | Shared library (`common.sh`) | sourced at build time |
<<<<<<< HEAD
| `config/` | Static config files + SSH authorized_keys | `~/.config/<app>/` (via postinstall) |
=======
| `config/` | Static config files (gitignored — user adds their own) | `~/.config/<app>/` (via postinstall) |
>>>>>>> bba577c (Initial commit)
| `compose/` | ScaleTail templates (dev reference only) | cloned to `/usr/local/share/mylinux/scale-tail` on install |
| `systemd/` | Systemd service unit files | `/etc/systemd/system/` (via postinstall) |

### Key Files Added

| File | Purpose |
|------|---------|
<<<<<<< HEAD
| `.gitignore` | Prevents secrets (rclone tokens) and build artifacts from being committed |
| `config/authorized_keys` | SSH public keys read by `postinstall.sh` (replaces hardcoded key) |ls

=======
| `.gitignore` | Prevents secrets (rclone tokens, SSH keys) and build artifacts from being committed |
>>>>>>> bba577c (Initial commit)
| `~/.config/mylinux/compose.env` | Global Docker Compose defaults (`TS_AUTHKEY`, `TZ`, `DNS_SERVER`, `SERVICES_BASE`) — created by `wr-compose config` |

---

## How to Add a New Tool

### 1. Create the script in `bin/`

```bash
#!/usr/bin/env bash

set -euo pipefail

# Use the shared library for colors and helpers (preferred)
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

**Conventions to follow:**

- **Shebang:** `#!/usr/bin/env bash` (portable across distros)
- **Strict mode:** `set -euo pipefail` at the top
- **`--help` flag:** all tools must accept `-h` / `--help` — use the `case ... esac` pattern above
- **Shared library:** source `lib/common.sh` from any script in `bin/` or `apps/` for consistent colors, logging (`log`, `warn`, `err`, `ok`), spinners (`spawn`), and dry-run support (`run`). Use `spawn "message" command` for long-running installs.
- **Fallback (no lib):** if sourcing `common.sh` is not desired, inline:
  ```bash
  log()  { echo "[+] $*"; }
  warn() { echo "[!] $*"; }
  err()  { echo "ERROR: $*" >&2; exit 1; }
  ```
- **Exit codes:** `0` for success, `1` for error

### 2. Add system dependencies (if any)

Open `preinstall.sh` and add the package name to the `PACKAGES` array:

```bash
PACKAGES=(
    ...
    your-package
)
```

### 3. Add runtime configuration (if any)

If the tool needs a config file:
- Place the file in `config/`
- Add copy logic in `postinstall.sh`

If the file contains secrets (tokens, keys):
- Add it to `.gitignore`
- Document in README how to create it manually

<<<<<<< HEAD
### 4. Add SSH keys (if needed)

Place public keys in `config/authorized_keys` (one per line).
`postinstall.sh` reads from this file automatically.

=======
>>>>>>> bba577c (Initial commit)
### 5. Update README.md

Add a section under **Tools Reference** following the existing format.

### 6. Test

```bash
# Syntax check
bash -n bin/your-tool

# ShellCheck linting
shellcheck bin/your-tool

# Run directly
./bin/your-tool --help
```

---

## How to Edit an Existing Tool

1. **Find the script** — all tools live in `bin/`
2. **Understand the contract** — what args does it expect? What does it print? What exit codes?
3. **Make the change** — keep it idempotent if possible (running twice = same result)
4. **Update README** if usage, output, or behaviour changed
5. **Run `shellcheck`** on the modified file:
   ```bash
   shellcheck bin/your-tool
   ```

---

## How to Add a New App

App installers live in `apps/<category>/` and follow a simple pattern. Each is a standalone script that can be run independently.

### Template

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

Note: app scripts are now in `apps/<category>/`, so the source path to `common.sh` is two levels up (`../../lib/common.sh`).

### Conventions

- **Shebang:** `#!/usr/bin/env bash`
- **Strict mode:** `set -euo pipefail`
- **Shared library:** always source `lib/common.sh` from the app directory
- **Idempotent:** check `command -v` before installing; skip if present
- **Method:** standardize on official repos/scripts over PPAs or third-party
- **APT packages** → `sudo apt install -y <pkg>` wrapped in `spawn`
- **Official scripts** → `curl ... | sh` inside `spawn`
- **Flatpak** → `flatpak install -y flathub <app-id>` inside `spawn`
- **`.deb` files** → download to temp and `sudo apt install -y ./file.deb` inside `spawn`
- **Groups:** `usermod` commands print a re-login reminder (`log "Log out and back in for group changes to take effect"`)

### Adding to the picker

`apps/install.sh` auto-discovers all `apps/<category>/*.sh` files (excluding itself). Just create the script in the appropriate category subdirectory and it will appear in the interactive prompt under that category.

Categories: `browsers`, `development`, `media`, `networking`, `remote-access`, `system`, `utilities`.

---

## Best Practices

### Idempotency

Scripts should be safe to run multiple times:
- Check if something exists before creating it
- Use `>>` with checks (grep for existing content) instead of blindly appending
- Don't overwrite configs that the user may have customized

### Error Handling

```bash
# Fail fast
set -euo pipefail

# Check for required commands
if ! command -v docker &>/dev/null; then
    echo "docker not found"
    exit 1
fi

# Check arguments
if [[ -z "${1:-}" ]]; then
    echo "Usage: my-tool <argument>"
    exit 1
fi
```

### Portability

This repo targets **Debian** and **Ubuntu**. Keep in mind:
- Use `apt` not `apt-get` unless you need non-interactive guarantees
- Assume `bash` is at `/usr/bin/env bash`
- Prefer POSIX-safe patterns when possible
- Check for command availability with `command -v`

### Dry-run support

Scripts that make changes (`install.sh`, `preinstall.sh`) support `--dry-run`:

```bash
./install.sh --dry-run    # preview without executing
```

Use the `run()` helper pattern:

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

- **Never hardcode secrets** in scripts (SSH keys, API tokens, passwords) — put them in `config/` files that are `.gitignore`d
- Use `chmod 600` for sensitive files (SSH keys, rclone config)
- Validate user input before using it in shell commands
- Use `sudo` only where necessary; don't run the whole script as root if only one command needs elevation

### Naming

- Prefix personal wrappers with `wr-` (e.g., `wr-ip`, `wr-docker`)
- Keep names lowercase, use hyphens for word separation
- Name should hint at the tool's purpose (`wr-scan-ping`, `wr-checkport`)

---

## Working with Systemd

### Adding a new service

1. Create `systemd/<name>.service`
2. postinstall.sh automatically copies all `*.service` files to `/etc/systemd/system/` and enables them

Service file template:

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
2. Add a section to `postinstall.sh`:

```bash
if [ -f config/your-config.conf ]; then
    mkdir -p "$HOME/.config/your-app"
    cp config/your-config.conf "$HOME/.config/your-app/your-config.conf"
    chmod 600 "$HOME/.config/your-app/your-config.conf"
    echo "Installed your-config.conf"
fi
```

---

## Working with Docker Compose

The installer clones [ScaleTail](https://github.com/tailscale-dev/ScaleTail) templates to `/usr/local/share/mylinux/scale-tail/` — a library of 119+ self-hosted services with a **Tailscale sidecar** pattern. Each service runs with `network_mode: service:tailscale`, gets a `tail-xxxxx.ts.net` URL, and optional automatic HTTPS via Tailscale Serve or Funnel.

### Architecture (after install)

```
/usr/local/share/mylinux/scale-tail/   # ScaleTail templates (git repo)
└── services/<name>/
    ├── compose.yaml     # Service definition (Tailscale + app containers)
    └── .env             # Template variables (SERVICE, IMAGE_URL, TS_AUTHKEY, TZ, ...)

~/.config/mylinux/compose.env          # Global defaults — set via wr-compose config

<SERVICES_BASE>/<name>/                # Active deployments (default: /srv/<name>)
    ├── compose.yaml     # Copied from template (refreshed on wr-compose update)
    ├── .env             # Your real config — preserved across updates
    ├── config/          # Service configuration data
    └── data/            # Service persistent data
```

### `wr-compose` commands

| Command | Behaviour |
|---------|-----------|
| `wr-compose up <service>` | Deploys service to `$SERVICES_BASE/<service>/` (default: `/srv`), creates `config/` + `data/` dirs, generates `.env` from global config (prompts for `TS_AUTHKEY` if empty), runs `docker compose up -d` |
| `wr-compose down <service>` | Runs `docker compose down` in the service directory |
| `wr-compose update` | `git pull` in ScaleTail templates dir, then re-copies `compose.yaml` into all deployed directories — `.env` files are left untouched |
| `wr-compose config set K=V` | Persists a value in `~/.config/mylinux/compose.env` (e.g. `TS_AUTHKEY`, `TZ`, `DNS_SERVER`, `SERVICES_BASE`) |

### Portable `.env` design

- **Global**: `~/.config/mylinux/compose.env` — one place for `TS_AUTHKEY`, `TZ`, `DNS_SERVER`, `SERVICES_BASE`.
- **Per-service**: `<SERVICES_BASE>/<service>/.env` — generated from the ScaleTail template on first deploy, with empty values filled from the global config.
- **On update**: `wr-compose update` refreshes only `compose.yaml` from the templates; `.env` files are preserved.
- **Services path**: set `SERVICES_BASE` to any directory (e.g. `/srv`) via `wr-compose config set SERVICES_BASE=/srv`. Defaults to `/srv`.

This means `wr-compose` works anywhere — no repo clone needed after install. Just set `TS_AUTHKEY` once and deploy.

### Contributing upstream

ScaleTail provides a [service template](https://github.com/tailscale-dev/ScaleTail/tree/main/templates/service-template). To add a service:

1. Fork ScaleTail and add your service under `services/<name>/`
2. Submit a PR upstream
3. Changes are picked up by `wr-compose update`

---

## Commit Guidelines

- Use conventional commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`
- Explain *why* the change was made, not just *what* changed
- Keep commits focused — one logical change per commit

Examples:

```
feat: add wr-mytool for monitoring disk usage
fix: wr-ip fails when no default route exists
docs: add example output for wr-scan-ping
```

---

## Useful Commands

```bash
# Syntax-check a script without running it
bash -n bin/my-script
bash -n apps/utilities/myapp.sh

# ShellCheck linting
shellcheck bin/my-script
shellcheck apps/utilities/myapp.sh

# Quick syntax check all scripts
for f in bin/* apps/*/*.sh lib/common.sh install.sh preinstall.sh postinstall.sh; do
    bash -n "$f" || echo "FAIL: $f"
done

# Initialize submodule after clone
git submodule update --init

# Pull latest ScaleTail services
git submodule update --remote compose/scale-tail

# List available compose services
./bin/wr-compose ls

# Test install in Docker
docker run --rm -it -v $PWD:/repo ubuntu:22.04 bash
# inside container: cd /repo && ./install.sh

# Test app installation interactively
./apps/install.sh
./apps/install.sh --all        # install all apps
./apps/install.sh docker vscode # install specific apps
```
