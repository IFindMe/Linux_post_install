# Builder Report — share clients: mountpoint picker enhancements + unmount-by-pick

## TL;DR
- Status: IN PROGRESS
- Files to change: `bin/pos-share-nfs-client`, `bin/pos-share-smb-client`, `DOC/howto/share.md`
- Features: (A) mountpoint picker gains same-as-server synthetic candidate + `n=new` create-dir flow; (B) interactive unmount becomes pick-from-active-mounts with y/N confirm, typed fallback when none.
- Verification: bash -n ×2 · `make gen` idempotent · `make check` · `make lint` (0 FAIL, 0 WARN) · pty probes A1–A3, B1–B3 incl. zero-mutation proof.

## Step 1: Context read + design lock
[DONE]
- Read survey report (Pattern B contracts), `lib/share-lib.sh`, `lib/menu-lib.sh`, both clients, smb-server consumption (:378–408), common.sh helpers (`confirm` default-deny, `run` dry-run-aware non-exiting).
- Constraint conflict resolved: `share_pick` treats `n` as a filter string and owns its read loop; lib is off-limits → each client gets a local `pick_mountpoint` port of `menu_pick` with exactly two deltas: hint line `[1-N], n=new, text=filter, 0=back` and an `n|N` case delegating to a new-dir flow (success → created dir echoed as chosen value; failure/decline/EOF → redraw picker). Numbered picks / filter / `0=back` rendering byte-identical.
- Feature B interpretation: "interactive path" = menu item 4 (`menu_unmount`, reached via no-args+tty front door). Bare CLI verb dispatch (`unmount <dir>` required arg) untouched → scripted behavior byte-identical (B3).

## Step 2: nfs-client — Feature A (picker capabilities)
[DONE]
- Added `pick_mountpoint` (local menu_pick port; deltas: hint `[1-N], n=new, text=filter, 0=back`, `n|N` → new-dir flow) and `ask_new_mountpoint` (validate absolute + no trailing slash + system-path parity guard, `confirm` y/N naming full path, `run sudo mkdir -p`; any failure/decline/EOF = warn + rc 1 → picker redraws, tool never aborts).
- `menu_ask_mountpoint` now takes optional `[server_path]`: strips annotations from candidates for the membership test (`grep -qxF` on bare paths), appends synthetic `<path>   (as on server)` only when absent. Fallback to manual typed prompt preserved byte-identically (incl. cancel→manual-entry fall-through).
- `menu_mount` passes `${what#*:}` (server-side export path) into the picker for both ephemeral and persist modes.
- bash -n OK.

## Step 3: smb-client — Feature A (picker capabilities + server-path resolution)
[DONE]
- Same `pick_mountpoint` / `ask_new_mountpoint` / `menu_ask_mountpoint(server_path)` trio as nfs-client.
- Added `smb_server_path <host> <share>`: resolves the underlying dir ONLY when the target host is this machine (localhost/loopbacks/hostname/`hostname -f`/`hostname -I`), via `testparm -s --parameter-name=path --section-name=<share> "$SMB_CONF"`; anything else → rc 1 → suggestion silently skipped (remote SMB paths are not remotely discoverable). Invocation verified empirically on this box (`print$` → `/var/lib/samba/printers`, unknown share rc 1). NOTE: bare-share-name positional is WRONG (testparm treats it as a config file); `--section-name` is required. New `SMB_CONF="${SMB_CONF:-/etc/samba/smb.conf}"` env seam matches smb-server's constant.
- `menu_mount` resolves after share pick and passes the result into `menu_ask_mountpoint`.
- bash -n OK.

## Step 4: nfs-client — Feature B (unmount by pick)
[DONE]
- `menu_unmount` rewritten: enumerates via `findmnt -rn -o TARGET,SOURCE -t nfs,nfs4` (same source as `cmd_list`'s view, reduced to TARGET|SOURCE rows via the house `$NF` awk split, cf. share-lib's candidates parser).
- Zero mounts → `log "No active NFS mounts"` + existing manual typed prompt fallback. One+ → `share_pick` over `<mountpoint>  ← <source>` entries, then default-deny `confirm "Unmount <mp> (from <src>)?" n`; decline/EOF → `[+] Cancelled` + rc 1, zero umount issued.
- Deliberate correction inside the rewritten enumeration: old code ran `findmnt -r -n … | tail -n +2`, but `-n` already suppresses the header — so `tail` dropped the FIRST active mount from the picker. Verified empirically (`findmnt -rn -o TARGET -t tmpfs` prints data rows only). Keeping the tail would contradict "enumerate using the same source as list".
- Scripted path untouched: dispatch still requires an explicit `<local-dir>` arg for the `unmount` verb; `cmd_unmount` unchanged.
- bash -n OK.

## Step 5: smb-client — Feature B (unmount by pick)
[DONE]
- Mirror of Step 4 against the cifs source: `findmnt -rn -o TARGET,SOURCE -t cifs`, items `<mountpoint>  ← <source>`, confirm-gated, `[+] Cancelled` on decline, typed fallback when none ("No active SMB mounts").
- Replaces the old `${row##* }` last-field parse of `findmnt -rnf -t cifs -o SOURCE,TARGET`.
- bash -n OK ×2.

## Step 6: DOC/howto/share.md hints
[DONE]
- NFS + SMB "Interactive menu" paragraphs now mention: `n=new` create-dir (y/N confirmed, failure returns to picker), the "(as on server)" pick (SMB: only when this machine is the server), and unmount-by-pick `<mountpoint> ← <source>` with confirmation + typed fallback. Pre-existing tolerance sentence preserved.

## Step 7: Gates
[DONE]
- `bash -n` ×2 → OK.
- `make gen` twice → byte-identical outputs (GEN-IDEMPOTENT); `DOC/AGENT_Context_Project.md` drift = exactly the two filetable line-count rows (343→467, 576→726), no header changes.
- `make check` → `check-sync: OK`.
- `make lint` → `0 FAIL, 0 WARN (convention lint)`.

## Step 8: Bug found by own probe — display lines swallowed under $( )
[DONE]
- First pty probe round exposed that `ask_new_mountpoint`'s warn/log lines were invisible: it runs inside `made="$(ask_new_mountpoint)"`, so stdout-captured substitution ate them. Fixed by sending all display lines to stderr (`>&2`), matching menu-lib's "display → stderr, result → stdout" contract. Gates re-run green after the fix.

## Step 9: pty probes (throwaway env /tmp/opencode/share-probe, cleaned)
[DONE]
- Harness: PATH-shimmed `findmnt`/`showmount`/`sudo`/`mount.nfs`/`mount.cifs`/`smbclient`; fixture-driven; `sudo` shim logs every call and EXECUTES ONLY `mkdir` targets inside the probe root — zero mutation guaranteed outside it; real pty via `script(1)`; SMB port-probe satisfied via the tool's `SMB_PORT=18445` env seam against a throwaway listener.
- **A1/A3** — nfs synthetic appears when absent (`-- 1 of 8 match 'as on' --` → picked → `Mounted 100.100.100.1:/exports/media at /exports/media`); absent when already listed (7 items, no suggestion); smb resolution via testparm works end-to-end (`/tmp/…/mp/serveronly   (as on server)` suggested for share `datashare`) and is silently skipped when the underlying dir is already a candidate (share `testshare`). Filter still works incl. matching the synthetic item.
- **A2** — `n`+path+`y` → dir really created inside probe root + `Created mount point …` + mount completes; decline (Enter=N) → no dir, picker redraws, `0=back` → manual typed prompt preserved; relative path → warned, back at picker; mkdir failure in read-only prefix → `Could not create …` warning + stays in picker (then recovers by creating a good dir); EOF at path prompt → straight back to picker. Picker hint renders exactly `Mountpoint [1-N], n=new, text=filter, 0=back`. All flows exit rc 0.
- **B1** — nfs + smb: 2 active mounts rendered as `<mountpoint>  ← <source>`; confirm names both; decline → `[+] Cancelled` with **zero umount calls logged** (zero-mutation proof from shim log); happy path issues exactly one umount.
- **B2** — empty list → `[+] No active NFS mounts` / `[+] No active SMB mounts` + existing typed prompt fallback; typed target handled idempotently ("not mounted as NFS — nothing to do").
- **B3** — scripted `unmount <dir>` HEAD vs worktree: stdout+stderr byte-identical and identical rc 0 for both tools.
- Excerpt (B1a, decline path):
  ```
  -- 2 available --
    1) /mnt/nfs/media  ← 100.100.100.1:/exports/media
    2) /mnt/nfs/data  ← 100.100.100.1:/exports/data
  Unmount which NFS mount? [1-2], text=filter, 0=back 1
  Unmount /mnt/nfs/media (from 100.100.100.1:/exports/media)? [y/N]:
  [+] Cancelled
  ```
- Harness lessons (not product bugs): HEAD copies must sit beside a `lib/` mirror for their dirname-based sourcing; literal `"[+] "` assertions need ANSI stripping; smb `probe_server` hard-exits (no try-anyway) so the port seam was required.

## Per-tool diff summary
- `bin/pos-share-nfs-client` (+~120/−~18): `pick_mountpoint`, `ask_new_mountpoint`, `menu_ask_mountpoint[server_path]` w/ `(as on server)` synthesis, `menu_mount` passes `${what#*:}`, `menu_unmount` rewritten (list-view enumeration, `<mp>  ← <src>` picks, confirm-gate, typed fallback).
- `bin/pos-share-smb-client` (+~170/−~18): same trio + `smb_server_path` (testparm via new `SMB_CONF` env seam, self-host-only) + `menu_mount` wiring + mirrored `menu_unmount`.
- `DOC/howto/share.md`: NFS + SMB interactive-menu paragraphs updated (n=new, as-on-server, unmount-by-pick).
- `DOC/AGENT_Context_Project.md`: GEN line-count rows only (343→467, 576→726).

## Scope compliance
- Only the four allowed files touched (2 tools + howto + GEN regen). lib/, servers, usb-server, dispatch tables, INTERACTIVE_CMDS untouched. No commits made.

REPORT_PATH: ./reportAgents/2026-08-23-builder-share-clients-picker-unmount.md

