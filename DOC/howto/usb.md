# How-To: `pos usb`

Share USB devices over the network with the USB Redirector server. Tool:
`server`.

| Tool | What it does |
|------|--------------|
| `pos usb server` | Control `usbsrv`: share devices, manage clients, callbacks, nicknames |

Requires `usbsrv` (the USB Redirector server binary) — a **manual** install from
incentivespro.com, not an apt package. Point to it and it's picked up by
`command -v usbsrv`; `install.sh` copies any precompiled `x64_bin/`/`arm64_bin/`
binaries to `/usr/local/bin`.

---

## `pos usb server` — share + manage

```bash
pos usb server --ls                # host devices + connected clients
pos usb server --ls-shared         # only shared/in-use devices
pos usb server --share             # interactive picker
pos usb server --share 0-1 3       # share device 0-1 to client 3
pos usb server --unshare 0-1       # stop sharing a device
pos usb server --auto-share on|off # auto-share new devices
pos usb server --callback 192.168.1.5:8080   # callback connection to a client
pos usb server --close-callback 192.168.1.5:8080   # close it
pos usb server --auto-connect on|off [client]      # remote auto-connect
pos usb server --disconnect 0-1     # disconnect a device from clients
pos usb server --disconnect all
pos usb server --nickname 0-1 myprinter   # friendly name (empty = remove)
pos usb server --timeout 0-1 300    # auto-unshare after inactivity (0=off)
pos usb server --port 32032         # server TCP port (restart to apply)
pos usb server --info               # server info
pos usb server --version            # server version
```

Subcommands that need input (e.g. `--share`) prompt interactively when args are
omitted.

**Recipes:**
- **Attach a device and connect to one client, in one step:**
  ```bash
  pos usb server --ls                          # note device + client IDs
  pos usb server --share 0-1 3
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

## Related

- Reference + full flag table: [DOC/POS.md → usb](../POS.md)
