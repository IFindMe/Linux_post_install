# How-To: `pos entertainment`

Auto-published fun messages from public APIs, with per-plugin scheduling.
Tools: `config`, `enable`, `disable`, `send`, `status`.

| Tool | What it does |
|------|--------------|
| `pos entertainment send` | Fetch a plugin's message to stdout (dry-run) |
| `pos entertainment enable <plugin> [interval]` | Schedule auto-sends |
| `pos entertainment disable <plugin>` | Remove the schedule |
| `pos entertainment status` | List plugins + their active schedules |
| `pos entertainment config set|get` | Plugin keys in `entertainment.env` |

### Plugins

| Plugin | API | Config keys |
|--------|-----|-------------|
| `weather` | Open-Meteo (no key) | `WEATHER_LAT`, `WEATHER_LON` (req), `WEATHER_CITY` (opt) |
| `joke` | icanhazdadjoke (no key) | — |
| `gold` | goldprice.dev (no key) | — |

Interval (systemd time): `5m`, `10m`, `30m`, `1h`, `2h`, `6h`, `12h`, `daily`,
`weekly`.

---

## First run — configure, test, schedule

```bash
pos entertainment config set WEATHER_LAT=36.51 WEATHER_LON=40.75 WEATHER_CITY="Berlin"

pos entertainment send weather     # stdout test — message for Telegram
pos entertainment send joke
pos entertainment send gold

pos entertainment enable weather daily     # once a day
pos entertainment enable joke 2h           # every 2 hours
pos entertainment disable gold

pos entertainment status                   # plugins + active schedules
```

## How it works

- **Scheduling** uses systemd **user** timers only (unit
  `pos-entertainment-<plugin>.timer` in `~/.config/systemd/user/`). Interval is
  resolved through the same systemd-time parser used by `.timer` units —
  invalid values are rejected with a clear message.
- **Delivery** goes through `notify_send`, so the platform follows
  `NOTIFY_PLATFORM` (default Telegram). If no platform is configured, enable
  still works — the plugin fetches and tries to notify, silently no-ops when
  unconfigured.

**Recipes:**
- **Morning weather + joke:** `enable weather daily`, `enable joke daily`; the
  08:00 health digest plus these make a nice wake-up.
- **Add a plugin:** it's a `POS_PLUGIN` script in `entertainment/`; stdout is
  the message, `POS_KEYS` lines declare config keys. See
  [DOC/DEV.md → "Adding a plugin"](../DEV.md).

**Troubleshooting:**
- `send weather` prints an error about coordinates → set `WEATHER_LAT`/
  `WEATHER_LON` (required keys) via `config set`.
- `enable` fails on the interval → the value isn't valid systemd time; use one
  of: `5m 10m 30m 1h 2h 6h 12h daily weekly`.
- Nothing arrives even though `status` shows the timer → check `notify.env`
  (`NOTIFY_PLATFORM`) and that `telegram.env` is configured (see
  [communication](communication.md)); confirm the timer fired:
  `systemctl --user list-timers pos-ent-*`.
- Public-API flakiness → the plugin outputs a clear failure; the notify call is
  silent-fail by design.

---

## Related

- Reference + plugin list: [DOC/POS.md → entertainment](../POS.md)
- Notify platform: [communication.md](communication.md)
- Writing a plugin: [DOC/DEV.md](../DEV.md)
