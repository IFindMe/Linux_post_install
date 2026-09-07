---
name: linux-post-install
description: Use when working on the Linux_post_install repo — creating, modifying, or fixing pos CLI tools (bin/pos-*, install.sh, features/, apps/, lib/, systemd/, completions/), regenerating docs via make gen, or running the make check / make lint / make test gates. Front-loads the # POS: header system, the pos tool model, the doc-authority order (templates > DEV.md > AGENTS.md > code), the definition of done, and the test conventions.
---

# Linux_post_install — Toolkit Operations

Operational playbook for changing the Linux_post_install repo (Debian/Ubuntu bootstrap + homelab toolkit, Bash). Read `DOC/AGENT_Context_Project.md` first for any non-trivial task — it opens with a **Document Map** (auto-generated line ranges) to jump straight to the relevant section. For day-to-day *usage* docs see `DOC/HOWTO.md`; for the `pos` CLI reference see `DOC/POS.md`.

## Repo shape

- `bin/pos-<cat>-<cmd>` — tools (45 of them); category-less `bin/pos-<cmd>` for dispatcher/dev-level (`pos-config`, `pos-tree`). Legacy `bin/wr-*`, `mp3`, `mp4`, `vbox`, `ssh-load-all` are thin forwarders — keep them that way.
- `lib/` — shared libraries: `common.sh` (run/spawn/err/warn, `ensure_user_bus`), `registry.sh` (POS_* header query API — consumers source it, never re-implement sed/grep), `menu-lib.sh` (`menu_ask_value`, `--allow-empty`), `jq-seam.sh` (stub-friendly jq), `config.sh` (env files, `pos config` scopes), `share-lib.sh`, `usb-lib.sh`, `ai-lib.sh` (use the `llamafile` seam in tests).
- `features/`, `apps/`, `templates/` (pos-tool.sh, app.sh, feature.sh — starting points for new files), `systemd/`, `completions/pos.bash` (gen output), `tests/` (suite, see below), `x64_bin/`+`arm64_bin/` (prebuilt hotspot binaries), `scripts/` (gen-docs, check-sync, lint-conventions, ci-status), `Makefile` (check/gen/lint/test/hook), `.gitea/workflows/lint.yml` (CI).
- Gen blocks `GEN:START`/`GEN:END` (AGENT_Context filetable/tree/dispatch/selfcontained/docmap + `completions/pos.bash`) are `make gen` output — never hand-edit.

## Tool model

- Format: shebang → `set -euo pipefail` → `# POS: <cat> <cmd> — <desc>` header (missing header hard-fails `make gen`) → `# POS_FLAGS:` / `# POS_SUBCMDS:` / `# POS_CONFIG:` / `# POS_DEPS:` / `# POS_EXAMPLES:` headers → `command -v` deps guards **before** `-h|--help` dispatch → case-based help.
- File must be executable (`100755`) and run standalone from `/usr/local/bin` after install (source `lib/common.sh` via `$(dirname "$0")/../lib/common.sh` fallback chain).
- New tools are auto-discovered; `make gen` only uses the text after the first `— ` in the header.
- Stdin readers must be added to `INTERACTIVE_CMDS` in `bin/pos` or the logging `tee` pipe hangs/swallows prompts.
- Deps: apt → `PACKAGES` array in `preinstall.sh`; non-apt/manual installers → `command -v <bin> || err` guard inside the tool. Secrets never committed; runtime config `~/.config/linux_post_install/<tool>.env` (chmod 600), env-var precedence.
- Entertainment plugins (`entertainment/`) must NOT source `lib/common.sh` (stdout is the Telegram message); markers `# POS_PLUGIN:` + `# POS_KEYS:`.
- ScaleTail compose is a git submodule — `git submodule update --init` before `pos docker compose *`.
- Generators must be byte-order deterministic (`LC_ALL=C`, sort) or CI `git diff --exit-code` trips.

## Doc authority (MAINTENANCE.md Phase 0)

1. `templates/*.sh` — codified current convention; required starting point for new files (`cp templates/pos-tool.sh bin/pos-<cat>-<cmd>`).
2. `DOC/DEV.md` — convention detail, checklists (wins on detail).
3. `AGENTS.md` — operational/process facts (wins on process).
4. Code + `# POS:` headers — ground truth for behavior and GEN blocks.

Drift in POS/HOWTO/README/SCRIPTS/SYSTEMD/APPS docs is a doc bug — fix the doc.

## Definition of done

After touching `bin/pos-*` (or anything structural):

```bash
make gen        # regenerates gen blocks + completions
make gen        # run twice — must be byte-idempotent
make check      # self-consistency: bash -n + exec bits + doc-sync + dispatch smoke
make lint       # convention gate — must end "0 FAIL, 0 WARN"
make test       # full suite (18 files / 416 checks) unless tests/README.md says otherwise
```

Also: `bash -n <file>` for new/edited scripts, `git diff --check`, CI gate (`.gitea/workflows/lint.yml`, job `gates`) runs the same four commands on push to main and tags `ci-ok/<sha>`; query with `scripts/ci-status.sh [--wait] [<sha>]`.

## Test conventions (`tests/`)

- Suite lives in `tests/`; run standalone after suite load: `test_run <name> <label> <stdin> <expected_rc>` with `expect_eq`/`expect_ok`/`expect_fail` helpers; each file prints `^ <name>: <n> checks, <m> fail, <k> skip`.
- Read `tests/README.md` — it documents the harness and suite table; add a row when adding a file.
- Hard-skip contract: tests must never fake passes. Infeasible non-TTY cases are documented `skip`; use `# POS:` header checks, `extract_fn` brace extraction, stub-PATH seams, and non-TTY stdin pipes where possible. Zero-skip is preferred but never silence real failures. Negative controls (assert the new check actually catches the old bug) are required for regression tests.

## Commands relevant to this repo

- `make gen` + `make check` + `make lint` (+ `make test`) — the gates above.
- `make hook` — opt-in pre-commit gate.
- `scripts/ci-status.sh [--wait] [<sha>]` — CI tag lookup (0 green / 1 red / 2 pending); reliable path is the Gitea API `https://gitea.skink-platy.ts.net/api/v1/repos/admin/Linux_post_install/commits/<sha>/status`.
- `pos tree` — authoritative structure (needs a built/installed tree; falls back to reading `bin/pos-*` directly).
- `pos config <scope>` — runtime env-file config (`~/.config/linux_post_install/<tool>.env`); mask tokens in output.