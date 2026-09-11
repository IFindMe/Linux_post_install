# How-To: `pos system`

Host care: encrypted backups, firewall, health dashboard, persistent aliases, and uninstall. Tools:
`alias`, `backup`, `firewall`, `health`, `uninstall`.

| Tool | What it does |
|------|--------------|
| `pos system alias` | Manage persistent command aliases (wrapper scripts in `~/.local/bin/`) |
| `pos system health` | Host health dashboard (disk, RAM, services, backup age, fail2ban, docker) |
| `pos system backup` | gpg-encrypted (AES-256) folder snapshots |
| `pos system firewall` | Interactive UFW ("UFW POWER") management |
| `pos system uninstall` | Safe, interactive uninstaller for the pos toolkit |

---

## `pos system alias` — persistent command aliases

Create named shortcuts for shell commands. Each alias becomes an executable
wrapper script in `~/.local/bin/` that runs the mapped command with any
arguments forwarded.

### Quick start

```bash
pos system alias                     # interactive menu
pos system alias list                # show all aliases
pos system alias create              # interactive create wizard
pos system alias show restart-dns    # show one alias's details
```

### Examples

**Create an alias:**

```bash
pos system alias create restart-dns
# Step 1: Alias name → restart-dns
# Step 2: Command → sudo systemctl restart systemd-resolved
# Confirm → [y]
# Alias 'restart-dns' created.
# Test it: restart-dns
```

**Create more aliases:**

```bash
pos system alias create exit-google
# Command → pkill -f chrome

pos system alias create update-all
# Command → sudo apt update && sudo apt upgrade -y

pos system alias create my-ip
# Command → curl -s ifconfig.me
```

**Use them directly** (no `pos` needed — just the alias name):

```bash
restart-dns          # runs: sudo systemctl restart systemd-resolved
exit-google          # runs: pkill -f chrome
update-all           # runs: sudo apt update && sudo apt upgrade -y
my-ip                # runs: curl -s ifconfig.me
restart-dns 1.1.1.1  # arguments are forwarded to the command
```

**Edit an alias:**

```bash
pos system alias edit restart-dns
# Shows current command, prompts for new value (Enter = keep current)
```

**Remove an alias:**

```bash
pos system alias remove restart-dns
# Shows details, asks for confirmation (default: no)
```

**List all aliases:**

```bash
pos system alias list
#   Name             Command
#   ---------------- ----------------------------------------
#   restart-dns      sudo systemctl restart systemd-resolved
#   exit-google      pkill -f chrome
```

### How it works

- Aliases are stored in `~/.config/linux_post_install/aliases.env`
  (pipe-delimited: `name|command`, chmod 600).
- Each alias is materialized as an executable wrapper at
  `~/.local/bin/<name>` (chmod 755).
- Wrappers are synced automatically on every `pos system alias` invocation
  — edits are live on the next run.
- Name validation: must start with a letter, then letters/digits/hyphens/
  underscores. Collisions with existing files or PATH binaries are refused.

### PATH requirement

`~/.local/bin` must be on your `PATH` for alias scripts to resolve by name.
If it isn't, you'll see a warning with a fix:

```bash
export PATH="$HOME/.local/bin:$PATH"
# Persist it:
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.profile
```

### Recipes

- **DNS restart shortcut:** `pos system alias create restart-dns`
  with command `sudo systemctl restart systemd-resolved`.
- **Quick app launcher:** `pos system alias create open-code`
  with command `code ~/projects`.
- **Custom backup alias:** `pos system alias create snap-docs`
  with command `pos system backup ~/Documents`.

### Troubleshooting

- `Alias 'X' already exists` → use `pos system alias edit X` instead.
- `File '~/.local/bin/X' already exists` → pick a different name (pos
  won't overwrite non-pos-owned files).
- `~/.local/bin is not on your PATH` → add it to `~/.profile` (see above).
- Alias name autocompletes stale after removal → run `hash -r`.

---

## `pos system health` — host health dashboard

```bash
pos system health                 # console report; exits 1 if any check FAILs
```

Checks: disk per mount (>90% = FAIL), RAM/swap, failed systemd units, backup
age, fail2ban, docker containers. Header shows hostname, uptime, load, public IP.

Health is a **console-only reporter — it never sends notifications**; deliver
its output with a wrapper or a scheduled job (below). `--help` prints the
**effective** config values (env > `system.env` > default), e.g.:

```
Environment (effective values):
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
```

### Daily digest (automated)

Run the health report on a timer with a scheduled job (no systemd unit needed):

```bash
pos system schedule config        # add a job: INTERVAL=daily, NOTIFY=always,
                                  #   COMMAND=pos system health
systemctl --user list-timers | grep pos-schedule
pos system schedule run <name>    # run once now
```

The `NOTIFY=always` policy sends the job's full output — i.e. the dashboard —
as the alert. The old `pos-health.{service,timer}` systemd units are gone — a
legacy install may still have them failed/leftover; disable and remove them:

```bash
sudo systemctl disable --now pos-health.timer pos-health.service 2>/dev/null
sudo rm -f /etc/systemd/system/pos-health.{service,timer} && sudo systemctl daemon-reload
```

**Recipes:**
- Watch the backup age without email: add the daily digest job; if the backup
  check turns WARN you'll see it in the morning report.
- Exit code in a cron/scheduled check:
  `pos system health >/dev/null 2>&1 || notify_send "health FAIL"`.

**Troubleshooting:**
- `[WARN] fail2ban installed but not running` → expected unless you have it
  active; start it (`sudo systemctl enable --now fail2ban`) or ignore.
- `[FAIL] services: nbd-server.service …` → a failed unit; inspect with
  `systemctl status <unit>`.

---

## `pos system backup` — encrypted folder snapshots

```bash
pos system backup <folder-path>                 # encrypt to ./<name>_<date>.tar.gz.gpg
pos system backup <folder-path> --no-encrypt    # plain ./<name>_<date>.tar.gz, no password
pos system backup --service                     # pick a folder from /srv + ~/srv
```

Uses `sudo tar` + gpg AES-256. The password is prompted **twice and never
stored**; the artifact is `chmod 600`. On success (and on failure, via ERR
trap) a `notify_send` alert is sent.

**Skip encryption** with `--no-encrypt` (or `BACKUP_ENCRYPT=0` in
`system.env`): the archive stays a plain `.tar.gz`, no password is prompted,
and the file is still `chmod 600` + USB-copy verified. This is the
**headless/cron-safe** mode — the encrypted path prompts for a password, so
under cron it needs `--no-encrypt` with a fixed folder
(`pos system backup ~/Documents --no-encrypt`).

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

Detection reads `lsblk` and treats a device as USB when `TRAN == usb` (the
per-device deciding signal). Removable-but-not-USB slots (e.g. a SATA card
reader) are skipped. If a device shows no `TRAN` at all, `lsblk`'s answer is
cross-checked against `/dev/disk/by-id/usb-*` symlinks and `lsusb` before it is
offered.

**Unmounted stick?** If the USB stick is plugged in but only shows as `sdax`
with no mountpoint (common on CLI boxes with no automounter), you're offered a
**mount first**, then it copies there:

```bash
#   [!] Found USB storage not mounted: /dev/sda1 (7.5G, DataTraveler)
#   Mount it at /media/usb-sda1 (world-writable) so the backup can go there? [y/N]
#   (y)  OK Mounted /dev/sda1 at /media/usb-sda1
#   [+] Copying to /media/usb-sda1/backups/docs_2026-08-13.tar.gz.gpg ...
#   OK Transfer verified 100% (sha256 match): .../backups/docs_2026-08-13.tar.gz.gpg
```

The mount mirrors `usb-automount` (`/media/<label>`, fallback
`/media/usb-<devname>`, `-o umask=000` world-writable so the copy works without
root). Decline it and you get the exact `sudo mkdir -p` / `sudo mount` commands
to run yourself, then `Enter` re-checks. `s` or EOF (cron) skips silently and
the backup stays local — it never blocks.

- Multiple sticks mounted → pick by number; `0` skips; `n`/EOF skips silently
  (cron runs never block).
- Pin a fixed stick (no detection, no prompt on cron) with
  `BACKUP_USB_ROOT=/mnt/usb` in `system.env` — the copy still lands in
  `<root>/backups/` and is still sha256-verified.
- Mount base and by-id dir are configurable: `BACKUP_MOUNT_BASE` (default
  `/media`) and `BACKUP_USB_BYID` (default `/dev/disk/by-id`).

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

## `pos system uninstall` — remove the pos toolkit

```bash
pos system uninstall                       # interactive scan + confirm tier 1
pos system uninstall --yes                 # non-interactive, tier 1 only
pos system uninstall --yes --config --data # remove everything (nuclear option)
```

Scans the system for installed pos components and removes them in three tiers:

| Tier | What it removes | How to include |
|------|----------------|----------------|
| **Tier 1** | Binaries (`/usr/local/bin/pos*`, libs, entertainment plugins, prebuilt, features), systemd services (disable+remove), shell integration (`~/.bashrc` PATH/completion/pos-ai-hook entries), completion file | Always (default) |
| **Tier 2** | Config files (`~/.config/linux_post_install/` — `.env` files, `schedule.d/`, `authorized_keys`, `rclone.conf`) | `--config` flag |
| **Tier 3** | Session/log data (`~/.local/share/linux_post_install/` — AI sessions, logs, captured output) | `--data` flag |

The default mode is interactive: it shows what will be removed and asks for
confirmation. The git repo is **never** removed — delete it manually if desired.

**Recipes:**
- Quick cleanup: `pos system uninstall --yes`
- Full wipe: `pos system uninstall --yes --config --data`
- Safe preview: run `pos system uninstall` without `--yes` to see the plan first

**Troubleshooting:**
- "Nothing to remove" → pos toolkit is not installed (or already removed)
- After uninstall, run `source ~/.bashrc` or restart your shell

---

## Related

- Reference: [DOC/POS.md → system](../POS.md)
- Notify platform config: [communication.md](communication.md)
- Backup roots shared with health: `system.env` ([DOC/POS.md](../POS.md))
- Alias storage: `~/.config/linux_post_install/aliases.env` ([DOC/POS.md → pos system alias](../POS.md#pos-system-alias-in-detail))
