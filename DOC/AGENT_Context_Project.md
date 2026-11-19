# AGENT Context — Linux_post_install Project

> **Purpose:** Single-source context document so any coding agent can understand the project, navigate the codebase, and make correct contributions.

---

## 1. Project Overview

**Linux_post_install** is a personal bootstrap and homelab toolkit for Debian/Ubuntu. One command turns a bare install into a fully productive machine:

- Automated system package installation (25+ packages)
- A unified CLI (`pos`) for network, Docker, and system tasks
- Optional desktop application installers (16 apps)

**Repository:** `https://gitea.skink-platy.ts.net/admin/Linux_post_install`
**Target OS:** Debian / Ubuntu (uses `apt`)
**Shell:** Bash (`#!/usr/bin/env bash`)

---

## 2. Directory Structure

```
Linux_post_install/
├── install.sh              # Main orchestrator — entry point
├── preinstall.sh           # Phase 1: system packages via apt
├── postinstall.sh          # Phase 3: PATH, completion, SSH keys
│
├── lib/
│   ├── common.sh           # Shared library (colors, logging, spinner, timer, run, load_env_file)
│   ├── flags.sh            # Flag store (flag_set/clear/is_set/value/list/status)
│   └── menu-lib.sh / usb-lib.sh / bank-lib.sh / registry.sh
│
├── bin/                    # CLI tools — installed to /usr/local/bin/
│   ├── pos                 # Main dispatcher — smart arg matching to pos-* scripts
│   ├── flag-reader         # Inspect flags (list/status/--raw)
│   ├── flag-set            # Set a flag (optionally with a value)
│   └── flag-clear          # Unset a flag
│
├── templates/              # Dev-only scaffolds — NOT installed by install.sh
│   ├── pos-tool.sh         # New `pos` CLI tool (→ bin/pos-<cat>-<cmd>)
│   └── app.sh              # New optional app installer (→ apps/<cat>/<name>.sh)
│
├── x64_bin/                # Precompiled binaries, copied to /usr/local/bin on x86_64
│   ├── create_ap           # Wi-Fi AP CLI (bash script)
│   ├── wihotspot           # Wrapper → wihotspot-gui
│   └── wihotspot-gui       # GTK3 hotspot GUI (x86-64 ELF)
│                           # future: arm64_bin/ picked up automatically on aarch64
│
├── apps/                   # Optional desktop app installers (by category)
│   ├── install.sh          # Interactive picker / orchestrator
│   ├── browsers/
│   │   └── brave.sh       # Brave Browser (APT repo)
│   ├── development/
│   │   └── vscode.sh      # VS Code (Microsoft APT repo)
│   ├── media/
│   │   ├── obs.sh         # OBS Studio (apt)
│   │   ├── scrcpy.sh      # scrcpy Android mirror (GitHub release)
│   │   └── vlc.sh         # VLC media player (apt)
│   ├── networking/
│   │   ├── netbird.sh     # NetBird VPN (official script)
│   │   ├── tailscale.sh   # Tailscale VPN (official script)
│   │   └── zerotier.sh    # ZeroTier VPN (official script)
│   ├── remote-access/
│   │   ├── termius.sh     # Termius SSH client (.deb)
│   │   └── vnc-viewer.sh  # TigerVNC Viewer (apt)
│   ├── system/
│   │   ├── docker.sh      # Docker Engine (get.docker.com)
│   │   └── qemu.sh        # QEMU + libvirt + KVM (apt)
│   └── utilities/
│       ├── affine.sh      # AFFiNE knowledge base (AppImage)
│       ├── btop.sh        # btop resource monitor (apt)
│       ├── localsend.sh   # LocalSend (flatpak)
│       └── tsui.sh        # Tailscale config TUI (official install script)
│
├── completions/
│   └── pos.bash            # Bash tab-completion for the pos CLI
│
├── config/                 # Gitignored secrets only (e.g. authorized_keys); no templates
├── README.md               # User-facing intro + quick start (links into DOC/)
│
├── DOC/                    # All documentation
│   ├── README.md           # Docs index
│   ├── SCRIPTS.md          # Installer scripts, libs — reference
│   ├── POS.md              # pos CLI reference
│   ├── APPS.md             # Optional apps reference
│   ├── DEV.md              # Developer guide
│   ├── HOWTO.md            # Hands-on guides index (per-category tutorials)
│   ├── howto/              # Per-category tutorials (docker, network, system)
│   ├── AGENT_Context_Project.md  # This file — coding agent context
│   └── algorithm.md        # Algorithm diagrams
│
└── .gitignore              # Excludes secrets, Python artifacts, OS files
```

---

## 3. Installation Flow

```
User runs: ./install.sh [--apps|--full|--dry-run|--force|--skip <phase>|--steps <spec>]
│
├─ Version gate: compares installed version (flag) vs current (0.0c<commit count>)
│   └─ match + no --force → "Already installed. Use --force to re-install." / exit 0
│       (--dry-run variant prints "Would skip install"); no git or no flag → skip gate
│
├─ Phase 1: preinstall.sh        (requires root)
│   └─ apt update + installs system packages + fail2ban
│
├─ Phase 2: install.sh           (requires root)
│   └─ Copies bin/* → /usr/local/bin/ (chmod 755)
│   └─ Copies lib/*.sh (common, flags, usb-lib, menu-lib, registry, bank-lib)
│      → /usr/local/bin/ (chmod 644)
│   └─ Copies x64_bin/* → /usr/local/bin/ on x86_64
│
├─ Phase 3: postinstall.sh       (runs as user)
│   └─ PATH export in ~/.bashrc
│   └─ Bash completion for pos CLI
│   └─ SSH authorized_keys (from config/authorized_keys)
│
└─ [if --apps or --full]: apps/install.sh
    └─ Interactive picker (or --all for non-interactive)
```

**After install, the repo can be deleted** — all tools live in `/usr/local/bin/`.

### install.sh Flags

| Flag | Purpose |
|------|---------|
| `--apps` | Run interactive app picker after core install |
| `--full` | Core install + all apps (non-interactive) |
| `--dry-run` | Preview without executing |
| `--force` | Re-install even if the version matches |
| `--skip <phase>` | Skip a phase (repeatable): `preinstall`, `scripts`, `postinstall`, `apps` |
| `--steps <spec>` | Run only specific phases. Format: `1,3` or `1-3` |
| `--no-color` | Disable colored output |

### pos Output Logging

All non-interactive `pos` commands log output to `~/.local/share/linux_post_install/logs/`:
- Per-command files: `YYYYMMDD_HHMMSS_pos_<cmd>.log` (full stdout+stderr)
- Main log: `pos.log` (command + timestamp + exit code for every invocation)
- Interactive commands (`system-firewall`, `system-backup`, `docker-vbox`) only log invocation, not output

---

## 4. The `pos` CLI System

### How It Works

`bin/pos` is the main dispatcher. It:
1. Scans its own directory for all executable `pos-*` files
2. Extracts category-subcommand names from filenames
3. Uses variable-length argument matching to find the right script

**Example:** `pos system backup --service --no-encrypt`
- Tries `pos-system-backup-service---no-encrypt` (not found)
- Tries `pos-system-backup-service` (not found)
- Finds `pos-system-backup` (runs with args `--service --no-encrypt`)

### Available Commands

| Category | Commands |
|----------|----------|
| `docker` | `health`, `ps`, `stack`, `vbox` |
| `network` | `checkport`, `hotspot`, `ip`, `scan` |
| `system` | `backup`, `bank`, `firewall`, `health`, `uninstall` |
| *(category-less)* | `tree` |

Run `pos tree` for the authoritative live list. See `DOC/POS.md` for the full CLI reference.

### pos docker vbox Details

`pos-docker-vbox` manages disposable Docker containers as lightweight VMs:

- **Container labeling:** All created containers get `linux_post_install.vbox=true` label
- **`ls` filtering:** `docker ps --filter label=linux_post_install.vbox=true` — only shows vbox-managed containers
- **Post-create prompt:** After `create`, asks "Enter now? [Y/n]" using `confirm` helper
- **Working dir detection:** `enter` auto-detects bind mount path from container labels
- **Custom dirs:** `--dir <path>` or `--dir .` for current directory

---

## 5. Shared Library — `lib/common.sh`

Sourced by most scripts. Provides:

| Function | Purpose |
|----------|---------|
| `log "msg"` | Green `[+]` status message |
| `warn "msg"` | Yellow `[!]` warning |
| `err "msg"` | Red `ERROR:` + exit 1 |
| `ok "msg"` | Green `OK` prefix |
| `section "title"` | Cyan-bordered section header |
| `step N T "msg"` | Numbered step header (e.g., `[1/4] Installing`) |
| `run cmd` | Executes command, respects `$DRY_RUN` |
| `spawn "msg" cmd` | Runs with animated braille spinner, elapsed time, OK/FAIL status; respects `$DRY_RUN` |
| `timer_start` / `timer_stop` | Elapsed time tracking |
| `confirm "prompt" [default]` | y/N or Y/n prompt |
| `load_env_file <name\|path>` | Loads KEY=VALUE pairs from a runtime env file (basename → `~/.config/linux_post_install/`); env already exported wins |

**Auto-detects TTY** — disables colors when piped.

**Source pattern:**
```bash
source "$(dirname "$0")/../lib/common.sh"
```

---

## 6. Optional Apps (`apps/`)

### How They Work

- `apps/install.sh` auto-discovers all `apps/<category>/*.sh` files (excluding itself)
- Three modes: interactive (default), `--all`, or specific app names as arguments
- `--uninstall` switches to uninstall mode (same selection, invokes app scripts with `uninstall` argument)
- Interactive TUI groups apps by category with section headers
- Each app script is standalone, idempotent, sources `lib/common.sh`
- Every app script defines `install_<name>()` **and** `uninstall_<name>()`, dispatched via `case "${1:-}" in uninstall) ...`

### Installation Methods

| Method | Apps |
|--------|------|
| `apt install` | btop, obs, vlc, vnc-viewer, qemu |
| APT repo (GPG + repo) | brave, vscode |
| Official `curl \| sh` | docker, tailscale, netbird, zerotier |
| AppImage | affine |
| GitHub release binary | scrcpy |
| Flatpak | localsend |
| .deb package | termius |

### Adding a New App

1. Create `apps/<category>/<name>.sh` following the template in DOC/DEV.md
2. It auto-appears in the interactive picker — no registration needed

---

## 7. Background Services

None — pos is a standalone CLI toolkit: no systemd units are shipped or installed, no timers are scheduled, and no pos-managed daemons run. `postinstall.sh` only writes user config (fail2ban jail, PATH, bash completion). Leftover units from older installs are swept by `pos system uninstall`.

---

## 8. Configuration Files

### Gitignored Secrets

- `config/authorized_keys` — SSH public keys

### Runtime Config

There is no config UI or config templates. Tools read plain environment variables (env already exported wins); `load_env_file` from `lib/common.sh` can read a hand-written `~/.config/linux_post_install/<name>.env` (chmod 600, never commit).

- `pos system backup` / `pos system health` — `BACKUP_SERVICE_ROOTS`, `HEALTH_BACKUP_MAX_AGE_DAYS`
- `~/.bashrc` — Modified by postinstall (PATH, bash completion)

### Flags

System-wide flag store at `/usr/local/share/linux_post_install/flags/`:
- One file per flag; **presence = set**, **file content = optional value** (dir 755, files 644).
- Library: `lib/flags.sh` (installed as `/usr/local/bin/flags.sh`) — `flag_set <name> [value]`, `flag_clear <name>`, `flag_is_set <name>`, `flag_value <name>`, `flag_list`, `flag_status <name>`.
- CLI: `flag-reader` (list / status / `--raw`), `flag-set`, `flag-clear`.
- Main consumer: `installed_version` — `install.sh` records the repo version there so a later run can compare it against the installed one (version gate).
- Writes use `run` + `sudo`, so they respect `--dry-run`. `FLAGS_DIR` is env-overridable for tests.

---

## 9. Coding Conventions

### Script Standards

- **Shebang:** `#!/usr/bin/env bash`
- **Strict mode:** `set -euo pipefail`
- **Help:** Every script accepts `-h`/`--help` via `case` pattern
- **Idempotency:** Check existence before creating/modifying
- **Exit codes:** 0 = success, 1 = error

### Naming Conventions

- `pos-<category>-<command>` — canonical tool names
- `apps/<category>/<name>.sh` — optional app installers
- Hyphens for word separation, lowercase always

### Error Handling

- `command -v <tool> &>/dev/null` to check tool availability
- `set -euo pipefail` for fail-fast
- `err()` for fatal errors, `warn()` for non-fatal
- Confirmation prompts for destructive actions

### Security

- Never hardcode secrets in scripts
- Use `chmod 600` for sensitive files
- Validate user input before shell commands
- Use `sudo` only where necessary

---

## 10. Development Workflow

### Adding a New App

1. Create `apps/<category>/<name>.sh` from `templates/app.sh` (per DOC/DEV.md)
2. It auto-appears in the interactive picker — no registration needed
3. Update `DOC/APPS.md` catalog table (name, category, purpose, install method)
4. Test: `bash -n apps/<cat>/<name>.sh && shellcheck apps/<cat>/<name>.sh`

### Adding a New Tool

0. Define the exact CLI verb (`pos <category> <command> [<subcommand>]`) and its runtime context before writing code: a **dev/repo-only** tool (e.g. reads repo files, like `pos tree`) or a **runtime** tool that must work from `/usr/local/bin` after the repo is deleted. Category-less `bin/pos-<cmd>` is for dispatcher/dev-level commands that fit no category (`pos-config`, `pos-tree`); everything else goes in a category.
1. Create `bin/pos-<category>-<command>` (or `bin/pos-<cmd>` for category-less) from `templates/pos-tool.sh` — must be executable (`100755`); it auto-appears in `pos <category> --help` (filename-derived, no registration)
2. Add the `# POS: <cat> <cmd> — <one-line description>` header right after the shebang (plus `# POS_FLAGS: ...` for flag-style tools and `# POS_SUBCMDS: ...` for multi-command tools) — this is the single source of truth for the generated docs; nested tools (`pos-<cat>-<a>-<b>`) auto-list under their parent tool
3. Add to `INTERACTIVE_CMDS` in `bin/pos` if it reads stdin
4. Add system deps to `PACKAGES` array in `preinstall.sh` (if needed); non-apt/manual installers → `command -v` guard in the tool instead
5. Runtime tool config is a plain env var (optionally in a hand-written `~/.config/linux_post_install/<name>.env`, chmod 600); use `load_env_file` from `lib/common.sh`
6. Update docs by hand: `DOC/POS.md` (command table + detail), `DOC/HOWTO.md` index row + a section in `DOC/howto/<category>.md`, and `AGENT_TODO.md` Done (dated) in the same commit
7. Test: `bash -n <file>`, `bin/pos help <full command>`, `bin/pos <category> --help`, `bin/pos tree`, and `git diff --check`. There is no test suite or gate tooling

### Testing

```bash
for f in bin/* apps/*/*.sh lib/*.sh install.sh preinstall.sh postinstall.sh; do
    bash -n "$f" || echo "FAIL: $f"
done
bin/pos tree
bash apps/install.sh --all
```

### Commit Conventions

Use conventional prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`

---

## 11. Key File Quick Reference

| File | Purpose |
|------|---------|
| `install.sh` | Main orchestrator — 3 phases, `--force`, version gate |
| `preinstall.sh` | apt packages + hotspot deps + fail2ban |
| `postinstall.sh` | PATH, bash completion, SSH authorized_keys |
| `lib/common.sh` | Shared helpers (log/warn/err/run/spawn, `load_env_file`, CONFIG_DIR) |
| `lib/flags.sh` | Flag store (set/clear/is_set/value/list/status) |
| `lib/registry.sh` | POS header query API used by `pos tree` |
| `lib/menu-lib.sh` / `lib/usb-lib.sh` / `lib/bank-lib.sh` | Interactive menus, USB detection, command bank storage |
| `bin/pos` | CLI dispatcher + logging |
| `bin/flag-reader` / `flag-set` / `flag-clear` | Flag store CLIs |
| `completions/pos.bash` | Dynamic bash completion |
| `apps/install.sh` | App install/uninstall picker |

---

## 12. Common Tasks for Agents

| Task | Where to Edit |
|------|---------------|
| Add a new CLI tool | Create `bin/pos-<cat>-<cmd>` with a `# POS:` header, chmod +x, add deps (apt → `preinstall.sh` PACKAGES; non-apt → `command -v` guard), then test with `bash -n` and `pos tree` |
| Verify syntax | `bash -n <file>`; `bin/pos tree` lists every command |
| Add a new app installer | Create `apps/<category>/<name>.sh` (auto-discovered) |
| Add a precompiled binary | Drop it in `x64_bin/` — auto-copied by Phase 2 |
| Inspect/set flags | `flag-reader`, `flag-set`, `flag-clear` (or source `lib/flags.sh`) |
| Modify package list | Edit `PACKAGES` array in `preinstall.sh` |
| Change PATH or bash config | Edit `postinstall.sh` |
| Add bash completion | Edit `completions/pos.bash` |
| Modify Docker views / VM logic | Edit `bin/pos-docker-*` |
| Modify USB backup-copy logic | Edit `bin/pos-system-backup` / `lib/usb-lib.sh` |
| Modify UFW/firewall logic | Edit `bin/pos-system-firewall` |
| Modify install phases/flags | Edit arg parsing in `install.sh` |
| Update documentation | Edit the relevant doc under `DOC/` (index: `DOC/README.md`) |
