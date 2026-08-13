# How-To: `pos communication`

Messaging and alerts over Telegram and Matrix, plus Android mirroring. Tools:
`telegram-sender`, `telegram-listener`, `matrix-sender`, `matrix-listener`,
`scrcpy`.

| Tool | What it does |
|------|--------------|
| `pos communication telegram sender` | Send messages/files/links/stickers, test, config (token + chat id) |
| `pos communication telegram listener` | Bot listener: map `/command` → bash and run it from chat (systemd user daemon) |
| `pos communication matrix sender` | Send messages to a Matrix room via the client-server API (send, test, login) |
| `pos communication matrix listener` | Matrix listener: map `/command` → bash and run it from room messages (systemd user daemon) |
| `pos communication scrcpy` | Mirror/control an Android device over USB or WiFi (scrcpy+adb) |

`telegram-sender` is the workhorse: it backs the whole **notify system** —
health digests, backup alerts, firewall changes — and can be used directly.
`matrix-sender` plugs into the same system as a second platform.

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
  (current senders: `telegram`, `matrix`).
- **Silent-fail:** no platform configured → one WARN line, exit 0, never
  breaks the calling tool.
- New platform: implement `bin/pos-communication-<p> send
  <value> [--markdown]`, then list it in `NOTIFY_PLATFORM`. Details:
  [DOC/DEV.md → Alerting](../DEV.md).

---

## `pos communication matrix sender`

Send plain-text (or markdown-formatted) messages to a Matrix room via the
homeserver's client-server API (v3). No bot is needed — it uses a regular
account's access token.

### One-time setup

```bash
pos config matrix
# set MATRIX_HOMESERVER (https://matrix.example.org) and MATRIX_ROOM_ID
# (room id or alias like #ops:example.org), then grab a token:
pos communication matrix sender login --user @you:example.org
# password is prompted (masked) — access token + user id are saved
pos communication matrix sender test
# config lives in ~/.config/linux_post_install/matrix.env (chmod 600)
```

`login` calls the homeserver's password endpoint and stores the resulting
access token in `matrix.env` (masked by `pos config matrix`). Tokens from any
Matrix client (Element, `synctl`…) work too — set `MATRIX_ACCESS_TOKEN`
directly. Requires network access to your homeserver.

### Send

```bash
pos communication matrix sender send "Backup finished"          # plain text
pos communication matrix sender send --markdown "**bold** ok"   # org.matrix.custom.html
pos communication matrix sender send "hi" --room '#ops:example.org'  # one-shot override
pos communication matrix sender test                            # canned test message
```

`--markdown` sends with `org.matrix.custom.html` (best-effort markdown →
HTML: `**bold**`, `` `code` ``, links, headers, lists). Room ids and aliases
are URL-encoded automatically.

**Troubleshooting:**
- "No access token" → run `pos communication matrix sender login` first.
- Login fails → is the homeserver URL right (`pos config matrix`) and is the
  account password correct? Homeservers may require the full
  `@user:example.org` id.
- Nothing arrives → the room id/alias must exist and the account must be a
  member. Public aliases like `#pos:example.org` work when the account has
  joined.

---

## `pos communication matrix listener`

Turns any room you're in into a remote control for your server: message your
own account a `/command` and the mapped bash runs.

```bash
pos communication matrix listener             # edit the /command → bash map
pos communication matrix listener --status    # service state + mapped commands
pos communication matrix listener --enable    # install the systemd user daemon
pos communication matrix listener --disable   # remove it
```

- **Map file:** `~/.config/linux_post_install/matrix_commands.env` (chmod 600),
  one `/cmd=bash command` per line — re-read on every message, so edits apply
  instantly. Example:
  ```
  /status=@quiet pos system health --send
  /temp=sensors | grep -i 'Tctl\|package id 0'
  /update=cd /path/to/repo && git pull
  ```
- **Self-messaging:** the listener reacts to messages **from your own user id**
  (`MATRIX_USER_ID`) — in practice that means a second device (or another
  account) sending the commands. If `MATRIX_ROOM_ID` is set it only watches
  that room, otherwise every room you've joined. `/` and `!` both work
  (`!status` = `/status`). `/help` lists mapped commands; unknown → "Unknown
  command".
- **Runs as you:** mapped commands execute as your user with a 60s timeout,
  stdout + stderr are replied to the room as a thread reply to your message
  (truncated ~3800 chars; empty → `OK`). `sudo` inside a command needs a
  NOPASSWD rule.
- **`@quiet` prefix:** a map value starting with `@quiet ` runs the command but
  does NOT reply — for commands that already send their own notification.
- **`ai …` bridge:** non-command messages starting with `ai ` are answered by
  `pos ai gemini` (per-room memory session; `ai /reset` clears it) — replying
  with the model's answer, markdown stripped.
- **Daemon lifecycle:** the service is a systemd **user** unit; it stops at
  logout unless you enable linger: `sudo loginctl enable-linger $(whoami)`.
  `--enable` prints this warning if linger is off.

**Troubleshooting:**
- Doesn't answer → check the service with
  `systemctl --user status pos-matrix-listener.service`; the daemon logs to
  `~/.local/share/linux_post_install/logs/pos.log`.
- "Unknown command" → send `/help` for the mapped list.
- Needs `jq` (in preinstall PACKAGES).

---

## `pos communication scrcpy`

Mirror and control an Android device from the PC — the phone's screen in a
window, controlled with mouse + keyboard (scrcpy by Genymobile, no root, no
phone app). Works over USB or WiFi.

### One-time setup

```bash
# phone: Settings → About → tap "Build number" 7× → Developer options → enable
# "USB debugging"; plug it in and accept the "Allow USB debugging" dialog
pos communication scrcpy devices          # confirm the phone shows as "device"
pos communication scrcpy info             # model / Android version
pos config scrcpy                         # optional defaults (serial, size, fps, ...)
```

Requires `scrcpy` + `adb` (both in preinstall PACKAGES). The apt build is older
than the latest release — install the current GitHub release (bundles `adb`)
with the optional app `apps/media/scrcpy.sh` (or `./install.sh --apps`).

### Mirror

```bash
pos communication scrcpy                          # USB device, config defaults
pos communication scrcpy --turn-screen-off        # pass any scrcpy flag through
pos communication scrcpy --no-audio --always-on-top
```

The window needs a display — over ssh use `ssh -X` (and a phone already
reachable over WiFi, see below). `scrcpy --help` lists every flag; the wrapper
forwards flags verbatim.

### Wireless (no USB cable)

```bash
pos communication scrcpy tcpip 5555       # switch the USB device to WiFi adb
# unplug the phone, then:
pos communication scrcpy connect 192.168.1.42:5555   # connect + mirror
```

`tcpip` prints the exact `connect` command with the phone's detected IP. Set
`SCRCPY_SERIAL` in `pos config scrcpy` so later bare `pos communication scrcpy`
goes straight to that device.

### Record / screenshot / files

```bash
pos communication scrcpy record --headless     # record to ~/Videos/scrcpy/, no window
pos communication scrcpy record clip.mp4        # explicit file
pos communication scrcpy screenshot             # PNG to ~/Videos/scrcpy/
pos communication scrcpy push ~/app.apk         # → /sdcard/Download/
pos communication scrcpy pull /sdcard/DCIM/Camera ~/photos
```

These all work headless — handy on the homelab box for grabbing a phone's
screen/file without a desktop.

**Troubleshooting:**
- "no device connected" → is USB debugging on, is the "Allow USB debugging"
  dialog accepted, and does `pos communication scrcpy devices` show the serial?
- Device shows `offline`/`unauthorized` → re-accept the USB debugging dialog on
  the phone (unplug/replug); `adb kill-server` may help.
- "not reachable" after `tcpip` → the phone's WiFi IP changed; re-check with
  `adb devices` or run `tcpip` again while plugged in.
- Mirror window is blank / no audio → older apt scrcpy lacks features; install
  the latest with the `apps/media/scrcpy.sh` app installer.
- `ssh -X` mirror is slow → prefer WiFi or a wired LAN; bump `SCRCPY_MAX_FPS`
  down or set `SCRCPY_BIT_RATE` lower in `pos config scrcpy`.

---

## Related

- Reference + config file details: [DOC/POS.md → communication](../POS.md)
- Alerting contract: [DOC/DEV.md → Alerting](../DEV.md)
- Health digest (uses `--send --markdown`): [system.md](system.md)
