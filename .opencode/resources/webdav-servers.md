# WebDAV servers relevant to `pos share`

> Evidence basis (checked 2026-09-18, sandbox = Debian 13 trixie amd64):
> local `apt-cache policy/show/search` + `apt-cache search`, one live probe
> (`rclone serve webdav --help` on installed rclone 1.60.1), Debian
> packages.debian.org name search + apache2-bin filelist (fetched via curl),
> PyPI JSON for WsgiDAV, dufs upstream GitHub title. Ubuntu-side apt status
> is **UNVERIFIED** (packages.ubuntu.com unreachable from sandbox — TLS
> connection reset); anything Ubuntu-only must be re-checked in task 03/04.
> No claim below contradicts `apt` reality on trixie.

## Protocol minimum a server must satisfy

WebDAV is an HTTP/1.1 extension (RFC 4918 — core spec; RFC 3253 DeltaV
versioning is out of scope for file sharing). For a `pos share`-style folder
export the methods that matter are: `OPTIONS`, `PROPFIND`, `GET`/`PUT`/
`DELETE`, `MKCOL`, `COPY`, `MOVE`, and `LOCK`/`UNLOCK`. Compliance classes:
Class 1 = basic WebDAV; Class 2 = Class 1 + locking. Locking matters because
filesystem clients (`davfs2`, GNOME `gio`, MS Office) expect it — a server
without lock support still works for simple GET/PUT but can break
concurrent-edit clients. (Spec facts from RFC 4918; class/client
interactions are standard knowledge — flag as background, not apt evidence.)

## Option matrix (Debian trixie `apt` reality)

| Server | Install path | apt evidence | Notes for `pos share` |
|---|---|---|---|
| Apache `mod_dav` | `apache2` (no extra package) | `apt-cache policy apache2` → candidate 2.4.68-1~deb13u1; `apt-cache search libapache2-mod` shows **no** dav module package; packages.debian.org `apache2-bin` filelist (trixie/amd64) contains `mod_dav.so`, `mod_dav_fs.so`, `mod_dav_lock.so` | Full Class 2 (locking via `mod_dav_lock`), per-directory `Dav On`, Basic/Digest auth, TLS via existing cert story. Heaviest option; config = Apache vhost snippet. Docs: https://httpd.apache.org/docs/2.4/mod/mod_dav.html |
| nginx WebDAV | `nginx-full` (or `nginx-extras`) + `libnginx-mod-http-dav-ext` | `apt-cache policy libnginx-mod-http-dav-ext` → 1:3.0.0-6; `apt-cache show nginx-full` lists WebDAV under OPTIONAL HTTP MODULES and `Depends:` includes `libnginx-mod-http-dav-ext`; package description: "complements the Nginx WebDAV module… provides the missing PROPFIND & OPTIONS methods" | Stock `ngx_http_dav_module` alone is write-only subset (PUT/DELETE/MKCOL/COPY/MOVE, no PROPFIND) — the `-dav-ext` module is **required** for a usable share. Lock support is limited vs Apache. Docs: https://nginx.org/en/docs/http/ngx_http_dav_module.html, https://github.com/arut/nginx-dav-ext-module |
| `rclone serve webdav` | `rclone` — **already in `preinstall.sh` `PACKAGES`** (line 39) | `apt-cache policy rclone` → 1.60.1+dfsg-4 (also installed in sandbox); live probe `rclone serve webdav --help` confirms the subcommand + `--addr` server options | Zero new apt deps; serves any path over HTTP immediately; `--user/--pass` Basic auth, TLS via `--cert/--key`. Single-process, no system config file — closest to "share this folder now" UX. Upstream docs: https://rclone.org/commands/rclone_serve_webdav/ |
| `wsgidav` | **NOT in trixie apt** — PyPI-only | `apt-cache search wsgidav` → empty; packages.debian.org name search (trixie) → "Sorry, your search gave no results"; PyPI `WsgiDAV` JSON confirms it exists upstream (Production/Stable, MIT) | Per `AGENTS.md` tool rules, a pip package is a *manual installer*: it must NOT go in `PACKAGES`, the tool must guard for it (`command -v wsgidav || err …` before help). Adds a Python/pip runtime dependency — heavier bootstrap contract than the `rclone` path. Upstream: https://wsgidav.readthedocs.io/ |
| `dufs` | **NOT in trixie apt** — single static binary from upstream releases | `apt-cache search dufs` → no package; packages.debian.org name search (trixie) → "Sorry, your search gave no results"; upstream GitHub title confirms identity: "sigoden/dufs: A file server that supports static serving, uploading, searching, accessing control, webdav…" | Same `PACKAGES` problem as `wsgidav` (manual download → guard-inside-tool, never `PACKAGES`), plus a curl-|-install supply-chain story the repo otherwise avoids (only `yt-dlp` precedent in `preinstall.sh:65-68`). Lightweight at runtime (one binary, WebDAV + auth + TLS flags). Upstream: https://github.com/sigoden/dufs |

## `PACKAGES`-convention consequence (`preinstall.sh:28-43`)

- `apache2` / `nginx-full` / `libnginx-mod-http-dav-ext` / `davfs2` are all
  real apt packages → eligible for `PACKAGES` if task 03 picks them.
- `wsgidav` (pip) and `dufs` (release binary) are NOT apt packages → per
  `AGENTS.md`, they must be guarded inside the tool, never added to
  `PACKAGES`. This is a fact about repo convention, not a server ranking.

## Share-suite pattern fit (from `bin/pos-share-nfs-server`, `bin/pos-share-smb-server`, `lib/share-lib.sh`)

Any future WebDAV server tool inherits this pattern language (facts observed
in the two server tools; reuse keeps `make lint` and UX consistent):

- Dep guard **before** `-h|--help` (`command -v exportfs … || err`, smb-server:10-13).
- Env-seam config path (`EXPORTS_FILE="${EXPORTS_FILE:-/etc/exports}"`, `SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"`) — a WebDAV tool needs the same seam for its vhost/conf path.
- `systemctl enable --now <unit>` for enable; `share_service_active` probe + `share_offer_fix` advisory (never abort the share op).
- `share_ufw_blocks_ports '<ports>'` advisory (NFS: `2049|111`; SMB: 139/445) — WebDAV equivalent is 80/443 or the chosen `--addr` port.
- Validate-before-reload (`testparm -s` in smb-server:97-105) — Apache has `apache2ctl configtest`, nginx has `nginx -t`; `rclone` needs none (no config file).
- `# >>> pos-managed share:` markers for idempotent edits (smb-server:215-226); `share_folder_candidates` for the interactive folder picker.
- Tailscale client preset (`100.64.0.0/10`, nfs-server:35,173) — WebDAV access control has an equivalent decision (see `webdav-clients-auth.md`).

## Explicitly NOT decided here

Server choice, tool filename(s), and UX shape belong to task 03
(`.tasks/webdav-share/03-webdav-design.md`). This doc is comparison facts only.
