# AGENT_TODO — Worklist & Idea Backlog

Living list of what we are doing, what is next, and what we might do later.
Deep history lives in git: `git log --follow AGENT_TODO.md`, `git blame`, and
the individual feature commits — the **Done** section below is just a readable
summary (newest last).

## Conventions

- **Now** — items actively being worked on this session (only a few).
- **Next** — queued, well-scoped items.
- **Later** — idea backlog. Ideas marked **NOT NOW** were evaluated and rejected
  for the stated reason; revisit only if circumstances change.
- When a task is completed: move it from Now/Next into **Done** (dated one-line)
  in the same commit that finishes the work.

## Now

## Next

## Later

- **Tier 2: `pos health` extras** — temperature/fan/load average thresholds,
  `ss -tln` port checks for known services, SMART status for disks.
- **Tier 3: backup rotation + remote target** — keep-N rotations, upload to a
  remote target after verify, `--remote` flag, digest reports rotation age.
- **Tier 3: `pos secret` vault** — gpg/age-encrypted key-value store; backend
  for future tools that need stored tokens.
- **Tier 3: `pos inventory`** — machine manifest (OS, packages, services,
  mounted disks, USB devices) exportable as markdown/JSON.
- **Tier 4: `pos self update`** — pull repo and re-run install.sh to refresh
  `/usr/local/bin` (verify manually with `bash -n`, `pos tree`, `--help`,
  `git diff --check`).
- **Tier 4: `pos new`** — scaffold a new tool from `templates/pos-tool.sh`
  (category, name, POS header, exec bit, doc stubs).
- **NOT NOW:** per-category `bin/` subdirectories — flat `bin/` + filename
  dispatch scales fine; revisit only if `bin/` passes ~40 files.

## Done

- **2026-11-19** — Removed the provider-chat/HF command category, adapters, optional apps, and all related docs; `pos` now exposes docker, network, system and tree only.

- **`pos system bank alias`** — bash aliases for bank commands (Architect→Builder): `alias <name> [alias_name]`, `alias list`, `alias remove…
- **`pos bank` command bank** — feature (41efc91) + lib registration fix (73d15a2) + main-menu visibility & `run` crash fix (c5d501a) +…
- **2026-09-09** — New `pos system alias` tool (Architect→Builder→Reviewer→Writer): persistent command aliases via wrapper scripts in…
- **2026-09-08** — `install.sh` version gate (Architect→Builder): skip+abort when installed version == current version, `--force` to…
- **2026-09-07** — opencode project skill: created `.opencode/skills/linux-post-install/SKILL.md` (repo had no `.opencode/`).
- **2026-09-06** — Repo cleanup: removed 114 temp/process files (AgentsReport/ 86 + reportAgents/ 28 agent reports), stale…
- **2026-09-06** — Stabilization pass: 17-point code-level audit executed via Explorer(3) → Architect(decisions D-A..D-F) →…
- **2026-09-06** — Convention sweep.
- **2026-08-21** — Refreshed `AGENTS.md` against the codebase: HOWTO category list corrected to match `DOC/howto/*`…
- **2026-08-15** — `pos docker stack` (`bin/pos-docker-stack`).
- **2026-08-14** — `pos system backup`.
- **2026-08-05** — `pos <category> --help` auto-discovery in the dispatcher.
- **2026-08-05** — AGENTS.md with lazy-loaded DOC references.
- **2026-08-06** — Nested `pos` subcommands.
- **2026-08-06** — `pos` HOW-TO guide set.
- **2026-08-06** — Tier 1.
- **2026-08-09** — `pos tree`: prints the live `pos` command tree (categories → commands → subcommands) by deriving the hierarchy…
- **2026-08-09** — Structure/convention audit fix: `--dry-run` now truly dry (`spawn()` honors `DRY_RUN`, install.sh exports it to…
- **2026-08-11** — Docs: DEV.md / AGENTS.md / AGENT_Context conventions pass.
- **2026-08-11** — `pos network checkport` nmap overhaul: two-pass engine.
- **2026-08-12** — `pos network download` (`bin/pos-network-download`).
- **2026-08-12** — `pos network download` grows outage resilience: `restart <gid>` (re-queue from history.
- **2026-08-12** — `pos network download replace <gid> <url>` + fresh-link status advisory.
- **2026-08-12** — `pos system event-trigger` (eventer) generalized into `pos system schedule`.
- **2026-08-13** — Fast pos-unit shutdown: every systemd unit a pos tool writes (or `systemd/` ships) now sets `TimeoutStopSec=5s` (+…
- **2026-08-13** — Bootstrap output transparency (`install.sh` / `preinstall.sh` / `postinstall.sh`): removed the redundant `apt…
- **2026-08-13** — `usb-automount` feature, integrated exactly like `autostart`: `features/usb-automount.sh` (root-guard re-exec via sudo.
- **2026-08-13** — `pos system backup` copies the finished backup to a USB stick.
- **2026-08-13** — Docs hardening from the schedule-session review (sole-developer call: terse, session-learned).
- **2026-08-14** — Convention-drift maintenance fix session (completed the audit backlog `MAINTENANCE.md`, M-001..M-023, all VERIFIED.
- **2026-08-14** — `pos system backup` optional encryption (`--no-encrypt` flag + `BACKUP_ENCRYPT=0` env, flag-or-env.
- **2026-08-23** — Menu Phase 1 (user-ratified decision "b"): category-neutral menu library added (Pattern B) +…
- **2026-08-23** — Menu Phase 2 + firewall style-migration (decision "a" activated: P1 landed, `lib/menu-lib.sh` exists).
