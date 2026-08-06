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

- (none — Tier 1 shipped: `pos system health`, `lib/notify.sh`, digest timer)

## Next

- Wire alerting into more tools as they are added (default: source
  `lib/notify.sh`, call `notify_send` on success/failure).

## Later — idea backlog

- **Tier 2: watch plugins** — `pos system watch <event>`: poll conditions and
  alert on change (public IP changed, disk > 90%, backup skipped, fail2ban
  spike). Reuses `notify_send` + a systemd timer per watch.
- **Tier 2: `pos health` extras** — temperature/fan/load average thresholds,
  `ss -tln` port checks for known services, SMART status for disks.
- **Tier 3: backup rotation + remote target** — keep-N rotations, upload to
  rclone remote after verify, `--remote` flag, digest reports rotation age.
- **Tier 3: `pos secret` vault** — gpg/age-encrypted key-value store; backend
  for future tools that need stored tokens.
- **Tier 3: `pos inventory`** — machine manifest (OS, packages, services,
  mounted disks, USB devices) exportable as markdown/JSON.
- **Tier 4: `pos self update`** — pull repo, `make gen && make check`,
  re-run install.sh to refresh `/usr/local/bin`.
- **Tier 4: `pos new`** — scaffold a new tool from `templates/pos-tool.sh`
  (category, name, POS header, exec bit, doc stubs).
- **NOT NOW:** Telegram inbound bot (command handling) — outbound alerting
  covers current needs; revisit if remote control is wanted.
- **NOT NOW:** per-category `bin/` subdirectories — flat `bin/` + filename
  dispatch scales fine; revisit only if `bin/` passes ~40 files.
- **NOT NOW:** split `lib/entertainment-lib.sh` — fine under 600 lines; revisit
  if it grows.

## Done (summary, newest last)

- 2026-08-06: Tier 1 — `pos system health` (dashboard + `--send`), `lib/notify.sh`
  (wired into backup + firewall), daily digest timer via postinstall.
- 2026-08-06: Document Map index + Entertainment section in AGENT_Context (cf36780).
- 2026-08-06: Entertainment module — plugins (weather/joke/gold), `pos
  entertainment config/enable/disable/send/status`, auto-trigger + Telegram send.
- 2026-08-05: `pos communication telegram` — `--parse-mode` (plain/markdown/html).
- 2026-08-05: doc/code sync gate — `make gen` + `make check` + pre-commit hook.
- 2026-08-05: `pos usb server` — USB Redirector control tool (494eae2).
- 2026-08-05: `pos <category> --help` auto-discovery in the dispatcher.
- 2026-08-05: AGENTS.md with lazy-loaded DOC references.
