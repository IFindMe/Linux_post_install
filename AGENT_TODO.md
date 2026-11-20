# AGENT_TODO — Worklist & Idea Backlog

Living list of what we are doing, what is next, and what we might do later.
Deep history lives in git: `git log --follow AGENT_TODO.md`, `git blame`, and
the individual feature commits — the **Done** section below is just a readable
summary (newest first).

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
  mounted disks, USB devices) exported as plain text or JSON.
- **Tier 4: `pos self update`** — git-pull + reinstall with version gate and
  `--dry-run` support.
- **Tier 4: `pos new`** — scaffold a new tool from `templates/pos-tool.sh`,
  prompt for category/command/description, then run the manual checks.
- **NOT NOW: per-category `bin/<category>/` subdirs** — dispatcher is deliberately
  flat (`pos-<cat>-<cmd>`), and nesting buys nothing for the current tool count.

## Done

- **2026-11-19** — Recreated `AGENTS.md` and `AGENT_TODO.md` for the README-only, AI-free repo.
- **2026-11-19** — Reduced documentation to `README.md` only; removed `DOC/`, the old agent docs and the opencode skill markdown.
- **2026-11-19** — Removed the AI command category, adapters, optional apps and all references; `pos` now exposes docker, network, system and tree only.
