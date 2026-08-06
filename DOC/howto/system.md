# How-To: `pos system`

Host care: encrypted backups, firewall, and the health dashboard. Tools:
`backup`, `firewall`, `health`.

| Tool | What it does |
|------|--------------|
| `pos system health` | Host health dashboard (disk, RAM, services, backup age, fail2ban, docker) |
| `pos system backup` | gpg-encrypted (AES-256) folder snapshots |
| `pos system firewall` | Interactive UFW ("UFW POWER") management |
| `pos system nfs-server` | Manage the NFS kernel server (exports, enable/disable) |
| `pos system nfs-client` | Mount NFS shares (ephemeral or persistent systemd units) |

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

---

## `pos system nfs-server` — NFS kernel server

Requires `nfs-kernel-server` (in `preinstall.sh` PACKAGES). Writes to
`/etc/exports` and reloads via `exportfs -ra`; mutating commands announce via
`notify_send`.

```bash
pos system nfs-server status                    # server active? + current exports
pos system nfs-server share /mnt/hdd            # export (generic, warns)
pos system nfs-server share /mnt/hdd '100.64.0.0/10(rw,sync,no_subtree_check)'
pos system nfs-server list                      # exportfs -v
pos system nfs-server unshare /mnt/hdd          # remove the export
pos system nfs-server reload                    # re-apply /etc/exports after hand edits
pos system nfs-server enable                    # start + boot-persist the server
pos system nfs-server disable
```

`share <path> [client]` is idempotent: an existing line for the same path is
replaced. With no client it uses `*(rw,sync,no_subtree_check)` and **warns you
to restrict it** — print the restricted form:

- Tailscale (CGNAT): `pos system nfs-server share /mnt/hdd '100.64.0.0/10(rw,sync,no_subtree_check)'`
- WireGuard: `pos system nfs-server share /mnt/hdd '10.10.0.0/24(rw,sync,no_subtree_check)'`
- LAN: `pos system nfs-server share /mnt/backups '192.168.1.0/24(ro,sync,no_subtree_check)'`

**Recipes:**
- **Share the media drive to the tailnet:**
  ```bash
  pos system nfs-server share /mnt/hdd '100.64.0.0/10(rw,sync,no_subtree_check)'
  pos system nfs-server enable
  ```
- **Read-only backups to a LAN host:** use `(ro,sync,no_subtree_check)` and only
  `enable` the server where it's needed.

**Troubleshooting:**
- "exportfs not found" → `nfs-kernel-server` isn't installed; `sudo apt install nfs-kernel-server`
- Client sees "mount.nfs: Permission denied" → your `/etc/exports` client rule
  doesn't cover the client's IP (check with `pos system nfs-server list`); use
  `showmount -e <server>` on the client to see what's exported
- After editing `/etc/exports` by hand, run `pos system nfs-server reload`
- NFS is blocked → allow the ports in `pos system firewall` (or `ufw`)
- Changes to `/etc/exports` are root-required → the tool uses `sudo`

---

## `pos system nfs-client` — mount NFS shares

Requires `nfs-common` (in `preinstall.sh` PACKAGES).

```bash
pos system nfs-client mount <server:export> <local-dir>   # one-shot (mkdir -p first)
pos system nfs-client persist <server:export> <local-dir> # persistent systemd mount
pos system nfs-client list                                # active NFS mounts
pos system nfs-client unmount <local-dir>
pos system nfs-client unpersist <local-dir>               # remove the systemd unit
```

**Persistent mounts use systemd, not fstab.** `persist` writes a
`/etc/systemd/system/<mnt-nfs-name>.mount` unit ordered after
`network-online.target`, so the share is mounted only once all interfaces are
up — a down/unreachable NFS server can't break boot (with fstab it could).
`enable --now` mounts it immediately too.

**Recipes:**
- **Mount the server's media share and keep it across reboots:**
  ```bash
  pos system nfs-client persist 100.100.100.1:/mnt/hdd /mnt/nfs/media
  pos system nfs-client list
  ```
- **One-off mount (no persistence):**
  `pos system nfs-client mount 10.0.0.5:/srv/data /mnt/data`

**Troubleshooting:**
- "mount.nfs not found" → `nfs-common` isn't installed; `sudo apt install nfs-common`
- Mount hangs → check the server export (`pos system nfs-server list` on the
  server) and that the client IP is allowed; `showmount -e <server>` lists
  exports; NFS timeouts take ~2min by default, add `timeo=50,retrans=2` via the
  unit if needed
- Persistent mount fails at boot when the server is off → intended: the unit
  waits for network-online and fails cleanly, and boot continues (unlike fstab);
  `pos system nfs-client unpersist` removes it

---

## Related

- Reference: [DOC/POS.md → system](../POS.md)
- Notify platform config: [communication.md](communication.md)
- Backup roots shared with health: `system.env` ([DOC/POS.md](../POS.md))
