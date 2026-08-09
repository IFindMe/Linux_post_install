# How-To: `pos communication`

Telegram messaging and alerts. Tools: `telegram-sender`, `telegram-listener`,
`matrix`.

| Tool | What it does |
|------|--------------|
| `pos communication telegram sender` | Send messages/files/links/stickers, test, config (token + chat id) |
| `pos communication telegram listener` | Bot listener: map `/command` → bash and run it from chat (systemd user daemon) |
| `pos communication matrix` | Matrix/Synapse sender (extensible; not yet implemented) |

`telegram-sender` is the workhorse: it backs the whole **notify system** —
health digests, backup alerts, firewall changes — and can be used directly.

---

## `pos communication telegram sender`

### One-time setup

```bash
pos config telegram
# edit TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID (masked input), then test:
pos communication telegram sender test
# config lives in ~/.config/linux_post_install/telegram.env (chmod 600)
```

The bot token comes from @BotFather, the chat ID from @userinfobot (or by
starting a chat and reading it). `pos config telegram` shows the current values
(token masked).

### Send

```bash
pos communication telegram sender send "hello from my server"    # plain text
pos communication telegram sender send --markdown "**bold** ok"  # parse as markdown
pos communication telegram sender send --help                    # list all flags
pos communication telegram sender send /path/to/report.pdf       # auto-detects file
```

**Recipes:**
- **Alert when a backup finishes** — automatic: `pos system backup` calls
  `notify_send` (below) on success *and* failure.
- **Warn before a service update:**
  ```bash
  pos communication telegram sender send "Maintenance: docker compose down in 2min"
  ```
- **On-call file drop:** `pos communication telegram sender send ~/log/nginx-error.log`

**Troubleshooting:**
- "Not configured (no token or chat id)" → run `pos config telegram` and set both values.
- Send succeeds but nothing arrives → the chat must have started the bot
  (press `Start` / send `/start` once).
- **Markdown silently empty** → Telegram uses its own MarkdownV2; unmatched
  syntax makes the message vanish. Use `--markdown` only when the text is
  Telegram-safe (the health digest output is).
- **Webhook vs getUpdates:** the sender uses polling (`getUpdates`), so a
  webhook registered on the bot (e.g. via BotFather) blocks sends; remove it
  with BotFather's `/deletewebhook`.

---

## `pos communication telegram listener`

Turns your bot into a two-way remote control: map `/command` → bash, then
message the bot from your phone to run it.

```bash
pos communication telegram listener             # edit the /command → bash map
pos communication telegram listener --status    # service state + mapped commands
pos communication telegram listener --enable    # install the systemd user daemon
pos communication telegram listener --disable   # remove it
```

- **Map file:** `~/.config/linux_post_install/telegram_commands.env` (chmod 600),
  one `/cmd=bash command` per line — re-read on every message, so edits apply
  instantly. Example:
  ```
  /status=@quiet pos system health --send
  /temp=sensors | grep -i 'Tctl\|package id 0'
  /update=cd /path/to/repo && git pull
  ```
- **Bot command menu:** the mapped commands are pushed to the bot's `/` menu
  (`setMyCommands`) after every map edit, on `--enable`, and at daemon start
  (force it anytime with `--sync-commands`). Add a short description with the
  `/cmd::description=bash command` syntax — e.g.
  `/backup::Encrypted nightly backup=@quiet pos system backup --send` — or it
  falls back to the bash command. Telegram only registers lowercase `[a-z0-9_]`
  names (1–32 chars); `/Status` or `/my-cmd` are skipped from the menu but still
  work when typed. An empty map clears the menu.
- **Owner-only:** the bot only reacts to `TELEGRAM_CHAT_ID` (your own chat);
  others are ignored. `/help` lists mapped commands; unknown → "Unknown command".
- **Runs as you:** mapped commands execute as your user with a 60s timeout,
  stdout + stderr are replied to the chat (truncated ~3800 chars; empty → `OK`).
  `sudo` inside a command needs a NOPASSWD rule.
- **`@quiet` prefix:** a map value starting with `@quiet ` runs the command but
  does NOT reply — for commands that already send their own notification, so
  you don't get it twice. `/status=@quiet pos system health --send` delivers
  one digest via the notify system and nothing else.
- **Daemon lifecycle:** the service is a systemd **user** unit; it stops at
  logout unless you enable linger: `sudo loginctl enable-linger $(whoami)`.
  `--enable` prints this warning if linger is off.

**Troubleshooting:**
- Bot doesn't answer → send `/help`; if silent, check the service with
  `systemctl --user status pos-telegram-listener.service`.
- A webhook on the bot blocks `getUpdates` → remove it with BotFather's
  `/deletewebhook`.
- Needs `jq` (in preinstall PACKAGES).

---

## The notify system (`notify_send`)

Every tool that announces something sends through `lib/notify.sh` instead of
hard-coding Telegram:

```bash
# ~/.config/linux_post_install/notify.env
NOTIFY_PLATFORM=telegram        # default; comma-separated to fan out to all
```

- `notify_send "msg"` → delivers to every platform in `NOTIFY_PLATFORM`
  (current senders: `telegram`).
- **Silent-fail:** no platform configured → one WARN line, exit 0, never
  breaks the calling tool.
- New platform (e.g. Matrix): implement `bin/pos-communication-<p> send
  <value> [--markdown]`, then list it in `NOTIFY_PLATFORM`. Details:
  [DOC/DEV.md → Alerting](../DEV.md).

---

## `pos communication matrix`

Sender contract exists (`send <value> [--markdown]`) and the dispatcher routes
to it, but no implementation ships yet. When present, add `matrix` to
`NOTIFY_PLATFORM` and configure it via `pos communication matrix config set …`.

---

## Related

- Reference + config file details: [DOC/POS.md → communication](../POS.md)
- Alerting contract: [DOC/DEV.md → Alerting](../DEV.md)
- Health digest (uses `--send --markdown`): [system.md](system.md)
