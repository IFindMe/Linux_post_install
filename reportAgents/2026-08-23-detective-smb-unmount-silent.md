# Detective — `pos share smb-client` unmount: no feedback for idle-automount targets

## TL;DR
- Root cause (STRONG INFERENCE, behavior FACT-reproduced): idle x-systemd.automount SMB shares are invisible to `findmnt -t cifs`; `cmd_unmount` then hits its idempotent branch → one low-salience stdout line `[+] Nothing mounted at <mp>` (**not** `[+] Unmounted`, no error) and **`exit 0` kills the entire interactive session** (umount never attempted — proven).
- Second defect found & reproduced: any cancel/EOF/empty-input from the unmount flow returns 1 into bare `4) menu_unmount ;;` under `set -euo pipefail` → **silent whole-process death, rc 1, ZERO bytes** — the only literally-output-free path.
- NFS looked "correct" only because its boot-time `.mount` target WAS active → real success path; its code also reports-and-survives (`return 0`).
- Today's worktree adds `[+] No active SMB mounts` context but keeps both defects (exit-0 session kill; errexit silent death).
- Fix list for Builder at end of Step 5. Box-side verification commands included (installed copy vs repo diff).

## Step 1: HEAD smb-client unmount path trace [DONE]
All citations: `git show HEAD:bin/pos-share-smb-client` (= commit 5b2a030 content; 692cb6b did not touch this file).

Flow: `run_menu` :541 `4) menu_unmount ;;` (bare case branch, script has `set -euo pipefail` :2)
→ `menu_unmount` :491-506: `mapfile -t rows < <(findmnt -rnf -t cifs -o SOURCE,TARGET)`; zero rows → else :502 `share_ask_value "Local mountpoint to unmount"` (manual typed entry; NO context message printed before it) → :505 `cmd_unmount "$where"`.
→ `cmd_unmount` :240-259:
```bash
242:  validate_dir "$where"
244:  src="$(mounted_src "$where")"          # findmnt -rnf -t cifs … awk '$2==t' (:102-104)
245:  if [ -z "$src" ]; then
246:      log "Nothing mounted at $where"    # log = echo "[+] …" to STDOUT (lib/common.sh:22)
247:      exit 0                             # ← terminates the WHOLE tool incl. menu loop
248:  fi
249:  if ! out="$(sudo umount "$where" 2>&1)"; then … err "Unmount failed: $out" :255 … fi
257:  log "Unmounted $where"
```
Every committed variant prints ≥1 line per branch (verified back to creation a484961; pre-menu a0152fa:248-252 identical logic inline). No `run … || true`, no redirection swallowing.

[DONE]

## Step 2: State hypothesis + deterministic reproduction [DONE]
State: persist writes `.mount`+`.automount` units (HEAD :304, :353-366) enabled at boot; the `.mount` activates only on first access. Idle since boot ⇒ `findmnt -t cifs` empty ⇒ matches user's option-3 view exactly ("Persistent (automount):" section only). With only an autofs trigger present, `sudo umount <mp>` would fail "not mounted" — but the tool never gets there: `mounted_src` filters `-t cifs` → empty → idempotent branch first. Classification: STRONG INFERENCE for box state (design + user's own listing); discriminator below.

Reproduction (stubbed PATH: findmnt emits nothing for cifs; sudo logs + mimics real umount "not mounted"; pty via `script`), input = user's exact keystrokes `4⏎ /media/he/12T-smb⏎`:
- HEAD: prints `Choose: Local mountpoint to unmount: [+] Nothing mounted at /media/he/12T-smb`, **rc 0, process exits — menu never redraws**; sudo stub NEVER invoked (operationally a no-op).
- Empty Enter instead of path (`4⏎ ⏎`): `share_ask_value` rc1 → `menu_unmount` `return 1` :502 → bash-x trace ends `+ return 1` → **set -e kills process, rc 1, ZERO output** (bare `4) menu_unmount ;;` is not an errexit-exempt context).

Expected vs Actual:
```
Expected: explicit actionable outcome ([+] Unmounted …, or guidance for a persisted-but-idle target), menu survives.
Actual : one dismissible info line + abrupt session exit (typed path); or literally nothing + rc1 (empty/cancel).
First divergence: cmd_unmount's `-z "$src"` branch conflates "nothing ever configured", "idle automount",
                  and "wrong path" into one non-actionable line, then `exit 0` abuses process exit as control flow.
```

[DONE]

## Step 3: Today's working-tree (T6) delta [DONE]
Worktree `bin/pos-share-smb-client` (728 lines): T6 rewrote `menu_unmount` (:632-659) and mountpoint picking; **`cmd_unmount` untouched** (still :241-259, `log "Nothing mounted…"; exit 0` at :247-248).
- New: zero-active branch prints `log "No active SMB mounts"` (:644) before the same manual typed fallback (:645-647) → typed-not-mounted still ends in `[+] Nothing mounted …` + session-killing `exit 0` (reproduced; rc 0).
- Empty-input/EOF fallback: `|| return 1` → identical silent rc-1 errexit death (reproduced on worktree copy). Picker-branch cancel (`share_pick … || return 1`, HEAD :499 analog) is the same class when mounts DO exist.
- REMAINING SILENT/DEAD PATHS (answer): (a) manual typed fallback still reachable in both versions — yes; typed not-mounted → info line + full session exit; (b) empty/EOF → zero-byte rc1 death (both versions); (c) bare CLI verb `unmount <mp>` on not-mounted path → prints `[+] Nothing mounted …`, rc 0 (reproduced) — visible but rc conflates "unmounted" vs "nothing to do" (usage :24 says only "(idempotent)").

[DONE]

## Step 4: nfs-client parity [DONE]
HEAD nfs `cmd_unmount` (/tmp copy of `git show HEAD:bin/pos-share-nfs-client`) :70-80: not-mounted → `log "$where is not mounted as NFS — nothing to do"; return 0` — message printed AND `return 0` → **menu redraws, session survives** (reproduced: second menu box rendered after the notice). NFS persist writes plain boot-time `.mount` units (no automount), so its targets are normally ACTIVE → user's earlier `[+] Unmounted /mnt/hdd` was the ordinary success path :79, not the idempotent one. Typed-unmount-of-non-mounted-path latent issue: ABSENT at HEAD nfs (messaging exists, menu-safe). Worktree nfs (+141 lines today) keeps `cmd_unmount` intact and adds `log "No active NFS mounts"; return 0` for zero-active; residual: picker-cancel/confirm-decline still `return 1` into the same bare-case errexit class.

[DONE]

## Step 5: Recommended remedy (recommendation only) [DONE]
Builder fix list (worktree line refs):
1. `bin/pos-share-smb-client:245-248` — wrong: `-z "$src"` branch prints non-actionable line then `exit 0` (kills menu; conflates states). Change: keep printing, replace `exit 0` with `return 0`; if a `Type=cifs` unit in `${UNIT_DIR}` has `Where=` == `$where`, upgrade the line to e.g. `[!] $where is a persistent automount (not currently mounted) — access it once to trigger, or remove persistence: pos share smb-client unpersist <mp>`; unknown path keeps `[+] Nothing mounted at $where`. rc stays 0 both ways (scriptable behavior preserved; document rc0=idempotent in usage :24).
2. `bin/pos-share-smb-client:632-659` (+ HEAD :491-506) — wrong: handler `return 1` (EOF/empty/cancel) reaches bare `4) menu_unmount ;;` under `set -e` → silent rc-1 process death. Change: `4) menu_unmount || true ;;` (same for all handler case branches) or normalize menu_unmount to `return 0` on cancel.
3. Class-wide seam (flag only): same bare-handler/errexit pattern exists in other menu doors (nfs WT cancel paths, likely siblings) — worth a Toolsmith sweep, outside this bug.
Verification for he@debian (discriminates installed-copy drift & confirms idle state):
`diff <(git show HEAD:bin/pos-share-smb-client) /usr/local/bin/pos-share-smb-client` ; `findmnt -t cifs,autofs -o TARGET,SOURCE,FSTYPE | grep -e 12T -e lattepanda`.
Residual UNKNOWN (needs box): why the single `[+] Nothing mounted` line wasn't reported seen — candidates: low-salience line misread as noise + relaunch perceived as "returns to menu", or the user hit the reproduced zero-byte errexit path (stray Enter). Neither requires a different fix than 1+2.

Recommended next agent: Builder (fix list above; root cause established, read-only investigation, no changes made).

REPORT_PATH: ./reportAgents/2026-08-23-detective-smb-unmount-silent.md
