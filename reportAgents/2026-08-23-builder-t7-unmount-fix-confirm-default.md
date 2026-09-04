# Builder — T7: unmount silent-death fixes + confirm() Enter-defaults convention

## TL;DR
- Status: IMPLEMENTED
- Item 1: smb `cmd_unmount` no longer `exit 0`s the session — persisted-automount guidance added; lazy-unmount branch `exit 0`→`return 0`; menu handler invocations normalized `|| true` in BOTH clients (approach: call-site normalization, handler rc contracts preserved); nfs typed-unmount now mirrors persisted-unit guidance. All pty probes: session survives, rc clean.
- Item 2: `confirm()` rewritten — Enter accepts displayed default (`y` omitted), explicit y/n override, EOF+invalid deny fail-closed (`yn=""` init kills any set -u exposure), display derived case-insensitively from default arg (fixes latent `"Y"` bug found at pos-docker-compose:214). 26 call sites audited — zero behavior regressions at destructive sites.
- Files changed: bin/pos-share-smb-client · bin/pos-share-nfs-client · lib/common.sh · DOC/DEV.md
- Gates: bash -n ×3 ✅ · make gen idempotent ✅ (line-count rows updated) · make check OK ✅ · make lint **0 FAIL, 0 WARN** ✅

## Step 0: Read-in + pre-edit baseline capture [DONE]
- Inputs read: detective report (full fix list), both clients, lib/common.sh, lib/share-lib.sh, lib/menu-lib.sh, DEV.md sections.
- Baseline facts established by probe (pre-edit), correcting two brief assumptions honestly:
  - "Enter denies regardless of default" is NOT true today for omitted/y defaults — Enter already accepts those (`[[ -z "$yn" || … ]]`). The directive's target semantics were partially in place; the real defects were:
    a) **EOF fails OPEN**: y-default sites accept on EOF (`read` assigns empty → `-z` → accept). n-default sites deny. Verified bash 5.2: `read` at EOF *assigns empty string* (var becomes set-but-empty) — the reviewer-noted unbound `$yn` did not reproduce here, but `yn=""` init + explicit EOF-deny makes it portable and closes the worse fail-open hole.
    b) **Uppercase `"Y"` default broken** (`[ "$default" = "y" ]` is case-sensitive): falls into the n-branch — displays `[y/N]` and Enter denies. Live site: pos-docker-compose:214 `confirm "Edit .env before starting?" Y`.
  - Silent-death reproductions (stubbed env, pty): typed unmount of idle-persisted share → `[+] Nothing mounted…`, session killed rc 0, umount never attempted; cancel/EOF at typed prompt → zero bytes, rc 1.

## Step 1: lib/common.sh confirm() rewrite [DONE]
`lib/common.sh:119-141`. Semantics: `confirm <prompt> [default]` — Enter accepts displayed default (`y` when omitted); `[Yy]`→accept, `[Nn]`→deny, invalid input→deny, EOF/closed stdin→deny via `read` rc check (fail-closed, rc-safe). Display derived case-insensitively: `[Y/n]` iff `${default,,}` = y else `[y/N]`. Probe matrix (e/f): all 11 cases pass incl. `"Y"`→Enter YES + `[Y/n]` display, destructive-n Enter→DENIED.

## Step 2: smb-client unmount fixes [DONE]
- New helper `persisted_smb_at()` (after `mounted_src`): scans `${UNIT_DIR}/*.mount` for `Type=cifs` + `Where=` == path (robust to escape drift vs systemd-escape derivation), sets `PERSISTED_UNIT`.
- `cmd_unmount`: `-z "$src"` branch → guidance when persisted (`[!] … is a persisted automount — not currently mounted.` + `[+] Access it once (e.g.: ls <mp>) to auto-mount it, or remove the persistence first: menu option 5 (pos share smb-client unpersist <mp>)`), bare line otherwise; **`exit 0` → `return 0`** (CLI verb still ends rc 0 via fall-through).
- Same-function necessity also fixed: busy-path lazy-unmount success `exit 0` → `return 0` (was the identical session-kill class, reachable from the menu after a successful forced unmount).
- usage(): unmount line now "(idempotent: rc 0 when nothing is mounted)".

## Step 3: nfs-client parity [DONE]
- Verified pre-existing: nfs `cmd_unmount` already returned (not exited) on non-mounted.
- Added mirror guidance: new `persisted_nfs_at()` helper (`Type=nfs*`, Where= match, sets PERSISTED_UNIT); non-mounted + persisted → `[!] <mp> has a persistent NFS mount unit (<unit>) — not currently mounted.` + `[+] Check it: systemctl status <unit> — or remove the persistence: menu option 5 (pos share nfs-client unpersist <mp>)`. Plain log otherwise; `return 0` preserved.
- usage(): unmount line gains "(idempotent: rc 0 when nothing is mounted)".

## Step 4: menu handler normalization (BOTH clients) [DONE]
Approach chosen: **call-site normalization** — every handler invocation in `run_menu`'s case gets `|| true` (1–5 in both files), preserving documented handler contracts (rc 1 = cancel/back per comments/menu-lib conventions). Alternative (rewriting handlers to return 0 on cancel) rejected: would blur contracts across many return sites and risk misses.

## Step 5: confirm() call-site audit [DONE]
26 live call sites (2 grep hits are comment lines). Current-default column = arg as passed; post-change Enter column = behavior AFTER this change (all destructive `n` sites keep deny-on-Enter):

| # | Site | Prompt | Default | Post-change Enter |
|---|------|--------|---------|-------------------|
| 1 | pos-share-nfs-client:156 | Unit exists — overwrite? | n | DENY (kept) |
| 2 | pos-share-nfs-client:305 | Create mountpoint? | n | DENY (kept) |
| 3 | pos-share-nfs-client:377 | Try anyway? (2049 down) | n | DENY (kept) |
| 4 | pos-share-nfs-client:414 | Unmount <mp>? | n | DENY (kept) |
| 5 | pos-docker-compose:214 | Edit .env before starting? | **Y** | ACCEPT + now correct `[Y/n]` display (was broken `[y/N]`+Enter-deny — fixed by case-insensitive default) |
| 6 | pos-docker-compose:393 | Stop and remove stack (down)? | n | DENY (kept) |
| 7 | pos-docker-compose:402 | Restart stack? | n | DENY (kept) |
| 8 | pos-docker-compose:419 | Update ALL stacks (overwrite)? | n | DENY (kept) |
| 9 | pos-share-smb-client:133 | Mount over non-empty dir? | n | DENY (kept) |
| 10 | pos-share-smb-client:277 | Force lazy unmount (busy)? | y | ACCEPT (unchanged) |
| 11 | pos-share-smb-client:337 | Replace existing units? | n | DENY (kept) |
| 12 | pos-share-smb-client:453 | Force lazy unmount (unpersist)? | y | ACCEPT (unchanged) |
| 13 | pos-share-smb-client:574 | Create mountpoint? | n | DENY (kept) |
| 14 | pos-share-smb-client:680 | Unmount <mp>? | n | DENY (kept) |
| 15 | pos-system-backup:79 | Copy backup to <root>/backups/? | n | DENY (kept) |
| 16 | pos-system-backup:233 | Create (UN)ENCRYPTED backup? | n | DENY (kept) |
| 17 | pos-system-backup:243 | Create ENCRYPTED backup? | n | DENY (kept) |
| 18 | pos-system-schedule:83 | Run job now? | n | DENY (kept) |
| 19 | pos-share-smb-server:331 | Read-only share? | n | DENY (kept) |
| 20 | pos-share-smb-server:334 | Guest access? | n | DENY (kept) |
| 21 | pos-docker-vbox:79 | Create VM (host dir)? | n | DENY (kept) |
| 22 | pos-docker-vbox:83 | Create VM? | n | DENY (kept) |
| 23 | pos-docker-vbox:104 | Permanently remove VM? | n | DENY (kept) |
| 24 | pos-docker-vbox:208 | Enter now? | (omitted→y) | ACCEPT (unchanged) |
| 25 | lib/usb-lib.sh:118 | Mount at <mp>? | n | DENY (kept) |
| 26 | lib/usb-lib.sh:186 | Format/wipe partition? | n | DENY (kept) |
| — | lib/share-lib.sh:104 | Fix it now? (advisory) | n | DENY (kept; offer stays advisory rc 0) |

Counts: 21 explicit-`n` (all keep deny-on-Enter) · 1 `"y"` · 1 `"Y"` (bug fixed) · 2 omitted (default-y, unchanged) — total 26. No call site hardcodes its own `[Y/n]`/`[y/N]` into the prompt string (repo-wide grep: only raw `read -rp` prompts outside confirm(), out of T7 scope).

## Step 6: DOC/DEV.md [DONE]
- Shared-library table row: `confirm "prompt" [default]` → "y/n prompt; Enter accepts the default (`y` when omitted)".
- Best Practices gains `### Confirmation prompts`: "`confirm()` rule: Enter accepts the displayed default; destructive call sites pass explicit `'n'`."

## Step 7: Verification probes (throwaway stubbed env /tmp/opencode/t7, cleaned) [DONE]
Stubs: findmnt/sudo/systemctl/mount.{cifs,nfs}; fixture units in seam `UNIT_DIR`; pty via `script` (+Ctrl-D `\004`, 15 s timeout).
- (a) typed unmount idle-persisted share → `[!] …persisted automount — not currently mounted.` + actionable persistence-removal hint; **menu redraws (session survives)**, rc 0; bare "Nothing mounted" absent. NFS twin prints unit name + systemctl status hint; survives. ✅
- (b) cancel/EOF: Ctrl-D at typed prompt (smb+nfs), picker `q` cancel, Enter-decline at unmount confirm → all: menu redraws, rc 0, no silent death (pre-edit: zero-byte rc-1 kill reproduced first). ✅
- (c) mounted-path unmount: CLI verb `[+] Unmounted <mp>` + sudo umount logged (rc 0); interactive pick→y→Unmounted→menu survives. NFS same. ✅
- (d) scripted byte-compat vs pre-edit copies: list/unmount-unknown/unmount-noarg/bogus/unpersist-unknown ×(smb,nfs) — stdout AND stderr byte-identical, rc parity (incl. rc 0 idempotent unmounts). Only intentional delta: usage() unmount doc line. ✅
- (e) confirm matrix: no-arg Enter=YES / n=NO / garbage=NO / EOF=NO(rc-safe, no unbound error); "y" Enter=YES; "Y" Enter=YES+[Y/n]; "n" Enter=NO / y=YES / EOF=NO. Display strings verified under pty (read -p suppresses prompt without tty — pipe probes can't see it). ✅
- (f) vbox-rm-shaped simulation (subshell sourcing common.sh): Enter → DENIED. ✅

## Step 8: Gates [DONE]
- `bash -n` ×3 (smb-client, nfs-client, common.sh): OK
- `make gen`: write OK ×2, byte-identical reruns → idempotent; completions/pos.bash unchanged; only AGENT_Context_Project.md line-count rows updated (495 nfs / 754 smb — T6 rewrites + this change), as required after touching pos-* tools
- `make check` (scripts/check-sync.sh): **OK**
- `make lint` (scripts/lint-conventions.sh): **0 FAIL, 0 WARN**
- Throwaway probe env (/tmp/opencode/t7 incl. stubs + baselines) removed after verification.

## Scope compliance & handoff notes
- In-scope changes only; no commits made. Allowed files respected: the 2 clients, lib/common.sh, DOC/DEV.md (+ make-gen-owned AGENT_Context_Project.md rows).
- Discovered, NOT fixed (same silent-death class as Item 1, outside the enumerated fix list — flagged for Orchestrator triage): `cmd_unpersist` not-found paths still `exit 0` and would kill an interactive session on a bogus typed path — bin/pos-share-smb-client:438 (`No persistent SMB mount…`, exit at :439) and bin/pos-share-nfs-client:202–203 (`warn No systemd mount unit…`). One-line fix each (`exit 0`→`return 0`) if approved.
- Brief-correction recorded in Step 0: pre-edit confirm() already accepted Enter for y/omitted defaults; real pre-change defects were EOF fail-open and case-sensitive `"Y"` default handling.

Status: IMPLEMENTED

Recommended next agent: Reviewer

Reason: Both items implemented with targeted probes green and all gates passing; adversarial review of the confirm() semantics matrix and the menu-normalization approach is the remaining acceptance step before commit.

Changes made by Builder:
- lib/common.sh: confirm() default-on-Enter semantics + EOF fail-closed + case-insensitive display derivation
- bin/pos-share-smb-client: persisted_smb_at helper, cmd_unmount return-not-exit + idle-automount guidance, lazy-unmount exit→return, run_menu handler normalization, usage rc note
- bin/pos-share-nfs-client: persisted_nfs_at helper + mirrored unmount guidance, run_menu handler normalization, usage rc note
- DOC/DEV.md: table row + Confirmation prompts rule

REPORT_PATH: ./reportAgents/2026-08-23-builder-t7-unmount-fix-confirm-default.md
