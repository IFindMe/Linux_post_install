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

## Done

- **2026-08-09** — Telegram sender `config` / `config set` removed — redundant with `pos config telegram` (same `# POS_CONFIG:` registry, masked token display + input, chat-id validation, chmod 600); sender/listener error hints now point there. Deep-review bugfixes in the same commit: mapped `/command` values containing `|` are no longer truncated (`load_map` switched from a `|` to a `\x1f` delimiter — previously `/up=echo hi | head` silently ran `echo hi `); `pos entertainment send <plugin> [args…]` actually forwards the extra args (every arg was `shift`ed in the flag loop, so `$@` was empty) and passes `--` before the message so leading-`-` plugin output isn't parsed as an option; `write_config_key` (entertainment-lib) and `cfg_write` (config-ui) replaced unescaped `sed -i "s|^K=.*|K=\"$v\"|"` with grep-v+append so values with `&`/`|`/`\` no longer mangle (also the path all telegram config now flows through); `sync_systemd` daemon-reloads after removing timer units; `digits` config validation accepts negative group/supergroup chat ids (`-100…`).

- **2026-08-09** — Fixed telegram listener editor crash on remove/edit/test: `ui_pick` printed its menu listing to **stdout**, so `idx="$(ui_pick)"` captured the menu *and* the number, and `MAP_CMDS[$idx]` (arithmetic array subscript) blew up with "syntax error in expression". Menu decoration now goes to stderr; only the picked index is emitted on stdout. Pre-existing bug (before the `::desc` work), exposed by the description column.

- **2026-08-09** — Telegram listener pushes its mapped `/commands` to the bot's `/` menu via `setMyCommands` (auto after every map edit, on `--enable`, and at daemon start; manual `--sync-commands` flag). Map lines may carry a menu description: `/cmd::short description=bash command` (falls back to the bash command, ~40 chars). Names are validated against Telegram's lowercase `[a-z0-9_]` rule — invalid ones are skipped from the menu with a warning but still resolve when typed; empty map clears the menu. Fixed latent bugs found by the sync work: `map_has` (awk `END{exit 1}` overrode the match), and `warn()` went to stdout so it leaked into the generated JSON (now stderr).

- **2026-08-09** — `pos config <TAB>` scope completion is now cached at gen time (`_pos_config_scopes` array emitted by `make gen` from the `# POS_CONFIG:` registry) instead of scanning ~40 tools per TAB — a per-keypress subshell storm that wedged interactive shells for minutes on the loaded homelab box. Two stuck `-bash` sessions (69%/38% CPU) killed. `plugin_marker`/`plugin_keys` hardened with `|| true` so `config_keys` no longer aborts mid-scan under `set -euo pipefail` on mixed lib/plugin dirs (installed layout) — fixes missing plugin keys in `pos config entertainment`.

- **2026-08-09** — `pos config <scope>` interactive config editor: reads the `# POS_CONFIG:` registry across tools into a single runtime config (`~/.config/linux_post_install/*.env`, one file per scope, chmod 600); secret masking with show/hide toggle, `digits:`/`num:`/`url:` validation, `-` to clear, blank keeps; `*plugins` marker expands plugin vars (entertainment) from `entertainment-lib.sh`; `desc::example` value-format hints shown in the editor; gen-docs now handles category-less tools (`pos-config`), fixed a `set -e`+`pipefail` bug that truncated the header registry.

- **2026-08-09** — `pos-communication-telegram` → `pos-communication-telegram-sender`: one canonical `send` (dropped the legacy `--send` flag, which duplicated the `send` subcommand in completion). `pos communication telegram <TAB>` now completes to just `sender listener`. `lib/notify.sh` maps platform `telegram` → `telegram-sender` via `notify_sender_name()`; entertainment-send + health `--send` check updated. Removed phantom subcommands from howto/communication.md (webhook/logs/broadcast/file never existed).

- **2026-08-09** — Structure/convention audit fix: `--dry-run` now truly dry (`spawn()` honors `DRY_RUN`, install.sh exports it to child phases, postinstall mutations run-wrapped); `gen-docs.sh` no longer chmods regenerated files to 0600; `make check` now syntax-checks apps/entertainment/features/templates; `.gitignore` protects `config/authorized_keys` + `config/rclone.conf`; honest `--send` confirmation; docs refreshed (notify.sh in lib lists, pos-health systemd units, tsui, scripts/, INTERACTIVE_CMDS).

- **2026-08-07** — `pos system health --send` notification-only; listener `@quiet` prefix (run mapped command without replying, for commands that self-notify). `/status=@quiet pos system health --send` = exactly one digest.

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
- **NOT NOW:** per-category `bin/` subdirectories — flat `bin/` + filename
  dispatch scales fine; revisit only if `bin/` passes ~40 files.
- **NOT NOW:** split `lib/entertainment-lib.sh` — fine under 600 lines; revisit
  if it grows.

## Done (summary, newest last)

- 2026-08-06: Fix entertainment timer `1h` not firing — `interval_to_oncalendar`
  emitted invalid `OnCalendar=*-*-* */N:00:00` (systemd rejects `*/N` in the hour
  field); now `*-*-* 00/N:00:00`. Dropped the cron fallback entirely: scheduling
  is systemd user timers only (`sync_cron`/`interval_to_cron`/`cron_block`
  removed), `status` simplified, `Nd` intervals rejected with a clear error.
- 2026-08-06: Nested `pos` subcommands — `# POS_SUBCMDS:` header annotation (telegram,
  docker-compose, docker-vbox) + `make gen` emits a `_pos_subcmds` completion map;
  nested tools (`telegram listener`) auto-list under their parent instead of as a
  flat sibling (`telegram-listener`) in `pos <category>` and tab-completion; generic
  tool-level completion (subcommands + flags + `--help`).
- 2026-08-06: Telegram **listener** — `pos communication telegram listener`:
  interactive `/command` → bash map editor + owner-only polling daemon as a
  systemd user service (map in `~/.config/linux_post_install/telegram_commands.env`,
  re-read per message; `/help`, unknown-command reply, 60s timeout, stdout reply).
- 2026-08-06: NFS in `pos system` — `pos system nfs-server` (status/share/
  unshare/list/reload/enable/disable, idempotent /etc/exports edits, generic
  default with Tailscale/WireGuard/LAN examples) + `pos system nfs-client`
  (mount/unmount/list + persistent mounts as systemd `.mount` units ordered
  after network-online.target, no fstab); `nfs-kernel-server` + `nfs-common`
  added to preinstall PACKAGES.
- 2026-08-06: `pos` HOW-TO guide set — `DOC/HOWTO.md` index + per-category
  `DOC/howto/*.md` (network, docker, media, system, ssh, usb, communication,
  entertainment) with flags, recipes, config, and troubleshooting; wired into
  DOC/README, root README, AGENTS.md.
- 2026-08-06: Multi-platform alerting — `lib/notify.sh` routes via `NOTIFY_PLATFORM`
  (`notify.env`, default telegram; sender contract for Matrix/Synapse later),
  `system.env` shared config for health/backup, dynamic effective values in
  `--help`, telegram `--markdown` alias.
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
