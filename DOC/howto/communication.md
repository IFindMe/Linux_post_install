# How-To: `pos communication`

Telegram messaging and alerts. Tools: `telegram`, `matrix`.

| Tool | What it does |
|------|--------------|
| `pos communication telegram` | Send messages/files, manage config, webhook state, message logs |
| `pos communication matrix` | Matrix/Synapse sender (extensible; not yet implemented) |

`telegram` is the workhorse: it backs the whole **notify system** — health
digests, backup alerts, firewall changes — and can be used directly.

---

## `pos communication telegram`

### One-time setup

```bash
pos communication telegram config set TELEGRAM_BOT_TOKEN=123456:ABC...
pos communication telegram config set TELEGRAM_CHAT_ID=987654321
pos communication telegram config set TELEGRAM_DISABLE_WEBHOOK=true   # if used with webhooks
pos communication telegram config
# config lives in ~/.config/linux_post_install/telegram.env (chmod 600)
```

The bot token comes from @BotFather, the chat ID from @userinfobot (or by
starting a chat and reading it). To set your display name once: message
`/start` to your bot, then `pos communication telegram chat-id` prints it.

### Send

```bash
pos communication telegram send "hello from my server"      # plain text
pos communication telegram send --markdown "**bold** ok"    # parse as markdown
pos communication telegram send --help                     # list all flags
pos communication telegram file /path/to/report.pdf         # send a document
pos communication telegram broadcast "restarting in 5min"   # to all known chat IDs
```

### State & logs

```bash
pos communication telegram getwebhookinfo        # current webhook + pending count
pos communication telegram setwebhook https://... # point a webhook URL (or "")
pos communication telegram deletemenu            # clear the bot menu
pos communication telegram logs                  # recent send history (logs dir)
pos communication telegram clear-logs            # wipe message logs
```

**Recipes:**
- **Alert when a backup finishes** — automatic: `pos system backup` calls
  `notify_send` (below) on success *and* failure.
- **Warn before a service update:**
  ```bash
  pos communication telegram send "Maintenance: docker compose down in 2min"
  ```
- **On-call file drop:** `pos communication telegram file ~/log/nginx-error.log`

**Troubleshooting:**
- "Not configured (no token or chat id)" → run `config set` for both values.
- Send succeeds but nothing arrives → the chat must have started the bot
  (press `Start` / send `/start` once).
- **Markdown silently empty** → Telegram uses its own MarkdownV2; unmatched
  syntax makes the message vanish. Use `--markdown` only when the text is
  Telegram-safe (the health digest output is).
- **Webhook vs getUpdates:** if your bot has an active webhook, `send` may
  still work (we disable the webhook automatically when it owns it) — but if
  another process registered the webhook, polls fail; `deletemenu`/webhook
  state shows ownership. See `getwebhookinfo`.

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
