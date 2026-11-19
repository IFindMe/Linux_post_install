# Development Guide

How this repo works, how to add tools, and what to keep in mind when editing.

---

## Architecture

### Installation Phases

```
                  install.sh
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    preinstall.sh   bin/*    postinstall.sh
    (packages)   → /usr/local/bin  (config)
```

| Phase | Script | Responsibility |
|-------|--------|----------------|
| Pre | `preinstall.sh` | System packages and apt repos |
| Install | `install.sh` | Copies `bin/*` → `/usr/local/bin/` (chmod 755), all `lib/*.sh` → `/usr/local/bin/` (chmod 644) |
| Post | `postinstall.sh` | User config (SSH keys, PATH, bash completion) |

Each phase is independent and runs only if the corresponding script exists.

### Directory Layout

| Directory | Purpose | Installed To |
|-----------|---------|-------------|
| `bin/` | Daily-use CLI tools | `/usr/local/bin/` |
| `apps/<category>/` | Optional desktop app installers | run on demand |
| `lib/` | Shared libraries: `common.sh` (helpers + `load_env_file`), `flags.sh` (flag store — `installed_version` + misc flags), `registry.sh` (shared query API for POS tool metadata headers), `menu-lib.sh` (category-neutral menu primitives: guard/looping menu/filter picker/prompt), `usb-lib.sh` (USB storage detection/mount/pick for backups), `bank-lib.sh` (command-bank helpers) | sourced at build time |
| `config/` | Gitignored user secret (`authorized_keys`) | read by `postinstall.sh` |

### The `pos` CLI

`bin/pos` is a smart dispatcher. It scans its own directory for executable `pos-*` files and uses variable-length argument matching:

```
pos system bank alias remove work
  → tries pos-system-bank-alias-remove  (not found)
  → finds pos-system-bank-alias         → runs with args "remove work"
```

All non-interactive commands log to `~/.local/share/linux_post_install/logs/`.

`pos help <full command>` shows a tool's help, e.g. `pos help system bank` (all words joined with dashes → `pos-system-bank --help`). `pos <category>` or `pos <category> --help` shows a category's subcommands (derived from the `pos-<category>-*` filenames in `bin/` — no script execution, so it works even for root-only/interactive tools like `system-firewall`).

**When adding a command, `bin/pos` itself has one thing to keep in sync:**

- **The usage text** (`usage()` function) — the CATEGORIES block is **auto-derived** from the `pos-*` filenames in `bin/` (no manual edit, can't drift). The EXAMPLES block is the only hand-maintained part: add a line there only if you want the tool showcased in `pos --help`.
- **`INTERACTIVE_CMDS`** (space-separated list above the dispatch loop) — commands that **read stdin** (password prompts, selection menus: `system-firewall`, `system-backup`) must be added here. Everything else is piped through `tee` for logging, which would hang or swallow an interactive prompt. sudo's own password prompt is unaffected — it reads from `/dev/tty`. Trade-off: it's all-or-nothing **per script** — adding a flag-style tool with *any* prompting subcommand means *every* subcommand of that script skips output logging.

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
| `confirm "prompt" [default]` | y/n prompt; Enter accepts the default (`y` when omitted) |

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
- **Deps guards run before `--help`:** `command -v <bin> &>/dev/null || err "… (install <pkg>)"` lines sit at the top of the script, **before** the `-h|--help` case — so `--help` also errors when a dependency is missing. This matches every existing deps-gated tool; keep it that way.
  - Exception — tools with **no required deps** (every check degrades gracefully): `pos system health` probes binaries at runtime (`if command -v docker; then …`, `if command -v fail2ban-client; then …`) and needs no guard. A graceful-degradation probe (`if command -v …; then …`) is not a required-deps guard, so it does not need to precede `--help`. If you add a tool like this, keep all checks optional and note it in `usage()`.
- Shared library: always source `common.sh` for colors, logging, spinners
- Exit codes: `0` success, `1` error
- No shared lib? Inline fallbacks:
  ```bash
  log()  { echo "[+] $*"; }
  warn() { echo "[!] $*"; }
  err()  { echo "ERROR: $*" >&2; exit 1; }
  ```
  If you skip `common.sh`, add the tool to the "Scripts that do NOT source common.sh" list in `DOC/AGENT_Context_Project.md` by hand.

### 2. Make it discoverable

- The dispatcher auto-discovers executable `bin/pos-*` files — no registration needed. The file **must be executable** (`chmod +x`, committed as mode `100755`); the dispatcher and `install.sh` skip non-executables.
- `pos <category> --help` (and bare `pos <category>`) is derived from the `pos-<category>-*` filenames too — a new tool appears in its category's help automatically, with no registration (see [The `pos` CLI](#the-pos-cli)).
- **Add the `# POS:` header** (single source of truth for tool metadata) right after the shebang/strict-mode lines:
  ```bash
  # POS: <category> <command> — one-line description
  # POS_FLAGS: --flag1 --flag2      # ONLY for flag-style tools
  # POS_SUBCMDS: sub1 sub2          # ONLY for multi-command tools
  # POS_DEPS: binary1 binary2       # Optional: runtime deps (space-separated binary names)
  # POS_EXAMPLES: pos <tool> <args> | Description  # Optional: usage examples
  ```
  These headers are read at runtime by `lib/registry.sh` (the shared query API) — notably by `bin/pos tree` and by `pos <category> --help` in `bin/pos`. `POS_FLAGS` and `POS_SUBCMDS` carry flag/subcommand metadata; `POS_DEPS` lists runtime binary names that `command -v` would check (use when the tool needs binaries beyond what `preinstall.sh` installs, shown as `[deps: …]` in `pos tree`); `POS_EXAMPLES` holds curated usage examples (one per line, pipe-delimited `command | description`) shown in `pos tree`. The optional headers degrade gracefully when absent. Only the text after the first `— ` is used as the description — the `<category> <command>` words before it are convention-only (for nested tools, keep the full path there).
- **Category-less vs categorized:** most tools are `bin/pos-<category>-<command>`. The only category-less tool is `bin/pos-tree` (dispatcher/dev-level) — it documents like any other tool but shows with an empty category in `pos tree`.
- Nested tools are auto-detected from filenames: the trailing segment of a `bin/pos-<category>-<x>-<y>` name is offered as a subcommand of the parent tool in `pos <category> --help` and tab-completion, instead of appearing as a flat sibling. The flat dash-form still dispatches.
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

**Not in apt?** If the dependency ships as a manual installer (no package), do **not** put it in `PACKAGES` (that would break `preinstall.sh`). Instead, add a `command -v <binary> || err "… install from <URL>"` guard in the tool itself and note the manual install in `usage()`/`DOC/POS.md`.

### 4. Runtime config (if needed)

Tools that need user settings read plain environment variables, with precedence **flags > environment > file**. User-specific values live in a hand-written `~/.config/linux_post_install/<name>.env` (`chmod 600`) — never committed. There is no config UI and no shipped config templates: nothing to register or generate, just document the variable names in `DOC/POS.md`.

- **Canonical loader:** `load_env_file <file|basename>` in `lib/common.sh` — the shared KEY=VALUE loader (reads `^[A-Z_]+=` lines, skips blank + `#` comments, strips trailing CR and one pair of quotes, and exports a key only when that env var is not already set → **env always wins over the file**; loaded keys are appended to the global `LOADED_ENV_KEYS`). A bare basename resolves under the XDG-aware `CONFIG_DIR`; a full path is used as-is. A missing/unreadable file is a quiet no-op; the loader never creates files and never chmods. Source it with the standard fallback chain: `source "$(dirname "$0")/../lib/common.sh"`.
- `system.env` — settings for `pos system backup` / `pos system health` (`BACKUP_SERVICE_ROOTS`, `BACKUP_USB_ROOT`, `HEALTH_BACKUP_MAX_AGE_DAYS`, …), hand-written by the user. Env already exported wins over the file.

### 5. Add SSH keys (if needed)

Place public keys in `config/authorized_keys` (one per line). `postinstall.sh` reads this file automatically.

### 6. Update the docs

- `DOC/POS.md`: add the command to the section table + a detail block (commands, behavior, configuration). This is the hand-written CLI reference.
- `DOC/HOWTO.md` index row + a hands-on section in `DOC/howto/<category>.md` (recipes + troubleshooting) for user-facing tools.
- `DOC/AGENT_Context_Project.md` (bin tree, dispatch table, no-common.sh list, line-count table) and `completions/pos.bash` (flags/subcommand completion) are hand-maintained — update the relevant entries for the new tool. `pos tree` is the authoritative command list, so verify the tree and category help match afterwards.
- `AGENTS.md` Quick facts: update if a structural fact changed (new category, new convention).
- Root `README.md`: only if the `pos` category list in the help text changes.
- Move the finished task to the `Done` section of `AGENT_TODO.md` (dated) in the same commit.

### 7. Verify manually

There is no build step, test suite, or CI gate — verification is manual:

```bash
bash -n bin/your-tool                  # syntax
./bin/your-tool --help                 # help works (deps guards must still fire before it)
bin/pos help <full command>            # dispatch works
bin/pos tree                           # tool appears in the command tree
bin/pos <category> --help              # category listing includes the tool
bin/pos --help                         # top-level usage still renders
git diff --check                       # whitespace hygiene — run last, before committing
```

Ensure the file is executable (`chmod +x`, committed as mode `100755`) — see step 2.

Also do an env-seam review: every path the tool writes must be `VAR="${VAR:-default}"`-guarded. Grep for config writes without a `:-` guard:

```bash
grep -nE '>\s*(\$HOME|/etc)' bin/your-tool lib/your-lib
```

Each hit needs the seam; prove it with `VAR=/tmp/x bin/your-tool …` and assert the real path is untouched. `git diff --check` is the final self-check before committing — there is no hook or CI to fall back on.

### Testing tools that need root / missing deps

The manual checks above only prove syntax, exec bits, whitespace and dispatch — not behaviour. For tools that need `sudo` or binaries absent from the dev box (samba, usbsrv, …), test them end-to-end with two patterns:

- **Env-overridable paths.** Anything that touches a system config location gets an env override whose default is the real path — the seam that lets the tool be exercised against temp files. Precedents: `FLAGS_DIR` (`lib/flags.sh`), and the USB layer used by `pos system backup`: `USB_MOUNT_BASE` (default `/media`, keeps `BACKUP_MOUNT_BASE` as an alias) and `USB_BYID` (default `/dev/disk/by-id`, keeps `BACKUP_USB_BYID` as an alias) — both guarded as `VAR="${VAR:-${BACKUP_…:-default}}"` in `lib/usb-lib.sh` so existing config lines keep working. Pick a short tool-specific name and don't advertise it in `usage()` — it's a test seam, not user-facing. **Gotcha (session-learned):** a `VAR="${XDG…:-…}"` without the leading `VAR:-` *overrides* the seam — the stub run then silently writes to the real `$HOME` path and every assertion passes while the bug hides. The override must be written first, then tested with `VAR=/tmp/x …` and a check that the real path is untouched.
- **Stub PATH.** Create a temp dir with fake binaries, then run the tool with `PATH="$stubs:$PATH"`: fake `sudo` → `exec "$@"`; fake external tools → echo their args; fake validators → succeed on the temp copy. Assert on output **and** exit codes — happy path plus each failure path (`err` sets rc=1).
- **Interactive prompts** (`read … </dev/tty`): drive them with a PTY — `printf 'answer\n' | script -qec "cmd" /dev/null` — then assert the side effect (e.g. an encrypted archive lands with the right mode).

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

### Confirmation prompts

`confirm()` rule: Enter accepts the displayed default; destructive call sites pass explicit `'n'`.

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
- Mask secrets in any output that displays them
- Validate input before shell commands
- Use `sudo` only where needed

### Naming

- CLI tools: `bin/pos-<category>-<command>`
- App installers: `apps/<category>/<name>.sh`
- Lowercase with hyphens

---

## Flags

System-wide flag store at `/usr/local/share/linux_post_install/flags/` (presence = set, content = optional value). Sourced via `lib/flags.sh` (or the installed `/usr/local/bin/flags.sh`):

```bash
source "$(dirname "$0")/lib/flags.sh" 2>/dev/null || source "$(dirname "$0")/flags.sh"

flag_set myapp            # green flag
flag_set app "2.1"        # green flag with a value
flag_is_set myapp         # test (0/1) — the primitive consumers use
flag_value app            # → "2.1"
flag_list                 # names of all set flags
flag_clear myapp
```

Writes use `run` + `sudo`, so they respect `--dry-run`. CLI equivalents: `flag-reader`, `flag-set`, `flag-clear`. The main consumer today is `installed_version` — `install.sh` records the repo version there so a later run can compare it against the installed one.

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

# Test install in Docker
docker run --rm -it -v $PWD:/repo ubuntu:22.04 bash
# inside: cd /repo && ./install.sh

# Test app installers
./apps/install.sh
./apps/install.sh --all
./apps/install.sh docker vscode
```
