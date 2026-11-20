# Linux_post_install — Agent Instructions

Personal bootstrap & homelab toolkit for Debian/Ubuntu (Bash). `install.sh` bootstraps a machine; `bin/pos` dispatches `bin/pos-<cat>-<cmd>` by longest-prefix match. `pos tree` is the authoritative command list — never trust a hand-written list.

## Read first

- `README.md` — the only documentation. It covers the overview, detailed installation, and how to expand `pos` (tools, apps, metadata, verification).
- New files start from templates: `cp templates/pos-tool.sh bin/pos-<cat>-<cmd>` (likewise `app.sh` → `apps/<cat>/<name>.sh`). Never hand-roll. A category-less `bin/pos-<cmd>` is only for dispatcher/dev-level commands (currently `pos-tree`).

## Definition of done

After touching `bin/pos-*` (or anything structural), check manually:

```bash
bash -n <file>
bin/pos tree                  # every command the dispatcher can reach
bin/pos --help
bin/pos help <full command>
git diff --check
```

There is no build system, test suite, linter, or CI workflow — do not add references to them. If stale copies are installed under `/usr/local/bin`, the dispatcher resolves those before repo files; for a clean repo check use `./bin/pos-tree` and `<tool> --help` directly.

## Tool rules

- Executable `100755` + `#!/usr/bin/env bash` + `set -euo pipefail` + `# POS: <cat> <cmd> — <desc>` right after the shebang. `POS_FLAGS`/`POS_SUBCMDS` only for that style; `POS_DEPS`/`POS_EXAMPLES` optional. Only the text after `— ` is rendered; the words before it are convention-only. Query headers via `lib/registry.sh`, never re-parse with sed/grep.
- `command -v <bin> || err "…"` deps guards sit **before** the `-h|--help` case — help must also fail without the dep (graceful `if command -v` probes are exempt). Apt packages → `PACKAGES` in `preinstall.sh`; manual installers → guard inside the tool, never in `PACKAGES`.
- Stdin readers → add to `INTERACTIVE_CMDS` in `bin/pos`, or the logging `tee` pipe hangs/swallows prompts (per-script granularity: the whole script then skips logging).
- System-path writes need an env-overridable seam: `VAR="${VAR:-/real/path}"`, never a bare `/etc/…`/`$HOME/…` write. Use `run`/`spawn` helpers (respect `$DRY_RUN`); keep writes idempotent.
- Tools must run standalone from `/usr/local/bin`: source libs via the `$(dirname "$0")/../lib/common.sh` fallback chain. Use canonical `pos <category> <command>` spellings.

## Module quirks

- Secrets are never committed (`config/authorized_keys` is gitignored). Tools read plain environment variables (an already exported value wins). Use `load_env_file` from `lib/common.sh` to read a hand-written `~/.config/linux_post_install/<name>.env` (chmod 600, never commit); mask tokens in output.
- Non-interactive `pos` invocations log stdout/stderr to `~/.local/share/linux_post_install/logs/`; stdin-reading commands only log the invocation.
- Optional app installers live at `apps/<category>/<name>.sh`, define `install_<name>()` and `uninstall_<name>()`, and are auto-discovered by `apps/install.sh` — no registration.
- `lib/registry.sh` is the single query API over `# POS_*` headers, used by `pos tree`, category help and completion.

## Docs & process

- `README.md` is the only doc. Update its Introduction, Installation or Convenience sections when behavior changes. Authority on conflict: `templates/*.sh` > this file (process) > code + `# POS:` headers (behavior truth) > `README.md` (user-facing docs).
- Commits use `feat:`/`fix:`/`docs:`/`chore:`/`refactor:`, one logical change per commit. Record significant completed work in the commit message; deep history lives in git.
