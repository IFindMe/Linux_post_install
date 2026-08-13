# How-To: `pos system`

Host care: encrypted backups, firewall, and the health dashboard. Tools:
`backup`, `firewall`, `health`.

| Tool | What it does |
|------|--------------|
| `pos system health` | Host health dashboard (disk, RAM, services, backup age, fail2ban, docker) |
| `pos system backup` | gpg-encrypted (AES-256) folder snapshots |
| `pos system firewall` | Interactive UFW ("UFW POWER") management |

---

## `pos system health` — host health dashboard

```bash
pos system health                 # console report; exits 1 if any check FAILs
pos system health --send          # also send the summary via notify platforms
pos system health --markdown      # same, markdown parse mode (implies --send)
```

Checks: disk per mount (>90% = FAIL), RAM/swap, failed systemd units, backup
age, fail2ban, docker containers. Header shows hostname, uptime, load, public IP.

`--help` prints the **effective** config values (env > `system.env` > default),
e.g.:

```
Environment (effective values):
  NOTIFY_PLATFORM             telegram
  HEALTH_BACKUP_MAX_AGE_DAYS  2
  BACKUP_SERVICE_ROOTS        /srv $HOME/srv
```

(`$HOME` is resolved at runtime — on this host that is `/srv /home/unknown/srv`.)

### Configuration

```bash
# ~/.config/linux_post_install/system.env   (comment-only defaults — uncomment to override)
BACKUP_SERVICE_ROOTS=/srv $HOME/srv    # roots for backup-age check + backup --service
BACKUP_USB_ROOT=/mnt/usb               # optional: copy finished backups to <root>/backups/ (auto-detects a mounted USB when unset)
HEALTH_BACKUP_MAX_AGE_DAYS=3           # WARN if newest backup older (default 2)
# ~/.config/linux_post_install/notify.env
NOTIFY_PLATFORM=telegram
```

### Daily digest (automated)

`systemd/pos-health.{service,timer}` run `pos system health --send --markdown`
at 08:00 as the installing user. Enable it (re-run postinstall after Telegram
is configured):

```bash
./postinstall.sh                      # enables timer once telegram.env exists
systemctl list-timers | grep pos-health
systemctl start pos-health.service    # run once now, check status
```

**Recipes:**
- Watch the backup age without email: enable the digest; if the backup check
  turns WARN you'll see it in the morning report.
- Exit code in a cron/scheduled check:
  `pos system health >/dev/null 2>&1 || notify_send "health FAIL"`.

**Troubleshooting:**
- `[WARN] fail2ban installed but not running` → expected unless you have it
  active; start it (`sudo systemctl enable --now fail2ban`) or ignore.
- `[FAIL] services: nbd-server.service …` → a failed unit; inspect with
  `systemctl status <unit>`.
- `--send` prints a warn and exits 0 when no platform is configured — by design
  (see [communication](communication.md)).

---

## `pos system backup` — encrypted folder snapshots

```bash
pos system backup <folder-path>       # encrypt to ./<name>_<date>.tar.gz.gpg
pos system backup --service           # pick a folder from /srv + ~/srv
```

Uses `sudo tar` + gpg AES-256. The password is prompted **twice and never
stored**; the artifact is `chmod 600`. On success (and on failure, via ERR
trap) a `notify_send` alert is sent.

`--service` lists folders under the roots in `BACKUP_SERVICE_ROOTS`
(default `/srv $HOME/srv`; override via `system.env` or env) and lets you pick.

### Copy to a USB stick

After the archive verifies, connected USB storage is **detected** (so a stick
plugged in while the backup was running is found — if none is mounted you get
one chance to plug one in and re-check) and you're asked whether to copy the
backup there. The copy lands in `<usb>/backups/` and is **verified 100%**
(sha256 source vs copy) before any success is announced:

```bash
pos system backup ~/Documents
# ... after the archive verifies:
#   [!] No USB storage detected
#   Plug a USB drive in now and press Enter to re-check (or 's' to skip):
#   [+] Copying to /media/you/USB-DISK/backups/docs_2026-08-13.tar.gz.gpg ...
#   OK Transfer verified 100% (sha256 match): .../backups/docs_2026-08-13.tar.gz.gpg
```

- Multiple sticks mounted → pick by number; `0` skips; `n`/EOF skips silently
  (cron runs never block).
- Pin a fixed stick (no detection, no prompt on cron) with
  `BACKUP_USB_ROOT=/mnt/usb` in `system.env` — the copy still lands in
  `<root>/backups/` and is still sha256-verified.

### Recipes

- **Nightly service backup + health check:**
  ```bash
  cd ~/backups && pos system backup --service
  pos system health          # "backup: 0d old" turns OK
  ```
- **Cron it and get alerted:**
  ```bash
  30 3 * * * cd ~/backups && pos system backup --service >> ~/backups/backup.log 2>&1
  ```
  Success/failure are sent to Telegram automatically.

**Troubleshooting:**
- "Root not found: …" → the default roots don't exist; set `BACKUP_SERVICE_ROOTS`
  in `system.env`.
- Forgot the password → backups are unrecoverable; keep the passphrase in a
  password manager. Nothing is stored anywhere else.
- `sudo tar` prompt: ensure the user has sudo rights for the source dir.
- "USB copy FAILED verification — checksum mismatch" → the copy is corrupt
  (bad stick or transfer); the local archive is untouched — copy it again
  manually and replace the file on the stick.

---

## `pos system firewall` — interactive UFW ("UFW POWER")

**Must run as root:**

```bash
sudo pos system firewall
```

Interactive menu: add rule (port/service/IP/directional), delete by number or
text, status (simple/verbose/numbered), enable/disable/reset, default policies,
and an executed-command history. Supports `--dry-run`:

```bash
sudo pos system firewall --dry-run
```

Every command is **previewed and confirmed** before execution. Executed
mutating changes are announced via `notify_send` (read-only `ufw status` is
not).

### Recipes
- Open SSH + a service:
  `add rule → port/service → 22/tcp`, then `8080/tcp`; finish with `enable`.
- See current rules for deletion: menu `3) Show status → numbered`.
- `--dry-run` to rehearse a rule batch safely.

**Troubleshooting:**
- "Please run as root" → you need `sudo pos system firewall` (the notify config
  still uses your user's `$HOME`, so alerts keep working).
- Accidentally locked yourself out of SSH → console into the host,
  `sudo ufw allow 22/tcp`, then `sudo ufw reload`.
- `ufw reset` requires typing `RESET` — deliberate.

## Related

- Reference: [DOC/POS.md → system](../POS.md)
- Notify platform config: [communication.md](communication.md)
- Backup roots shared with health: `system.env` ([DOC/POS.md](../POS.md))
