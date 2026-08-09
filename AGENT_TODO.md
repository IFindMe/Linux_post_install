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

- **2026-08-09** — Matrix/Synapse `communication` tools — `pos communication matrix sender` + `listener`, completing the second notify platform `lib/notify.sh` was designed for (`NOTIFY_PLATFORM=telegram,matrix` fan-out; the sender implements the `send <value> [--markdown]` contract via `notify_sender_name()`'s default key→tool mapping, no lib changes). **Sender** (`bin/pos-communication-matrix-sender`): `send <value> [--markdown] [--room <id|alias>]` PUTs `m.room.message` (`m.text`) to the client-server API v3 — room ids/aliases URL-encoded (`#pos:example.org` → `%23pos%3A…`), unique per-message txn id, `--markdown` sends `org.matrix.custom.html` via a best-effort markdown→HTML converter (bold/italic/code/fences/strike/links/headers/lists, escapes HTML, never fails the send); `login --user <@id>` (masked password prompt → `m.login.password` → saves `access_token`+`user_id`); `test`. Config scope `matrix` (`~/.config/linux_post_install/matrix.env`, `MATRIX_HOMESERVER`/`MATRIX_ACCESS_TOKEN`/`MATRIX_USER_ID`/`MATRIX_ROOM_ID`, secret masked) registered via `# POS_CONFIG:` → `pos config matrix` + tab-completion scope. **Listener** (`bin/pos-communication-matrix-listener`): systemd **user** daemon (`pos-matrix-listener.service`) long-polling `/sync` (30s timeout, per-sync `since` token, compact filter dropping presence/account_data/device noise, `m.room.message` only); reacts to `MATRIX_USER_ID`'s own messages (resolved via `/account/whoami` if unset), `MATRIX_ROOM_ID` restricts to one room; `/` and `!` both resolve; replies threaded `m.in_reply_to`; `@quiet` no-reply marker; `/cmd::desc=…` map descriptions; `ai …` bridge (`pos ai gemini ask`, per-room session `matrix-<room>`, `ai /reset` clears, markdown stripped); interactive editor (`--status`/`--enable`/`--disable`/`--run`), 60s command timeout, exit-code prefix, ~3800-char truncation. `communication-matrix-listener` added to `INTERACTIVE_CMDS` (stdin editor + forever-loop daemon). Docs: POS.md rows + "in detail" sections + ai bridge note, howto/communication.md rewritten Matrix sections, HOWTO.md index + config table + platform note, `bin/pos` usage EXAMPLES; `make gen && make check` green. Verified against a mock homeserver: send plain/markdown/`--room`/test request shape (URL-encoding, Bearer auth, JSON body), login token save, listener owner-filter + `/status` reply + `/help` + `@quiet` silence + non-zero exit reply + interactive editor add. — state-based threshold rule monitors (eventer). Each line of `~/.config/linux_post_install/event.env` is an independent rule: `["<msg>" if ] <check-command> <op> <threshold>` (op `> < >= <= == !=`, unit suffix ok `60c`/`80%`). The check command is run on every pass and its **first numeric output** compared float-safe; operator detected as the rightmost `op threshold` pair so checks containing their own `>`/`<` (awk, redirection) parse fine. Alerts once on false→true plus one recovery message on true→false (no repeats while a condition holds); per-rule state in `~/.local/share/linux_post_install/eventer/state/` keyed by rule-line hash (editing a rule resets its state). Subcommands: `run` (timer entrypoint), `config` (interactive add/remove/edit with validation by test-running the check), `list` (rules + live values), `enable [interval]` (systemd **user** timer `pos-event-trigger.timer` + oneshot service; `5m…weekly` or `OnCalendar=…`; graceful warnings when no user systemd manager, `loginctl enable-linger` attempt), `disable`, `status`. `--dry-run` honors the DEV.md dry-run convention. Alerts via `lib/notify.sh` (Telegram default; other platforms via `NOTIFY_PLATFORM`). New: `bin/pos-system-event-trigger`, `lib/eventer-lib.sh`, `config/event.env` template (installed no-clobber by postinstall), `lib/eventer-lib.sh` installed by install.sh, `system-event-trigger` added to `INTERACTIVE_CMDS`, usage EXAMPLES row. Docs: POS.md system row, HOWTO.md index row, howto/event-trigger.md; `make gen && make check` green; functional tests covered trigger/recovery/no-repeat, float + unit parsing, editor add/remove/edit + validation + dry-run, timer enable/disable/status (graceful), dispatcher routing.

- **2026-08-09** — `pos media mp3`/`mp4` hardened + smart format selection. Both tools: yt-dlp calls go through `spawn` (honor `$DRY_RUN`; `--dry-run` prints the exact command and skips dep checks), `-o/--output`, `--no-playlist`, `--cookies` (file existence check), clean ffmpeg/yt-dlp guards, `# POS_FLAGS:` for completion, full metadata (`--embed-metadata --embed-chapters --embed-thumbnail --no-overwrites`, mp3 also `--convert-thumbnails jpg` + `--parse-metadata "%(artist,uploader)s:%(artist)s"` so the uploader fills the artist tag). mp3 gains `--by-artist` (`~/Music/<artist>/<title>.mp3`). mp4 gains `-f <id>` / `--best` / `--worst` (no prompt), conflict validation, and an interactive picker that shows a **curated** `-F` table (`[audio]`/`[video]`/`[combo]` grouping, raw clutter dropped) on stderr — stdout carries only the chosen id (ui_pick lesson) — with id validation against the real table and empty/best default. Docs: howto/media.md rewritten (flags, metadata, by-artist, troubleshooting); `make gen && make check` green.

- **2026-08-09** — Telegram `ai …` now answers about a message you reply to: the listener extracts `reply_to_message.text` (falls back to `caption`) from each update and passes it to `handle_message`; the AI bridge prefixes the prompt with `[Reply context — the message you are replying to]`. So replying to a `/status` output and asking `ai check this details` gives the model the actual output. Applies only to the AI bridge (mapped `/commands` untouched); reply context rides in the user turn so the session records what was analyzed. Docs: howto/ai.md bridge section.

- **2026-08-09** — `pos ai gemini` sessions + Telegram-friendly replies. `--session <name>` gives `ask`/`chat` persistent memory (`~/.local/share/linux_post_install/ai/<name>.json`, capped at 40 turns, pruning keeps the first user turn as scene); new `sessions` subcommand (list / `reset <name>`). Telegram listener now keeps one session per chat (`telegram-<chat_id>`) with `ai /reset` to clear. New `--system "<text>"` flag injects a Gemini `systemInstruction` (via `jq` merge) sent every turn but never stored in the session file; the listener passes a Telegram-voice prompt ("reply like a friendly Telegram chat, use emojis") and strips markdown (`**`, `*`, backticks, `#`, links, lists, blockquotes) from replies before `sendMessage`, since messages go out as plain text. Docs: howto/ai.md (flags, sessions, bridge memory/formatting), `make gen && make check` green.

- **2026-08-09** — Fixed `pos config` secret-value corruption: `cfg_read_secret`'s cursor-advance `echo` went to stdout and, since the function is called via `$(...)`, a leading `\n` ended up inside every secret value → the env file got `AI_GEMINI_API_KEY="\n<key>"`, unreadable by `cfg_value`/`load_config` (menu showed `(not set)`, `pos ai gemini` demanded a key). The newline now goes to the terminal (`echo >&2`). Defense in depth: `cfg_write`/`write_config_key` strip CR and truncate multi-line pastes (warn), `cfg_value` and the ai/telegram `load_config`s strip CR on read. Verified on a real PTY (piped tests couldn't reproduce — non-TTY stdin skips the echo path).

- **2026-08-09** — `ai` category — `pos ai gemini` (ask/chat/models) via Google Gemini REST API. `ask` prints only the answer (pipe/script/Telegram-friendly), `chat` is a multi-turn REPL (q/quit/Ctrl+C, `/reset`, empty input re-prompts), `models` lists generateContent-capable ids and flags the default; `--model` override; default `gemini-2.5-flash`. Config scope `ai` (`AI_GEMINI_API_KEY` secret + `AI_GEMINI_MODEL`) in `~/.config/linux_post_install/ai.env`, edited via `pos config ai`; `config/ai.env` template installed no-clobber by postinstall; `ai-gemini` added to `INTERACTIVE_CMDS`. Telegram listener now answers non-command messages starting with `ai ` via `pos ai gemini ask` (owner chat only; error replies carry the `pos config ai` hint) — future intents (reminders) slot in as more case arms in `handle_message`. Docs: POS.md `ai` section + listener bridge, howto/ai.md, HOWTO/README index rows, `bin/pos` usage example.

- **2026-08-09** — Entertainment plugins `gold` + `weather` now emit emoji-visualized Telegram messages. Gold: headline is USD/**gram** (XAU/oz ÷ 31.1034768), ounce as reference, bid/ask, cleaned timestamp (`+00:00`/fractional seconds stripped). Weather: per-WMO-code emoji (☀️/🌙 day-night aware for clear sky), °C + feels-like, humidity, wind with unit spacing. Both verified live; emojis are safe in the default plain send mode.

- **2026-08-09** — `pos tree`: prints the live `pos` command tree (categories → commands → subcommands) by deriving the hierarchy from `bin/pos-*` filenames + `# POS:` / `# POS_SUBCMDS:` headers, so it always matches what the dispatcher can run. Category-less like `pos-config`; `--depth N` limit; `pos help tree` works. Docs: POS.md `tree` section, `bin/pos` usage example, `make gen` regenerated the AGENT_Context tree/dispatch/filetable + `_pos_flags[tree]`.

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
