# How-To: `pos network`

Networking day-to-day: IP/diagnostic info, Wi-Fi hotspots, host discovery, port
checks, and the aria2 download daemon. Tools: `ip`, `hotspot`, `scan`,
`checkport`, `download`.

| Tool | What it does |
|------|--------------|
| `pos network ip` | Interfaces, default route, public IP + location |
| `pos network hotspot` | Wi-Fi AP via `create_ap` / `wihotspot-gui` |
| `pos network scan` | Two-phase host discovery with `nmap` |
| `pos network checkport` | Is a TCP port open on a host? |
| `pos network download` | aria2 download daemon + queue control (add/torrent/metalink, watch, limits) |

---

## `pos network ip` — where am I, what's my IP

```bash
pos network ip
```

Shows local interfaces + addresses, the default route, and your public IP with
its geolocation. Useful before `ssh`-ing home or opening ports.

**Recipe:** public IP on the go — this is the same value the health digest
includes, so if your home IP changed you'll see it in the 08:00 report.

**Troubleshooting:** the public-IP lookup needs outbound HTTPS; if it prints
"unreachable"/location unknown, your network or a firewall is blocking
`api.ipify.org` / the geo provider.

---

## `pos network hotspot` — turn the machine into a Wi-Fi AP

Requires the precompiled `create_ap` + `wihotspot-gui` binaries shipped in
`x64_bin/` (or `arm64_bin/`) and installed to `/usr/local/bin` by `install.sh`.
The GUI needs a desktop session; the CLI needs a wireless NIC in AP mode.

```bash
pos network hotspot                       # launch the wihotspot-gui
pos network hotspot start wlan0 eth0 MyNet mypass      # AP on wlan0, internet via eth0
pos network hotspot start --foreground wlan0 eth0 MyNet mypass   # block until Ctrl+C
pos network hotspot stop                  # stop the running AP (auto-detected)
pos network hotspot stop wlan0            # stop by interface/PID
pos network hotspot status                # list running APs
```

Positional args: `<wifi-iface> [<internet-iface>] <ssid> [<passphrase>]`.
Without `--foreground`, it asks whether to run in the background; daemonized APs
log to `/var/log/linux_post_install_hotspot.log`.

**Recipes:**
- Give guests internet while tethered: `pos network hotspot start wlan0 eth0 GuestNet secret`.
- After starting, find who joined with `pos network scan 192.168.42.0/24` (create_ap
  default subnet) or `pos network checkport <phone-ip>:80`.

**Troubleshooting:**
- `create_ap` not found → the precompiled binary wasn't installed; re-run
  `./install.sh` (Phase 2 copies `x64_bin/` → `/usr/local/bin`).
- "No suitable AP mode" → your Wi-Fi card/driver doesn't support AP mode; use the
  GUI (wihotspot-gui) or a USB dongle.
- Client has IP but no internet → check the `<internet-iface>` arg / NAT
  forwarding; `create_ap --daemon` logs to the hotspot logfile.

---

## `pos network scan` — find hosts on the LAN

Requires `nmap` (`sudo apt install nmap`).

```bash
pos network scan 192.168.1.0/24          # fast discovery
pos network scan 10.0.0.0/28 --full      # + OS, ports, services, NSE scripts
pos network scan 172.1.1.104             # single host
pos network scan 192.168.1.0/24 --retries 3
```

Two phases: fast ping-sweep discovery, then — only with `--full` — a detailed
metadata scan on the alive hosts.

**Recipe:** after `pos network hotspot start`, find attached clients:
`pos network scan 192.168.42.0/24`.

**Troubleshooting:** `nmap` missing → install it. Scanning a remote/hostile
network without permission is not advisable; `--full` is slow — scope it to a
`/24` or a single host.

---

## `pos network checkport` — is a port open?

```bash
pos network checkport 192.168.1.1:80
pos network checkport 10.0.0.5:443
```

Exits non-zero if the port is closed/unreachable, so you can chain it:

**Recipe:** confirm a self-hosted service is up before alerting:
```bash
pos network checkport jellyfin.local:8096 && notify_send "Jellyfin reachable" \
  || notify_send "Jellyfin DOWN"
```
(see [communication](communication.md) for `notify_send`).

**Troubleshooting:** a "closed" answer from a host that *is* up usually means a
local firewall — check `sudo pos system firewall` rules and service binds
(`ss -tlnp`).

---

## `pos network download` — aria2 download daemon + queue

Runs a persistent `aria2c` JSON-RPC daemon as a systemd **user** service
(`pos-aria2.service`, enabled via `systemctl --user enable --now`; a linger
warning is printed when no session is active, so the daemon survives logout).
The RPC secret lives in `~/.config/linux_post_install/download.env` (chmod 600).
Downloads land in `~/Downloads` by default.

```bash
# enqueue one or many files (auto-starts the daemon if needed)
pos network download add https://example.com/ubuntu.iso
pos network download add https://example.com/a.bin https://example.com/b.bin --dir /mnt/hdd/dl

# torrents / magnets — keep seeding with --seed (default: stop at 100%)
pos network download torrent debian.torrent --seed
pos network download torrent "magnet:?xt=urn:btih:…"

# watch progress live (Ctrl+C detaches); with a GID it exits when that one finishes
pos network download watch
pos network download watch a1b2c3d4e5f60718

# the queue
pos network download list
pos network download pause a1b2c3d4e5f60718     # resume / remove work the same
pos network download remove --force all          # kill everything immediately
pos network download limit 2M                    # global speed cap (0 = unlimited)
pos network download move a1b2c3d4e5f60718 0     # jump to the front of the queue
```

**Recipe:** grab a big ISO in the background and keep an eye on it from a
terminal:

```bash
pos network download add https://example.com/ubuntu.iso --tmux
tmux attach -t dl-ubuntu.iso      # live progress; session closes itself when done
```

`--tmux` opens a detached `dl-<name>` session running `watch <gid>` (name from
`--out` or the URL basename, sanitized; `-2` suffix on collision).

**Troubleshooting:** "RPC failed — is the daemon running?" → `pos network
download status`; if the unit failed, check the journal with
`journalctl --user -u pos-aria2 -n 50`. Seed/limit knobs live on `add`/`torrent`
(`--seed`, `--split`) and on `limit`/`set` for the running queue.

**Recipe: survive a long internet outage.** A download that fails while the
internet is down is stopped with `error` status — the retry machinery brings it
back without you:

```bash
pos network download add https://example.com/big.iso   # arms the retry healer
# ...router dies for 3 hours; big.iso sits in STOPPED/error...
pos network download retry all          # waits for connectivity, re-queues, verifies
pos network download watch 2e9dffc4     # or: watch a live one — auto-restarts when back
```

The healer timer (`pos-aria2-retry.timer`) already runs `retry all` every 2 min
on its own once a download started, so no shell is needed on headless boxes.
`retry <gid>` for one download; sources that fail with a *real* 404/410 are
remembered in `~/.config/linux_post_install/download.retry` and skipped by
`retry all` — `pos network download restart <gid>` re-queues them by hand.

---

## Related

- Reference tables: [DOC/POS.md → network](../POS.md)
- Firewall that may block these: [system.md](system.md)
- Public IP in the daily digest: [system.md → health](system.md)
