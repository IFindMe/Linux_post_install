# Linux_post_install — Personal Bootstrap & Homelab Toolkit

## Introduction

One command turns a bare Debian/Ubuntu install into a productive machine. This is a personal bootstrap and homelab toolkit made of three pieces:

- **Bootstrap scripts** — install the base packages and configure the user environment.
- **`pos` CLI** — a unified command line for network checks, Docker dashboards/VMs, system backups/health, and a command bank. Run `pos tree` for the live list of what is available.
- **Optional app installers** — 16 desktop/utility apps (VS Code, Brave, OBS, Tailscale, Docker, QEMU, …) installed through a picker.

Everything is plain Bash. Tools are auto-discovered from filenames, so the CLI grows by dropping in a new script. After installation, all tools live in `/usr/local/bin/` and the repo can be deleted.

Supported: Debian / Ubuntu (`apt`). Target shell: Bash.

## Installation

Run from the repo root:

```bash
git clone https://gitea.skink-platy.ts.net/admin/Linux_post_install.git
cd Linux_post_install
./install.sh
```

`install.sh` is the only entry point. It coordinates three core phases, then optionally the app picker. Each phase can be skipped or run on its own.

**Flags**

| Flag | What it does |
|------|-------------|
| `--apps` | Run the interactive app picker after the core install |
| `--full` | Core install + all 16 apps, non-interactive |
| `--dry-run` | Show what would be done without executing it (`install.sh` itself; subprocesses do not inherit the flag) |
| `--force` | Re-install even when the recorded installed version already matches |
| `--skip <phase>` | Skip a phase; repeatable. Names: `preinstall`, `scripts`, `postinstall`, `apps` |
| `--steps <spec>` | Run only selected phases, e.g. `--steps 1,3` or `--steps 1-3` (`1=preinstall`, `2=scripts`, `3=postinstall`) |
| `--no-color` | Disable colored output |
| `-h`, `--help` | Show usage |

A version gate compares the installed version flag against the current repo version (`0.0c<commit count>`); on a match it stops unless `--force` is given. Without git or without a stored version, the gate is skipped.

Installer output uses the pure-Bash helpers in `lib/ui.sh` (no Gum or other UI dependency): a compact banner, `[n/3]` section counters with progress bars, timed `✓ / ! / ✗` status lines, and a spinner only on interactive terminals. Package lists are summarized as counts instead of being printed in full; apt output is captured and shown on failure. Set `UI_DEBUG=1` to stream full command output, `UI_NO_COLOR=1` or `--no-color` to disable color, and `UI_SPINNER=0` to disable animation. On non-TTY output the UI falls back to plain, log-friendly lines.

**Phase 1 — preinstall (`preinstall.sh`, needs root)**

`apt update`, then installs the package list in `preinstall.sh` (network tools, `nmap`, `fail2ban`, hotspot dependencies, crypto/archive tools, Python, GTK/Qr libraries for the hotspot GUI). It also tries `cpufrequtils`/`linux-cpupower` opportunistically and verifies a few binaries. Can be run standalone with `--dry-run`.

**Phase 2 — scripts (needs root)**

- Copies every file in `bin/` to `/usr/local/bin/` with mode `755` (the `pos` dispatcher, all `pos-*` tools, and the flag CLIs).
- Copies six shared libraries — `common.sh`, `flags.sh`, `usb-lib.sh`, `menu-lib.sh`, `registry.sh`, `bank-lib.sh` — to `/usr/local/bin/` with mode `644`.
- Copies the architecture-matched prebuilt binaries from `x64_bin/` (or a future `arm64_bin/`) into `/usr/local/bin/` (`create_ap`, `wihotspot`, `wihotspot-gui`).

**Phase 3 — postinstall (runs as your user)**

- Appends the `PATH` line to `~/.bashrc` (includes `/usr/local/bin` and `~/.local/bin`).
- Installs Bash completion for `pos` under `/usr/local/share/bash-completion/completions/` and sources it from `~/.bashrc`.
- If `config/authorized_keys` exists, appends missing keys to `~/.ssh/authorized_keys` (chmod 600).

**Optional apps phase**

Triggered by `--apps` (interactive y/n picker grouped by category) or `--full` (install everything). You can also run `bash apps/install.sh [app ...]` directly; `--uninstall` reverses the selection.

After install, `pos` works from any directory and the repo is no longer required. To remove the toolkit later, run `pos system uninstall` (tiers 1/2/3 for binaries, config, and log data).

## Convenience systems — how to expand pos

**The dispatcher (`bin/pos`)**

`pos` scans its own directory for executable `pos-*` files. A call like `pos system bank alias remove work` is matched against the longest prefix that exists — `pos-system-bank-alias` — and the remaining words are passed as arguments. Categories and command lists are derived from filenames, so there is no central registry to update. `pos tree` prints the authoritative live tree, `pos <category> --help` lists a category, and `pos help <full command>` shows a tool's `--help`.

Tool metadata lives in comments next to the shebang:

```bash
# POS: <category> <command> — one-line description
# POS_FLAGS: --flag1 --flag2          # optional
# POS_SUBCMDS: sub1 sub2              # optional
# POS_DEPS: binary1 binary2           # optional
# POS_EXAMPLES: pos <tool> <args> | Description
```

`# POS_*` headers feed `pos tree`, category help and completion. A nested file such as `pos-system-bank-alias` appears under its parent tool instead of as a flat sibling.

**Add a CLI tool**

1. `cp templates/pos-tool.sh bin/pos-<category>-<command>` and `chmod +x` it.
2. Add the `# POS:` header above; add flags/subcommands if the tool has them.
3. If it reads stdin (prompts, menus), add its dash-name to `INTERACTIVE_CMDS` in `bin/pos` — otherwise the logging `tee` pipe swallows the prompt.
4. Dependencies: apt packages go into `PACKAGES` in `preinstall.sh`; manually installed binaries get a `command -v <bin> || err "…"` guard inside the tool.
5. Verify with `bash -n <file>`, `bin/pos tree`, `bin/pos --help`, `bin/pos help <full command>`, and `git diff --check`.

Tools must work after the repo is deleted: source libraries via the `$(dirname "$0")/../lib/common.sh` fallback chain and use canonical `pos <category> <command>` spellings.

**Add an optional app**

`cp templates/app.sh apps/<category>/<name>.sh`. Each installer defines `install_<name>()` and `uninstall_<name>()` and dispatches on `${1:-}`. `apps/install.sh` discovers app scripts from the directory structure — no registration. Keep install/uninstall idempotent and use the `run`/`spawn` helpers so `$DRY_RUN` is respected.

**Shared helpers and configuration**

`lib/common.sh` provides `log`/`warn`/`err`, `run` (dry-run aware), `spawn` (spinner/timer), `confirm`, and `load_env_file`. Tools read plain environment variables; a hand-written `~/.config/linux_post_install/<name>.env` (chmod 600, never committed) is an optional fallback and an already-exported variable always wins. Secrets are never committed. Non-interactive `pos` invocations log stdout/stderr to `~/.local/share/linux_post_install/logs/`; stdin-reading commands only log the invocation.

**Verification checklist for structural changes**

```bash
bash -n <file>          # syntax
bin/pos tree            # every command the dispatcher can reach
bin/pos --help
bin/pos help <full command>
git diff --check
```

There is no build system, test suite, linter or CI workflow — verification is manual.
