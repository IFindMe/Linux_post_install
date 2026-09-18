# WebDAV clients, auth/TLS, and Tailscale-LAN relevance for `pos share`

> Evidence basis (checked 2026-09-18, sandbox = Debian 13 trixie amd64):
> local `apt-cache policy/show/search` as cited per row; `gvfs-backends`
> package description (backend list + `protocol::webdav` tag); `rclone` 1.60.1
> installed in sandbox. Ubuntu-side apt status is **UNVERIFIED**
> (packages.ubuntu.com unreachable from sandbox). Auth/TLS mechanism claims
> cite upstream docs URLs; Tailscale trust argument cites the repo's own
> NFS tool precedent (`bin/pos-share-nfs-server:35,81,173`).

## Client mount options (Debian trixie `apt` reality)

| Client | Install path | apt evidence | Use in `pos share` context |
|---|---|---|---|
| `davfs2` (`mount.davfs`) | `davfs2` | `apt-cache policy davfs2` → 1.7.1-1; `apt-cache show davfs2`: "mount a WebDAV resource as a regular file system… fully integrate into the filesystem semantics (mount, umount…)" | The Linux filesystem mount path (`mount -t davfs`). Needs credential handling (`/etc/davfs2/secrets` or `~/.davfs2/secrets`, chmod 600) and the `allow_other`/fstab story for non-root mounts — a future `pos share webdav-client` tool would wrap exactly this. Upstream: https://github.com/alisarctl/davfs2 |
| `gio` (GNOME virtual fs) | `gvfs-backends` | `apt-cache policy gvfs-backends` → 1.57.2-2+deb13u1; description lists the `dav` backend and carries the `protocol::webdav` tag | `gio mount dav://host/share` — no fstab, per-user, desktop-oriented. Relevant for GNOME clients; headless servers use `davfs2` instead. Docs: https://wiki.gnome.org/Projects/gvfs |
| `rclone` (as client) | `rclone` (already in `preinstall.sh` `PACKAGES`) | Installed 1.60.1 in sandbox; backend type `webdav` is standard rclone functionality (serve-side probed live; client backend per upstream docs) | Zero-extra-dep client for scripts/tests (`rclone ls :webdav:` / remote type `webdav`). Useful as the smoke-test client in `tests/t-*.sh` without touching fstab. Docs: https://rclone.org/webdav/ |
| `cadaver` (CLI) | `cadaver` | `apt-cache policy cadaver` → 0.26+dfsg-2 | Interactive CLI for manual verification (`cadaver http://host/share`); good for docs examples, not for mounting. |
| `hdav` | `hdav` | `apt-cache policy hdav` → 1.3.4-4+b2 | Second CLI client in apt; niche — listed for completeness, no `pos share` role proposed. |
| `davix` tools | `davix` | Present in `apt-cache search webdav` output (`davix`, `libdavix0t64`) | HTTP/WebDAV CLI toolkit; niche — listed for completeness only. |

## Auth considerations

- **HTTP Basic** is the universal WebDAV auth (every server above + every
  client above speaks it). It is base64, not encryption — safe only over TLS
  or over an already-encrypted transport (Tailscale, see below). Evidence:
  `rclone serve webdav --help` documents `--user/--pass`; Apache `mod_dav`
  pairs with standard `AuthType Basic` + htpasswd (upstream:
  https://httpd.apache.org/docs/2.4/mod/mod_auth_basic.html).
- **Digest** (Apache `mod_auth_digest`) avoids cleartext-equivalent passwords
  on the wire but is Apache-only in our matrix and weaker than Basic+TLS.
  Only relevant if task 03 picks Apache for a non-TLS LAN.
- **Secrets discipline** (repo rule, `AGENTS.md` Module quirks): runtime
  credentials live in `~/.config/linux_post_install/<tool>.env` (chmod 600,
  env-var precedence), tokens masked in output, never committed. A WebDAV
  tool storing `--pass`/htpasswd entries must follow this; `davfs2` secrets
  files must be chmod 600 (its documented requirement).
- **Dep-guard + help rule** (`AGENTS.md`): any client binary the tool shells
  out to (`mount.davfs`, `gio`, `rclone`, `cadaver`) needs
  `command -v <bin> || err …` **before** the `-h|--help` case.

## TLS considerations

- **Public or untrusted LAN exposure → TLS is mandatory** with Basic auth
  (background fact, RFC 4918 §D.3 discusses security; not apt evidence).
- Termination points per server: Apache (`SSLEngine` + cert files), nginx
  (`ssl_certificate`), `rclone serve webdav` (`--cert/--key` flags per
  `--help` output), `dufs` (`--tls-cert/--tls-key` per upstream — UNVERIFIED
  locally, no binary in sandbox).
- Homelab cert story is an open point for task 03 (self-signed + Tailscale
  certs vs LAN CA); this doc only notes the per-server knobs exist.

## Tailscale-LAN relevance (why WebDAV fits `pos share`)

- The share suite already treats the Tailscale CGNAT range `100.64.0.0/10` as
  the trusted-client preset (`bin/pos-share-nfs-server:35,81,173`; smb-client
  checks `tailscale status`). Tailscale links are WireGuard-encrypted, so
  **plain-HTTP WebDAV inside 100.64.0.0/10 inherits transport encryption** —
  the same trust argument under which the NFS tool ships a Tailscale preset.
  (Trust inference from repo precedent + Tailscale's documented WireGuard
  transport: https://tailscale.com/blog/how-tailscale-works — the repo
  precedent is the evidence; the crypto property is upstream's claim.)
- Practical consequences for task 03: (a) a WebDAV tool can offer a
  Tailscale-scope preset (bind/limit to 100.64.0.0/10 or serve plain HTTP
  documented as Tailscale-only) mirroring the NFS menu presets; (b) outside
  Tailscale (raw LAN / internet), the tool must push auth + TLS, same as the
  SMB tool pushes `--users` over `--guest` (smb-server:193-197); (c) the
  firewall advisory pattern applies: `share_ufw_blocks_ports` with the
  WebDAV port (80/443 or custom `--addr` port), mirroring nfs-server:102-105
  and smb-server:199-202.
- Port note: WebDAV over standard 80/443 collides with any existing web
  server on the box — a custom high port (e.g. rclone `--addr :8080`-style)
  avoids the collision; exact choice belongs to task 03.

## What remains UNVERIFIED (for task 03/04 to close)

- Ubuntu (`noble`) package names/versions for everything above
  (packages.ubuntu.com unreachable during research).
- `dufs` TLS/auth flag names (no binary in sandbox; upstream README only).
- Whether `nginx-light` (vs `-full`/`-extras`) includes `ngx_http_dav_module`
  (only `nginx-full`'s description was inspected).
