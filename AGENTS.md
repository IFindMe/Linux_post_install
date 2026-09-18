# Linux_post_install — Agent Instructions

Personal bootstrap & homelab toolkit for Debian/Ubuntu (Bash). `install.sh` bootstraps a machine; `bin/pos` dispatches `bin/pos-<cat>-<cmd>` by longest-prefix match. `pos tree` is the authoritative command list — never trust a stale category list in docs.

## Read first (lazy-load only what the task needs)

- `DOC/AGENT_Context_Project.md` — overview, dispatch, structure (Document Map at top for jumping).
- `DOC/DEV.md` — adding Tool/App/Plugin checklists + test-seam patterns. Wins on detail.
- `DOC/POS.md` — hand-written CLI reference; update its table + detail block when behavior changes.
- New files start from templates: `cp templates/pos-tool.sh bin/pos-<cat>-<cmd>` (likewise `app.sh` → `apps/`, `feature.sh` → `features/`). Never hand-roll. Category-less `bin/pos-<cmd>` is only for dispatcher/dev-level commands (`pos-config`, `pos-tree`).

## Definition of done

After touching `bin/pos-*` (or anything structural):

```bash
make gen && make gen                  # 2nd run must be byte-identical (generators sort with LC_ALL=C)
make check                            # bash -n + exec bits + gen-drift + dispatch smoke
make lint                             # must end 0 FAIL, 0 WARN
make test                             # full zero-dep suite: no network, no sudo, no system changes
./tests/run-tests.sh t-<name>.sh      # single test file
bash -n <file> && git diff --check    # new/edited scripts
```

CI (`.gitea/workflows/lint.yml`, job `gates`) runs `make gen` + `git diff --exit-code` + `make check` + `make lint` on push to main and PRs, then tags `ci-ok/<sha>` or `ci-fail/<sha>`; check with `scripts/ci-status.sh [<sha>]`. Red is a merge-blocker. `make hook` installs the opt-in pre-commit hook (runs `make check` only — always run `make lint` yourself).

## Tool rules (lint-enforced — agents guess these wrong)

- Executable `100755` + `#!/usr/bin/env bash` + `set -euo pipefail` + `# POS: <cat> <cmd> — <desc>` right after the shebang (missing header hard-fails `make gen`). `POS_FLAGS`/`POS_SUBCMDS` only for that style; `POS_DEPS`/`POS_EXAMPLES`/`POS_CONFIG` optional. Only the text after `— ` is rendered; the words before it are convention-only. Query headers via `lib/registry.sh`, never re-parse with sed/grep.
- `command -v <bin> || err "…"` deps guards sit **before** the `-h|--help` case — help must also fail without the dep (graceful `if command -v` probes are exempt). Apt packages → `PACKAGES` in `preinstall.sh`; manual installers → guard inside the tool, never in `PACKAGES`.
- Stdin readers → add to `INTERACTIVE_CMDS` in `bin/pos`, or the logging `tee` pipe hangs/swallows prompts (per-script granularity: the whole script then skips logging).
- System-path writes need a test seam: `VAR="${VAR:-/real/path}"`, never a bare `/etc/…`/`$HOME/…` write (prove with `VAR=/tmp/x …` + real path untouched). Use `run`/`spawn` helpers (respect `$DRY_RUN`); keep writes idempotent.
- Tools must run standalone from `/usr/local/bin`: source libs via the `$(dirname "$0")/../lib/common.sh` fallback chain. Legacy `wr-*`, `mp3`, `mp4`, `vbox`, `ssh-load-all` are thin forwarders to `pos` — keep them thin.

## Module quirks

- `entertainment/<name>.sh` plugins: `# POS_PLUGIN:` + `# POS_KEYS:` markers, never source `lib/common.sh` (stdout becomes the Telegram message). Verify with `bash -n` + `pos entertainment send <name> --print`; `make gen` skips them.
- Secrets are never committed (`config/authorized_keys`, `config/rclone.conf` are gitignored). Runtime config is `~/.config/linux_post_install/<tool>.env` (chmod 600, env-var precedence); mask tokens in output.
- `compose/scale-tail` is a git submodule — `git submodule update --init` before any `pos docker compose` work.
- Tests live in `tests/t-*.sh` (`run_test()` + `test-lib.sh` helpers; `$TEST_TMP` sandbox auto-cleaned). Infeasible cases call `skip_case` — never fake a pass. Add a row to `tests/README.md` for new files; keep the suite under 90s.

## Docs & process

- Never hand-edit between `GEN:START`/`GEN:END` markers (`DOC/AGENT_Context_Project.md`, `completions/pos.bash`) — always `make gen`.
- Authority on conflict: `templates/*.sh` > `DEV.md` (detail) > `AGENTS.md` (process) > code + `# POS:` headers (behavior truth) > hand-written docs (drift = doc bug, fix the doc).
- Commits use `feat:`/`fix:`/`docs:`/`chore:`/`refactor:`, one logical change per commit. Move finished work to **Done** (dated) in `AGENT_TODO.md` in the same commit.
