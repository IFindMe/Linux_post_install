# How-To: `pos share`

Share files and devices over the network: USB devices via the USB Redirector
server, filesystems via NFS and SMB/Samba. Tools: `usb`, `nfs`, `smb`.

| Tool | What it does |
|------|--------------|
| `pos share usb server` | Control `usbsrv`: share USB devices, manage clients, callbacks, nicknames |
| `pos share nfs server` | Manage the NFS kernel server (exports, enable/disable) |
| `pos share nfs client` | Mount NFS shares (ephemeral or persistent systemd units) |
| `pos share smb server` | Manage the Samba server (shares, users, enable/disable) |
| `pos share smb client` | Mount SMB/CIFS shares (ephemeral or persistent systemd units) |

---

## `pos share usb server` — USB over network

Share local USB devices over the network with the USB Redirector server.

Requires `usbsrv` (the USB Redirector server binary) — a **manual** install from
incentivespro.com, not an apt package. Point to it and it's picked up by
`command -v usbsrv`; `install.sh` copies any precompiled `x64_bin/`/`arm64_bin/`
binaries to `/usr/local/bin`.

```bash
pos share usb server --ls                # host devices + connected clients
pos share usb server --ls-shared         # only shared/in-use devices
pos share usb server --share             # interactive picker
pos share usb server --share 0-1 3       # share device 0-1 to client 3
pos share usb server --unshare 0-1       # stop sharing a device
pos share usb server --auto-share on|off # auto-share new devices
pos share usb server --callback 192.168.1.5:8080   # callback connection to a client
pos share usb server --close-callback 192.168.1.5:8080   # close it
pos share usb server --auto-connect on|off [client]      # remote auto-connect
pos share usb server --disconnect 0-1     # disconnect a device from clients
pos share usb server --disconnect all
pos share usb server --nickname 0-1 myprinter   # friendly name (empty = remove)
pos share usb server --timeout 0-1 300    # auto-unshare after inactivity (0=off)
pos share usb server --port 32032         # server TCP port (restart to apply)
pos share usb server --info               # server info
pos share usb server --version            # server version
```

Subcommands that need input (e.g. `--share`) prompt interactively when args are
omitted.

**Recipes:**
- **Attach a device and connect to one client, in one step:**
  ```bash
  pos share usb server --ls                          # note device + client IDs
  pos share usb server --share 0-1 3
  ```
- **Keep the USB printer always available:** `--auto-share on` + a nickname
  (`--nickname 0-1 printer`) so clients see a friendly name.
- **Dedicated USB-over-network box:** set `--port` once, then clients connect
  to that port.

**Interactive menu:** run `pos share usb server` with no args for a menu
(list / share / unshare / auto-share / disconnect …). The share flow lists
devices and clients from the server as pickers — no IDs to memorize; if the
server listing can't be read, it prints the raw output and falls back to
manual ID entry.

**Troubleshooting:**
- `usbsrv: command not found` → the binary isn't installed; get it from
  incentivespro.com and drop it in `x64_bin/` (or `arm64_bin/`) then re-run
  `./install.sh`, or `sudo install -m 755 usbsrv /usr/local/bin/`.
- Device shared but client can't see it → check the client connects to the
  right `host:port` (see `--info`/`--port`); verify a callback/auto-connect is
  not required for your topology.
- Nickname/timeout don't apply → `usbsrv` persists them on the server; restart
  the server after `--port` changes.

---

## `pos share nfs server` — NFS kernel server

Requires `nfs-kernel-server` (in `preinstall.sh` PACKAGES). Writes to
`/etc/exports` and reloads via `exportfs -ra`; mutating commands announce via
`notify_send`.

```bash
pos share nfs server status                    # server active? + current exports
pos share nfs server share /mnt/hdd            # export (generic, warns)
pos share nfs server share /mnt/hdd '100.64.0.0/10(rw,sync,no_subtree_check)'
pos share nfs server list                      # exportfs -v
pos share nfs server unshare /mnt/hdd          # remove the export
pos share nfs server reload                    # re-apply /etc/exports after hand edits
pos share nfs server enable                    # start + boot-persist the server
pos share nfs server disable
```

`share <path> [client]` is idempotent: an existing line for the same path is
replaced. With no client it uses `*(rw,sync,no_subtree_check)` and **warns you
to restrict it** — print the restricted form:

- Tailscale (CGNAT): `pos share nfs server share /mnt/hdd '100.64.0.0/10(rw,sync,no_subtree_check)'`
- WireGuard: `pos share nfs server share /mnt/hdd '10.10.0.0/24(rw,sync,no_subtree_check)'`
- LAN: `pos share nfs server share /mnt/backups '192.168.1.0/24(ro,sync,no_subtree_check)'`

**Recipes:**
- **Share the media drive to the tailnet:**
  ```bash
  pos share nfs server share /mnt/hdd '100.64.0.0/10(rw,sync,no_subtree_check)'
  pos share nfs server enable
  ```
- **Read-only backups to a LAN host:** use `(ro,sync,no_subtree_check)` and only
  `enable` the server where it's needed.

**Interactive menu:** run `pos share nfs server` with no args for a menu
(share / unshare / list / reload / enable / disable / status). The share flow
offers mounted folders as a picker and client-spec presets (open, WireGuard,
LAN, single IP) so you don't hand-type export specs; an inactive
`nfs-server` service or a UFW conflict is offered as a one-key fix.

**Troubleshooting:**
- "exportfs not found" → `nfs-kernel-server` isn't installed; `sudo apt install nfs-kernel-server`
- Client sees "mount.nfs: Permission denied" → your `/etc/exports` client rule
  doesn't cover the client's IP (check with `pos share nfs server list`); use
  `showmount -e <server>` on the client to see what's exported
- After editing `/etc/exports` by hand, run `pos share nfs server reload`
- NFS is blocked → allow the ports in `pos system firewall` (or `ufw`)
- Changes to `/etc/exports` are root-required → the tool uses `sudo`

---

## `pos share nfs client` — mount NFS shares

Requires `nfs-common` (in `preinstall.sh` PACKAGES).

```bash
pos share nfs client mount <server:export> <local-dir>   # one-shot (mkdir -p first)
pos share nfs client persist <server:export> <local-dir> # persistent systemd mount
pos share nfs client list                                # active NFS mounts
pos share nfs client unmount <local-dir>
pos share nfs client unpersist <local-dir>               # remove the systemd unit
```

**Persistent mounts use systemd, not fstab.** `persist` writes a
`/etc/systemd/system/<mnt-nfs-name>.mount` unit ordered after
`network-online.target`, so the share is mounted only once all interfaces are
up — a down/unreachable NFS server can't break boot (with fstab it could).
`enable --now` mounts it immediately too.

**Recipes:**
- **Mount the server's media share and keep it across reboots:**
  ```bash
  pos share nfs client persist 100.100.100.1:/mnt/hdd /mnt/nfs/media
  pos share nfs client list
  ```
- **One-off mount (no persistence):**
  `pos share nfs client mount 10.0.0.5:/srv/data /mnt/data`

**Interactive menu:** run `pos share nfs client` with no args for a menu
(mount / persist / unmount / unpersist / list). Mountpoints are offered from
existing mount-layout candidates with manual entry as fallback — the picker
also accepts the server-side export path as a "(as on server)" pick when it
differs from your local layout, and `n=new` creates a fresh directory in
place (y/N confirmed; a failure just returns to the picker). Unmount lists
the active NFS mounts as `<mountpoint> ← <source>` picks and asks for
confirmation before unmounting (with a typed fallback when nothing is
mounted); unmount and unpersist tolerate already-absent targets instead of
erroring.

**Troubleshooting:**
- "mount.nfs not found" → `nfs-common` isn't installed; `sudo apt install nfs-common`
- Mount hangs → check the server export (`pos share nfs server list` on the
  server) and that the client IP is allowed; `showmount -e <server>` lists
  exports; NFS timeouts take ~2min by default, add `timeo=50,retrans=2` via the
  unit if needed
- Persistent mount fails at boot when the server is off → intended: the unit
  waits for network-online and fails cleanly, and boot continues (unlike fstab);
  `pos share nfs client unpersist` removes it

---

## `pos share smb server` — Samba server

Requires `samba` (in `preinstall.sh` PACKAGES). Writes idempotent share blocks
to `/etc/samba/smb.conf` (between `# >>> pos-managed share: <name>` /
`# <<< end pos-managed share` markers — anything outside the markers survives),
validates with `testparm`, and hot-reloads via `smbcontrol smbd reload-config`.
Mutating commands announce via `notify_send`.

```bash
pos share smb server status                              # smbd active? + shares + users
pos share smb server share /mnt/hdd media                # share (default name: basename)
pos share smb server share /mnt/hdd media --users bob,alice   # restrict to Samba users
pos share smb server share /mnt/hdd/backups --read-only  # read-only
pos share smb server share /mnt/public --guest           # guest access (warns)
pos share smb server list                                # current shares
pos share smb server unshare media                       # remove a share
pos share smb server adduser bob                         # create a Samba user (prompts)
pos share smb server deluser bob                         # remove a Samba user
pos share smb server reload                              # validate + reload after hand edits
pos share smb server enable / disable                    # start + boot-persist smbd / stop it
```

New shares default to read-write + browsable. `--guest` and shares without
`--users` both **warn** — any Samba account (or any network user with guest)
can then access them; print the restricted form with `--users`.

SMB shares need Samba accounts, not just system users: `adduser <user>`
(prompts for the password via `smbpasswd -a`) after the system user exists.
`share --users u1,u2` checks the list against the Samba passdb and warns about
any missing account (pointing at `adduser`) — plus it walks the path's parent
dirs and warns when one lacks `other:+x` traversal (e.g. a `700` home dir
blocks Samba clients with `NT_STATUS_ACCESS_DENIED`; fix with `chmod o+x`).
Both are warnings only — the share is still written.

**Recipes:**
- **Share the media drive to the tailnet (users bob + alice):**
  ```bash
  sudo adduser bob                          # system user first
  pos share smb server adduser bob          # then a Samba password
  pos share smb server share /mnt/hdd media --users bob,alice
  pos share smb server enable
  ```
- **Public read-only download share:** `pos share smb server share /srv/pub pub --read-only --guest`
- **Change a share's access later:** re-run `share` with the same name — the
  block is replaced, not duplicated.

**Interactive menu:** run `pos share smb server` with no args for a menu
(share / unshare / list / users / reload / enable / disable / status). The
share flow offers mounted folders as a picker and walks through read-only /
guest / valid-users confirms; a UFW conflict is offered as a one-key fix.

**Troubleshooting:**
- "smbd not found" → `samba` isn't installed; `sudo apt install samba`
- Windows can't connect → check the client is in `--users` / has a Samba
  password (`adduser`), and that `smbd` is running (`status`)
- `NT_STATUS_ACCESS_DENIED` → two causes, `share` warns about both at share
  time: the user is not in the Samba passdb (`pos share smb-server adduser <user>`),
  or a parent dir of the share path lacks `other:+x` traversal (`chmod o+x <dir>`
  — typical for `700` home dirs)
- `valid users` users can't log in → their Samba password differs from the
  system one; re-run `pos share smb server adduser <user>`
- After editing `/etc/samba/smb.conf` by hand, run `pos share smb server reload`
- SMB is blocked → allow Samba in `pos system firewall` (or `ufw allow samba`)

---

## `pos share smb client` — mount SMB/CIFS shares

Requires `cifs-utils` (in `preinstall.sh` PACKAGES).

```bash
pos share smb client mount //100.100.100.1/media /mnt/smb/media        # guest
pos share smb client mount //100.100.100.1/media /mnt/smb/media bob    # prompts for password
pos share smb client persist //100.100.100.1/media /mnt/smb/media bob  # persistent (systemd)
pos share smb client list                                              # active + persistent SMB mounts
pos share smb client unmount /mnt/smb/media
pos share smb client unpersist /mnt/smb/media                          # remove the unit
```

With no user, a **guest** mount is attempted (only works if the server allows
guest access). With a user you are prompted for the Samba password: one-shot
mounts use a throwaway chmod-600 credentials file, `persist` keeps one at
`/etc/samba/credentials/<name>` (chmod 600) and references it from the unit.

**Persistent mounts use systemd, not fstab.** `persist` writes a
`/etc/systemd/system/<mnt-name>.mount` unit (**and** a matching
`<mnt-name>.automount` unit, both `systemd-escape`d) with `_netdev`: the
automount is enabled and armed, and the share is mounted **on first access**
instead of at boot, so an unreachable SMB server can never hang boot (with
fstab it could). `enable --now` arms the automount immediately.

**Recipes:**
- **Mount the server's media share and keep it across reboots:**
  ```bash
  pos share smb client persist //100.100.100.1/media /mnt/smb/media bob
  ```
- **One-off guest mount (no persistence):**
  `pos share smb client mount //10.0.0.5/pub /mnt/pub`
- **Check what a server shares before mounting:** `smbclient -L //10.0.0.5 -N`
  (or with `-U bob`)

**Troubleshooting:**
- "mount.cifs not found" → `cifs-utils` isn't installed; `sudo apt install cifs-utils`
- Mount fails with `Permission denied` / `NT_STATUS_LOGON_FAILURE` → wrong Samba
  user/password; verify the account with `pos share smb server list` on the
  server and re-run with the right user
- Mount fails with `NT_STATUS_ACCESS_DENIED` on a guest mount → the server
  share has no `guest ok`; use a user or add `--guest` on the server
- Persistent mount doesn't appear under "Active mounts" until accessed →
  intended (`x-systemd.automount`); `pos share smb client list` now also lists
  persistent units under "Persistent (automount)", so the configured shares are
  visible even before their first access

**Interactive menu:** run `pos share smb client` with no args for a menu
(enumerate / mount / persist / unmount / unpersist / list). Enter the server,
an empty user tries guest enumeration first (with an auth retry on denial),
then shares and mountpoints are offered as pickers with manual fallback —
the account you authenticated with is reused for the mount. The mountpoint
picker accepts `n=new` to create a fresh directory in place (y/N confirmed;
a failure just returns to the picker); when the server is this machine, its
underlying share directory is offered as a "(as on server)" pick too.
Unmount lists the active CIFS mounts as `<mountpoint> ← <source>` picks and
asks for confirmation before unmounting (typed fallback when nothing is
mounted).

---

## Related

- Reference: [DOC/POS.md → share](../POS.md)
