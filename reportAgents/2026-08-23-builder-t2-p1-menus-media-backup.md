# Builder Report — T2 (P1 menus, part 1): Pattern-B menu doors for `pos-media-sync` + `pos-system-backup`

## TL;DR
- Status: **IMPLEMENTED** — all gates green, legacy paths byte-stable, probes pass.
- Files changed: `bin/pos-media-sync` (164→216) · `bin/pos-system-backup` (216→292) · DOC/POS.md (2 rows) · GEN blocks (`completions/pos.bash` 2 subcmd entries, `DOC/AGENT_Context_Project.md` 2 line-count rows).
- Pattern-B doors via T1's `lib/menu-lib.sh`: no-args+tty or `menu` verb → looping menu mapping existing behavior; with-args and non-tty invocations byte-identical to pre-change baselines.
- Verification: `bash -n` ✓ · gen idempotent ✓ · `make check` OK ✓ · `make lint` 0 FAIL 0 WARN ✓ · pty probes: render/q/EOF clean, preview path end-to-end, destructive backup PROMPT+ABORT on 'n' (0 archives) ✓.
- No new business logic: flows extracted verbatim into functions; restore/snapshot-listing omitted (no backing function). No commits.

## Step 0: Scope confirmation + plan [DONE]
- Brief read; T1 report + designer sketch Step 4.2/4.3 read; canonical shape `bin/pos-share-smb-server:378–408` read; `lib/menu-lib.sh` contracts read (guard/menu_run/menu_pick/menu_ask_value; stderr render, stdout index, EOF → rc 1).
- Both tools already in dispatcher `INTERACTIVE_CMDS` (`bin/pos:262`) — no `bin/pos` change needed, as brief states.
- Constraint honored: restore/snapshot-listing have NO existing backing functions in pos-system-backup → OMITTED (no new features).
- Allowed files only: `bin/pos-media-sync`, `bin/pos-system-backup`, DOC/POS.md (2 rows), GEN blocks, this report.

## Step 1: BEFORE baselines (byte-compat reference) [DONE]
- Harness dir `/tmp/opencode/t2-p1/` (throwaway HOME + temp src; cleaned at end).
- Non-tty baselines captured (`before/a1–a7`): media-sync `--help` rc0 · no-args `</dev/null` → section render + "No USB storage detected" + "Skipped — no sync performed" rc0 · `--mp4 --dry-run --src` same shape rc0 · backup `--help` rc0 · no-args `</dev/null` → `ERROR: Missing folder path (or use --service)` rc1 · bad path → Folder-not-found rc1 · `--service </dev/null` → folder list then EOF rc1.
- These are the AFTER byte-compare targets for with-args/non-tty paths.

## Step 2: bin/pos-media-sync menu door [DONE]
- `# POS_SUBCMDS: menu` added; `lib/menu-lib.sh` sourced via the standalone-safe 2-path chain (same shape as usb-lib line).
- Flow wrap: former top-level sync flow is now `cmd_sync()` — verified VERBATIM vs HEAD (`diff` after indent-strip = only mandated `exit 0`→`return 0` in the usb_pick_root skip branch).
- Menu glue: `run_menu()` (canonical smb-server shape: `menu_guard || exit 1` + loop over `menu_run`) with 5 items mapping onto existing modes only: 1 Sync now mp3+mp4 (= old default, first item) · 2 Preview `--dry-run` · 3 mp3-only · 4 mp4-only · 5 `menu_change_source` (ask_value + `-d` validation; warn+redraw on bad path).
- Front door before flag parser: `${1:-} = menu` verb, or `$# -eq 0 && [ -t 0 ]`; all other invocations fall through to the untouched parser.
- Usage text: 2-line "Bare ... opens an interactive menu" note (the ONLY intended help diff).
- Byte-compat AFTER probes: `--help` rc0 (note-only diff) · no-args `</dev/null` IDENTICAL to baseline · `--mp4 --dry-run --source …` IDENTICAL · `menu </dev/null` → guard pointer, rc1.

## Step 3: bin/pos-system-backup menu door [DONE]
- `# POS_SUBCMDS: menu` added; `lib/menu-lib.sh` sourced via same chain.
- Extractions verified content-verbatim vs HEAD: `pick_service_folder()` (= old inline `--service` picker) and `run_backup()` (= old top-level flow incl. trap swap + `usb_copy_offer`). CLI dispatch order preserved: parse → presence check → pick if `--service` → run_backup.
- Menu glue: `menu_backup_folder <enc>` (ask_value path + `-d` validation + y/N confirm via `confirm "$prompt" n` naming the folder), `menu_backup_service()` (pick_service_folder → same confirm), `run_menu()` with 3 items: encrypted typed/paste · encrypted from `${EFF_ROOTS}` picker · UNENCRYPTED typed/paste. Restore/snapshot-list OMITTED — no existing backing function (brief constraint).
- Front door identical shape; zero args non-tty still hits `err "Missing folder path (or use --service)"`.
- Destructive-op discipline: every menu backup runs only after explicit `y/N` (default N); 'n'/EOF aborts before any tar/gpg runs.
- Byte-compat AFTER probes: no-args `</dev/null` IDENTICAL · `/nonexistent` IDENTICAL · `--service </dev/null` IDENTICAL · `--help` note-only diff · `menu </dev/null` → guard pointer, rc1.

## Step 4: DOC/POS.md rows + make gen [DONE]
- Both rows gained one sentence documenting the opt-in door (bare-on-terminal or `menu` subcommand) and the item sets; backup row notes the explicit y/N confirm before any backup runs.
- `make gen` regenerated: `completions/pos.bash` += `_pos_subcmds[media-sync]="menu"` + `_pos_subcmds[system-backup]="menu"` (verified those are the only media/backup hunks); `DOC/AGENT_Context_Project.md` filetable line-count rows 164→216 / 216→292 (verified only media/backup delta is mine; remaining diff = pre-existing other-track WIP drift, same caveat as T1).

## Step 5: Gates [DONE]
- `bash -n bin/pos-media-sync bin/pos-system-backup` ✓
- `make gen` → re-run → identical result ⇒ **idempotent** ✓
- `make check` → **OK** ✓
- `make lint` → **0 FAIL, 0 WARN** ✓
- Verbatim-wrap proofs: media-sync flow body vs HEAD differs ONLY in `exit 0`→`return 0`; backup picker + backup flow content-identical after indent normalization.

## Step 6: pty-harness probes (`script -qec`, throwaway env) [DONE]
Excerpts (typescript logs were under `/tmp/opencode/t2-p1/pty/`, cleaned):
- **P1 media-sync render+quit**: 5 items + Exit rendered to stderr; `q` → `rc=0`.
- **P2 media-sync EOF**: immediate EOF on pty → rc 0, no hang.
- **P3 media-sync item 2 preview end-to-end**: `2)` chosen → sync section renders → `[!] No USB storage detected` → plug-prompt answered `s` → `[+] Skipped — no sync performed` → menu REDRAWS (loop survived) → `q` rc 0.
- **P3b item 5 change source**: `Source set to <tmp/src>`; next render shows `5) Change source folder (current: …/src)` — glue state visible.
- **P4 backup render+quit**: 3 items + Exit; `q` → rc 0.
- **P5 destructive PROMPT+ABORT**: item 1 → folder prompt → `Create ENCRYPTED backup of …? [y/N]:` answered `n` → `[+] Cancelled` → **archives created: 0** → loop redraws → rc 0.
- **P6 EOF at confirm**: EOF → fail-closed cancel, archives 0, rc 0.
- Non-tty fail-closed pointing at verbs: `menu </dev/null` on both tools prints `[!] Interactive menu needs a terminal — use a subcommand instead (see --help).` rc 1 (Steps 2–3); all legacy non-tty invocations byte-IDENTICAL to pre-change baselines.

## Final diff summary (this task only)
| File | Change |
|---|---|
| `bin/pos-media-sync` | 164→216: `# POS_SUBCMDS: menu` · menu-lib sourcing chain · usage note · `cmd_sync()` verbatim wrap (skip branch `return 0`) · `menu_change_source` + `run_menu` (5 items) · front door (verb + no-args+tty) before untouched flag parser |
| `bin/pos-system-backup` | 216→292: `# POS_SUBCMDS: menu` · menu-lib sourcing chain · usage note · `pick_service_folder()` + `run_backup()` verbatim extractions · `menu_backup_folder`/`menu_backup_service` + `run_menu` (3 items, y/N confirms) · front door; CLI dispatch order preserved |
| `DOC/POS.md` | 2 rows: menu-door sentence each |
| `DOC/AGENT_Context_Project.md` | GEN only: two filetable line-count rows |
| `completions/pos.bash` | GEN only: two `_pos_subcmds[…]="menu"` entries |
| `reportAgents/2026-08-23-builder-t2-p1-menus-media-backup.md` | this report |

## Scope compliance
- In-scope changes confirmed: exactly the brief's allowed files (2 tools, their POS.md rows, GEN-regenerated blocks, this report).
- Out-of-scope changes: none. No commits. `bin/pos`, dispatcher `INTERACTIVE_CMDS`, libs, install.sh untouched. Restore/snapshot-listing omitted per no-new-features constraint.

## Remaining risks / notes for next agent
- `pick_service_folder` EOF mid-picker inside the MENU path surfaces as `ERROR: Invalid selection:` (condition-context suppresses errexit differently than the bare CLI call) — fail-closed either way, never hangs; CLI `--service` behavior unchanged.
- Media-sync "sync now" intentionally has NO confirm (add/update-only, never deletes; designer's preview→confirm composite covered by separate dry-run menu item).
- P2 (docker-compose + system-schedule) can clone this exact shape.

REPORT_PATH: ./reportAgents/2026-08-23-builder-t2-p1-menus-media-backup.md
