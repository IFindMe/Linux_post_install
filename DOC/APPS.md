# Optional Apps Reference

`apps/` holds 18 optional desktop application installers, one script per app in `apps/<category>/<name>.sh`. They are **not** installed by the core bootstrap — run the picker explicitly.

- [The picker — `apps/install.sh`](#the-picker--appsinstallsh)
- [How an app installer works](#how-an-app-installer-works)
- [App catalog](#app-catalog)

---

## The picker — `apps/install.sh`

**Purpose:** discover every app under `apps/` and install/uninstall the selection. Apps are auto-discovered from the directory structure — no registration step.

### Usage

```bash
bash apps/install.sh                     # interactive install selection
bash apps/install.sh --all               # install everything
bash apps/install.sh brave vscode        # install specific apps
bash apps/install.sh --uninstall         # interactive uninstall selection
bash apps/install.sh --uninstall --all   # uninstall everything
bash apps/install.sh --uninstall brave   # uninstall a specific app
```

(Also reachable via `./install.sh --apps` / `--full`.)

### How it works

1. Parses `--all`, `--uninstall`, and positional app names.
2. Scans `apps/<category>/*.sh` to build the catalog (skips non-app dirs).
3. Picks apps three ways: named on the command line (unknown names are skipped with a warning), `--all`, or an interactive y/n picker grouped by category.
4. Runs `bash apps/<category>/<name>.sh [uninstall]` for each selected app, with a progress header and an overall elapsed-time banner.

### Configuration

- Categories: `ai`, `browsers`, `development`, `media`, `networking`, `remote-access`, `system`, `utilities`.
- Adding an app = dropping `apps/<category>/<name>.sh` into the folder. See [DEV.md](DEV.md) for the required installer conventions.

---

## How an app installer works

Every app script follows the same shape:

```bash
install_<name>() { … }      # idempotent: checks command -v (or flatpak list) first
uninstall_<name>() { … }    # also idempotent; purges and removes any added repos/keys
case "${1:-}" in
    uninstall) uninstall_<name> ;;
    *) install_<name> ;;
esac
```

Installation methods used across the catalog:

| Method | Example |
|--------|---------|
| `apt` package | `sudo apt install -y obs-studio` |
| Official installer script | `curl -fsSL https://tailscale.com/install.sh \| sh` |
| Custom apt repo (added at install, removed at uninstall) | Brave, VS Code |
| `.deb` file | `curl` → `dpkg -i` → `apt-get install -f -y` |
| GitHub release archive | scrcpy (tar.gz → `/usr/local/lib/`) |
| AppImage | AFFiNE (`/opt/affine` + desktop entry) |
| Flatpak | LocalSend (`flatpak install -y flathub …`) |

---

## App catalog

| App | Category | What it is | Install method |
|-----|----------|------------|----------------|
| llama.cpp | ai | Local LLM inference server (llama-server) | GitHub release → `/usr/local/lib/llama.cpp-<tag>` + `/usr/local/bin` symlinks |
| Brave | browsers | Brave browser | apt repo + `apt install brave-browser` |
| opencode | development | AI coding agent | official script → `~/.opencode/bin` |
| VS Code | development | Code editor | Microsoft apt repo + `apt install code` |
| OBS Studio | media | Screen recording / streaming | `apt install obs-studio` |
| scrcpy | media | Android mirror/control | GitHub release (latest) → `/usr/local/lib/scrcpy-<v>` + desktop entry |
| VLC | media | Media player | `apt install vlc` |
| NetBird | networking | Mesh VPN | official script; join with `sudo netbird up --setup-key <key>` |
| Tailscale | networking | WireGuard-based VPN | official script; start with `sudo tailscale up` |
| ZeroTier | networking | Virtual LAN | official script; join with `sudo zerotier-cli join <id>` |
| Termius | remote-access | SSH client | `.deb` from termius.com |
| VNC Viewer | remote-access | VNC client (TigerVNC) | `apt install tigervnc-viewer` |
| Docker Engine | system | Container runtime | get.docker.com; adds user to `docker` group (re-login needed) |
| QEMU + KVM | system | Virtualization + virt-manager | `apt install` (qemu-system, libvirt, bridge-utils, virt-manager); adds user to `libvirt`/`kvm` groups |
| AFFiNE | utilities | Knowledge base (AppImage) | GitHub release → `/opt/affine` + desktop entry |
| btop | utilities | Resource monitor | `apt install btop` |
| LocalSend | utilities | Local file sharing | flatpak (installs flatpak + flathub if missing) |
| tsui | utilities | Tailscale config TUI (official install script from neuralink.com) | `curl \| bash` → `/usr/local/bin/tsui` |
