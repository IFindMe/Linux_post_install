# How-To: `pos system schedule`

Scheduled jobs: run any shell command on a timer and have the result sent via
`lib/notify.sh` (Telegram by default, `NOTIFY_PLATFORM` for more) — or run it
silently. Unlike the old `event-trigger` threshold monitors, each job has its
own interval and its own notify policy.

```bash
pos system schedule list                  # jobs + notify policy + last run
pos system schedule enable                # start all job timers (per-job intervals)
pos system schedule status                # per-job timer state + next run
pos system schedule run nvme-health       # run one job now
pos system schedule run all --dry-run     # preview everything
pos system schedule disable cpu-temp      # stop a job, keep the file
pos system schedule migrate               # convert old event.env rules
pos system schedule config                # interactive job editor
```

---

## Job format

One file per job in `~/.config/linux_post_install/schedule.d/<name>.env`
(chmod 600):

```
INTERVAL=hourly            # 5m..59m | 1h..23h | hourly daily weekly | OnCalendar=…
NOTIFY=onchange            # always | onchange | onerror | threshold | never
MSG="NVMe health"          # optional label; threshold alert text when NOTIFY=threshold
RULE="> 60c"               # threshold only: op + threshold (unit suffix fine: 60c, 80%)
COMMAND=…                  # literal rest of the line — pipes/quotes/sudo fine
ENABLED=false              # written by `disable`; default enabled
```

The `COMMAND=` value is everything after the prefix — no quoting/escaping of
pipes, quotes, or `sudo`. The job runs it with `bash -c` and observes the
exit code. Only `INTERVAL` is required (default `5m`); `NOTIFY` defaults to
`threshold` when `RULE` is present, otherwise `onchange`.

### Notify policies

| Policy | Behavior |
|--------|----------|
| `threshold` | Runs the command, compares its **first numeric output** against `RULE` (float-safe). Alerts once on false→true plus one recovery message on true→false — a hot CPU for two hours is one message, not twenty. `MSG` is the alert text (auto-composed when absent) |
| `onchange` | Sends the output only when it differs from the last run. First run always sends. Best for "tell me when this changes" reports |
| `always` | Sends the full output on every run |
| `onerror` | Sends only when the command fails (non-zero exit or empty output), with the `rc` |
| `never` | Runs and logs, never notifies — side-effect jobs (cleanups, backups) |

Every run also writes a per-job log + last-run record
(`~/.local/share/linux_post_install/schedule/{logs,state}/`) so `list`/`status`
show the result even for `never` jobs.

## Example — NVMe health every hour

Your exact use case:

```
# ~/.config/linux_post_install/schedule.d/nvme-health.env
INTERVAL=hourly
NOTIFY=onchange
MSG=NVMe health
COMMAND=sudo -n smartctl -a /dev/nvme0n1 | grep -Ei 'critical_warning|temperature|available_spare|percentage_used|media_errors|error_information'
```

Two setup notes:

1. **Passwordless sudo for smartctl.** User timers have no tty, so `sudo` needs
   a NOPASSWD rule (smartmontools is in `preinstall.sh` PACKAGES):
   ```bash
   echo '%sudo ALL=(ALL) NOPASSWD: /usr/sbin/smartctl' | sudo tee /etc/sudoers.d/smartctl
   ```
   (Use `/usr/sbin/smartctl` — check `command -v smartctl`.) The `-n` flag makes
   `sudo` fail instead of hanging if the rule is missing, which `onerror` will
   report.
2. **`temperature` drifts**, so an `onchange` job on this grep will fire most
   hours. If you only want fault-field alerts, drop the `temperature`
   alternative: `grep -Ei 'critical_warning|available_spare|percentage_used|media_errors|error_information'`.

## Example — threshold rule (old event-trigger style)

```
# cpu-temp.env
INTERVAL=5m
NOTIFY=threshold
MSG=CPU too hot
RULE="> 60c"
COMMAND=sensors -u coretemp-isa-0000 | awk '/Package id 0:/{f=1} f && /temp1_input:/{print $2; exit}'
```

Gotchas carried over from event-trigger:

- Non-numeric/empty output → the job is skipped with a warning (others still run).
- **Pin the chip in `sensors` rules** — a bare `grep -m1 temp1_input` can match a
  different chip's `temp1_input` first (e.g. `acpitz`'s case temp). Find the
  real name in `sensors -u` (e.g. `coretemp-isa-0000`) and pin it as above.
- Unit suffixes on the threshold are fine: `60c`, `80%`, `10g`.

## Example — silent side-effect job

```
# log-cleanup.env — never notifies
INTERVAL=weekly
NOTIFY=never
COMMAND=find ~/.local/share/linux_post_install/logs -type f -name '*_pos_*.log' -mtime +30 -delete
```

## Scheduling

Each enabled job gets its own systemd **user timer pair**
(`pos-schedule-<name>.timer` + oneshot `.service` running
`pos system schedule run <name>`, `Persistent=true` — missed runs fire on next
boot/login). `enable`/`disable` reconcile the timers with `schedule.d/` and
remove orphaned units; the legacy single `pos-event-trigger` timer is cleaned
up automatically. Requires a reachable user systemd manager; run
`sudo loginctl enable-linger $USER` once so timers fire without login (the tool
tries this and warns if it can't).

## Migrating from event-trigger

If you have rules in `~/.config/linux_post_install/event.env`, convert them in
place:

```bash
pos system schedule migrate
```

Each rule becomes `schedule.d/rule-N.env` with `NOTIFY=threshold`, the legacy
timer's interval (or `5m`), and the rule split into `MSG`/`RULE`/`COMMAND`.
The old timer is disabled and removed; run `pos system schedule enable` to
start the migrated jobs.

`migrate` copies the rule's left side **verbatim** as `COMMAND` — the old tool
ran it literally and never had `disk root`/`loadavg`-style shorthands. A rule
like `disk root > 80%` migrates, but its job will log "produced no number" on
every run. After migrating, rewrite such jobs with a real command, e.g.
`COMMAND=df -P / | awk 'NR==2{print $5+0}'` (see the `config/schedule.d/`
starter jobs for patterns).

## Alerting

`run` sends via `lib/notify.sh notify_send`, which delivers to every platform
in `NOTIFY_PLATFORM` (default `telegram`; comma-separated = fan out). Adding a
Matrix/Synapse sender needs no changes here — see DOC/DEV.md → Alerting.

---

## Related

- Reference: [DOC/POS.md → system](../POS.md#system)
- Notifications: [communication](howto/communication.md) / `lib/notify.sh`
