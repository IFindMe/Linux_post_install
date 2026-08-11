# How-To: `pos share`

Share files and devices over the network: USB devices via the USB Redirector
server, filesystems via NFS (SMB planned). Tools: `usb`, `nfs`.

| Tool | What it does |
|------|--------------|
| `pos share usb server` | Control `usbsrv`: share USB devices, manage clients, callbacks, nicknames |
| `pos share nfs server` | Manage the NFS kernel server (exports, enable/disable) |
| `pos share nfs client` | Mount NFS shares (ephemeral or persistent systemd units) |

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

## Related

- Reference: [DOC/POS.md → share](../POS.md)
