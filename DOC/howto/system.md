# How-To: `pos system`

Host care: encrypted backups, firewall, health dashboard, uninstall, and the
persistent command bank. Tools: `backup`, `firewall`, `health`, `uninstall`,
`bank`.

| Tool | What it does |
|------|--------------|
| `pos system health` | Host health dashboard (disk, RAM, backup age, fail2ban, docker) |
| `pos system backup` | gpg-encrypted (AES-256) folder snapshots |
| `pos system firewall` | Interactive UFW ("UFW POWER") management |
| `pos system uninstall` | Safe, interactive uninstaller for the pos toolkit |
| `pos system bank` | Persistent command bank — save, run, and alias shell commands |

---

## `pos system health` — host health dashboard

```bash
pos system health                 # console report; exits 1 if any check FAILs
```

Checks: disk per mount (>90% = FAIL), RAM/swap, backup age, fail2ban, docker
containers. Header shows hostname, uptime, load, public IP.

Health is a **console-only reporter — it never sends notifications**; deliver
its output with a wrapper of your own or from your own cron/timer (e.g. redirect
it to a log file).
`--help` prints the
**effective** config values (env > `system.env` > default), e.g.:

```
Environment (effective values):
  HEALTH_BACKUP_MAX_AGE_DAYS  2
  BACKUP_SERVICE_ROOTS        /srv $HOME/srv
```

(`$HOME` is resolved at runtime — on this host that is `/srv /home/unknown/srv`.)

### Configuration

```bash
# ~/.config/linux_post_install/system.env   (hand-written; exported env vars win)
BACKUP_SERVICE_ROOTS=/srv $HOME/srv    # roots for backup-age check + backup --service
BACKUP_USB_ROOT=/mnt/usb               # optional: copy finished backups to <root>/backups/ (auto-detects a mounted USB when unset)
HEALTH_BACKUP_MAX_AGE_DAYS=3           # WARN if newest backup older (default 2)
```

### Running it on a timer (your own)

pos ships no scheduler — to get the dashboard regularly, use your own
scheduling: a cron entry or a timer in your service manager, e.g.

```bash
crontab -e
# every morning at 08:00, write the report to a log file:
0 8 * * * pos system health >> ~/health.log 2>&1
```

A legacy install may still carry old `pos-health.{service,timer}` units —
`pos system uninstall` sweeps leftover pos-managed units; you can also delete
the old files under `/etc/systemd/system/` by hand.

**Recipes:**
- Watch the backup age without email: run the report each morning from your
  own cron; if the backup check turns WARN you'll see it in that morning's
  report.
- Exit code in a cron check:
  `pos system health >/dev/null 2>&1 || echo "health FAIL" >&2`.

**Troubleshooting:**
- `[WARN] fail2ban installed but not running` → expected unless you have it
  active; start it with your service manager (e.g. `sudo service fail2ban start`)
  or ignore.

---

## `pos system backup` — encrypted folder snapshots

```bash
pos system backup <folder-path>                 # encrypt to ./<name>_<date>.tar.gz.gpg
pos system backup <folder-path> --no-encrypt    # plain ./<name>_<date>.tar.gz, no password
pos system backup --service                     # pick a folder from /srv + ~/srv
```

Uses `sudo tar` + gpg AES-256. The password is prompted **twice and never
stored**; the artifact is `chmod 600`.

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
(sha256 source vs copy) before it is reported as verified:

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
- **Cron it:**
  ```bash
  30 3 * * * cd ~/backups && pos system backup --service >> ~/backups/backup.log 2>&1
  ```
  Use `--no-encrypt` (or `BACKUP_ENCRYPT=0`) for a non-interactive run.

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

Every command is **previewed and confirmed** before execution.

### Recipes
- Open SSH + a service:
  `add rule → port/service → 22/tcp`, then `8080/tcp`; finish with `enable`.
- See current rules for deletion: menu `3) Show status → numbered`.
- `--dry-run` to rehearse a rule batch safely.

**Troubleshooting:**
- "Please run as root" → you need `sudo pos system firewall`.
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
| **Tier 1** | Binaries (`/usr/local/bin/pos*`, libs, prebuilt binaries), leftover units from older installs (pos ships none itself), flag store under `/usr/local/share/linux_post_install/`, shell integration (`~/.bashrc` PATH/completion), completion file | Always (default) |
| **Tier 2** | Config files (`~/.config/linux_post_install/` — `.env` files, `authorized_keys`) | `--config` flag |
| **Tier 3** | Log/capture data (`~/.local/share/linux_post_install/` — logs, captured output) | `--data` flag |

The default mode is interactive: it shows what will be removed and asks for
confirmation. The git repo is **never** removed — delete it manually if desired.

**Recipes:**
- Quick cleanup: `pos system uninstall --yes`
- Full wipe: `pos system uninstall --yes --config --data`
- Safe preview: run `pos system uninstall` without `--yes` to see the plan first

**Troubleshooting:**
- "Nothing to remove" → pos toolkit is not installed (or already removed)
- After uninstall, run `source ~/.bashrc` or restart your shell

## `pos system bank` — persistent command bank + bash aliases

```bash
pos system bank add convert "Convert video" "ffmpeg -i {input} -crf {quality} {output}"
pos system bank list
pos system bank run convert input=clip.mp4 quality=23 output=clip.mkv
pos system bank alias convert conv    # bash alias: conv='pos system bank run convert'
pos system bank alias list
```

The bank is a persistent store of shell commands in
`~/.config/linux_post_install/bank.env` (pipe-delimited, chmod 600, managed by
the tool). `{param}` placeholders are substituted at run time; on a TTY with no
arguments the tool opens an interactive menu.

**Bash aliases** are written to `~/.bashrc` inside a managed block
(`# >>> pos bank aliases … <<<`), one line per alias:
`alias <alias_name>='pos system bank run <name>'`. Details:

- Default alias name is the bank name; pass a second argument for a shorter one:
  `pos system bank alias convert conv`.
- Reusing an alias name **retargets** it to the new bank command; removing the
  last alias removes the whole managed block.
- An alias name already defined elsewhere in `~/.bashrc` is **refused** (shown
  with its line) so the managed block never shadows your own config. Aliasing a
  command that also exists on `PATH` prints a non-blocking notice that it will
  shadow the real command in interactive shells.
- `pos system bank remove <name>` also drops aliases pointing at the removed
  command.

After adding/removing an alias, run `source ~/.bashrc` (or open a new shell)
for it to take effect.

---

## Related

- Reference: [DOC/POS.md → system](../POS.md)
- Backup roots shared with health: hand-written `system.env` ([DOC/POS.md](../POS.md))
