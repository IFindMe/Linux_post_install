# How-To: `pos system event-trigger`

State-based threshold monitors: each line of `event.env` is an independent rule;
when a rule's check crosses its threshold you get one alert (plus one recovery
message when it clears). Alerts go through `lib/notify.sh` — Telegram by
default, `NOTIFY_PLATFORM` for more.

```bash
pos system event-trigger config          # interactive rule editor
pos system event-trigger list            # rules + live check values
pos system event-trigger enable 5m       # evaluate every 5 minutes via systemd
pos system event-trigger status          # timer + rule count
pos system event-trigger disable         # stop monitoring
pos system event-trigger run --dry-run   # preview what would fire
```

---

## Rule format

One rule per line in `~/.config/linux_post_install/event.env` (chmod 600):

```
["<message>" if ] <check-command> <op> <threshold>
```

| Part | Meaning |
|------|---------|
| `"<message>" if` | Optional custom alert text (quote-stripped); without it the message is auto-composed |
| `<check-command>` | Any shell command; its **first numeric output** is the value (pipes/args fine) |
| `<op>` | `>` `<` `>=` `<=` `==` `!=` |
| `<threshold>` | Number with optional unit suffix — `60c`, `80%`, `10g` all work |

The operator is detected as the rightmost `op threshold` pair in the line, so
check commands containing their own `>`/`<` (redirection, awk) don't confuse it.

Examples:

```
# event.env
"CPU too hot" if sensors -u coretemp-isa-0000 | awk '/Package id 0:/{f=1} f && /temp1_input:/{print $2; exit}' > 60c
"Disk nearly full" if df -P / | awk 'NR==2{print $5+0}' > 80%
"Load high" if uptime | sed 's/.*load average: //; s/,.*//' >= 4
```

Behavior:

- The check runs on every pass. Non-numeric/empty output, or an unparseable
  line → the rule is skipped with a warning (other rules still run). The
  `run` summary reports how many rules evaluated and how many were skipped.
- `sensors` rules need `lm-sensors` installed (`preinstall.sh` installs it;
  verify with `sensors -u` before adding a rule — sensor names differ by
  chip, check `sensors -u` output for the real `*_input` key). **Gotcha:**
  a bare `grep -m1 temp1_input` can match a *different* chip's `temp1_input`
  first (e.g. `acpitz`'s case temp) instead of the CPU — pin the chip with
  `sensors -u <chip>` (find it in `sensors -u`, e.g. `coretemp-isa-0000`)
  as in the example above.
- Alerts fire **once** when the condition turns true, and once more when it
  recovers — a hot CPU for two hours is one message, not twenty.
- State is tracked per rule in `~/.local/share/linux_post_install/eventer/state/`
  (keyed by a hash of the rule line — editing a rule resets its state).

## Scheduling

`enable [interval]` installs a systemd **user timer** (`pos-event-trigger.timer`
+ oneshot `.service` that runs `pos system event-trigger run`). Intervals:
`5m 10m 15m 30m 45m hourly 2h 6h 12h daily weekly`, or a raw `OnCalendar=…`.
Requires a reachable user systemd manager; run
`sudo loginctl enable-linger $USER` once so timers fire without login (the tool
tries this and warns if it can't).

## Alerting

`run` sends via `lib/notify.sh notify_send`, which delivers to every platform in
`NOTIFY_PLATFORM` (default `telegram`; comma-separated = fan out). Adding a
Matrix/Synapse sender later needs no changes here — see DOC/DEV.md → Alerting.

---

## Related

- Reference: [DOC/POS.md → system](../POS.md#system)
- Notifications: [communication](howto/communication.md) / `lib/notify.sh`
