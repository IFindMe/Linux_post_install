---
name: linux-post-install
description: Use when working on the Linux_post_install repo — creating, modifying, or fixing pos CLI tools (bin/pos-*, install.sh, apps/, lib/, completions/). Front-loads the # POS: header system, the pos tool model, and the doc-authority order (templates > DEV.md > AGENTS.md > code).
---

# Linux_post_install — Toolkit Operations

Operational playbook for changing the Linux_post_install repo (Debian/Ubuntu bootstrap + homelab toolkit, Bash). Read `DOC/AGENT_Context_Project.md` first for any non-trivial task. For usage docs see `DOC/HOWTO.md`; for the CLI reference see `DOC/POS.md`.

## Repo shape

- `bin/pos-<cat>-<cmd>` — tools; categories: docker, network, system. The only category-less tool is `pos-tree`.
- `lib/` — `common.sh` (run/spawn/err/warn, `load_env_file`), `registry.sh` (POS_* header query API), `menu-lib.sh`, `usb-lib.sh`, `bank-lib.sh`, `flags.sh`.
- `apps/`, `templates/` (pos-tool.sh, app.sh — starting points for new files), `completions/pos.bash`, `x64_bin/` (prebuilt hotspot binaries), `install.sh` / `preinstall.sh` / `postinstall.sh`.
- There is no Makefile, scripts/ directory, lint, generator, test suite, or CI workflow. Verification is manual.

## Tool model

- Format: shebang → `set -euo pipefail` → `# POS: <cat> <cmd> — <desc>` header → `# POS_FLAGS:` / `# POS_SUBCMDS:` / `# POS_DEPS:` / `# POS_EXAMPLES:` headers → `command -v` deps guards **before** `-h|--help` dispatch → case-based help.
- File must be executable (`100755`) and run standalone from `/usr/local/bin` after install (source `lib/common.sh` via `$(dirname "$0")/../lib/common.sh` fallback chain).
- New tools are auto-discovered by the dispatcher; `pos tree` uses the text after the first `— ` in the header.
- Stdin readers must be added to `INTERACTIVE_CMDS` in `bin/pos` or the logging `tee` pipe hangs/swallows prompts.
- Deps: apt → `PACKAGES` array in `preinstall.sh`; non-apt/manual installers → `command -v <bin> || err` guard inside the tool. No config UI — tools read plain env vars; `load_env_file` from common.sh optionally reads a hand-written `~/.config/linux_post_install/<name>.env` (chmod 600, never commit).

## Doc authority

1. `templates/*.sh` — codified current convention; required starting point for new files.
2. `DOC/DEV.md` — convention detail, checklists (wins on detail).
3. `AGENTS.md` — operational/process facts (wins on process).
4. Code + `# POS:` headers — ground truth for behavior.

Drift in POS/HOWTO/README/SCRIPTS/APPS docs is a doc bug — fix the doc.

## Verification

After structural changes, run manually:

```bash
bash -n <file>
bin/pos tree
bin/pos --help
bin/pos help <full command>
git diff --check
```

## Commands relevant to this repo

- `bin/pos tree` — authoritative structure (derived live from `bin/pos-*`).
- `bash install.sh --dry-run` — preview the 3-phase install.
- `bin/pos-system-uninstall --help` — removal tiers for the installed toolkit.
