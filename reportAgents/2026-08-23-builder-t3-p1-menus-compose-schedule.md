# Builder Report — T3 (P1 menus, part 2): Pattern-B menu doors for `pos-docker-compose` + `pos-system-schedule`

## TL;DR
- Status: **IMPLEMENTED** — all gates green, legacy paths byte-stable, probes pass.
- Files changed: `bin/pos-docker-compose` (366→487) · `bin/pos-system-schedule` (81→151) · DOC/POS.md (1 new paragraph + 1 row sentence) · GEN blocks (`completions/pos.bash` 2 subcmd entries, `DOC/AGENT_Context_Project.md` 2 line-count rows 366→487 / 81→151).
- Pattern-B doors via T1's `lib/menu-lib.sh`: no-args+tty or explicit `menu` verb → looping menu mapping EXISTING functions only; with-args and non-tty invocations behave exactly as before (help texts differ only by the intended 2-line bare-invocation note).
- Verification: `bash -n` ✓ · gen idempotent (re-run byte-compare clean) ✓ · `make check` OK ✓ · `make lint` 0 FAIL 0 WARN ✓ · pty probes ×13: render/q/EOF clean, ls/list end-to-end read-only, destructive down/restart/update/run-now PROMPT+ABORT on 'n', editor nesting survives, non-tty guard rc 1 pointing at verbs ✓.
- Automation door proven twice over: `run <name>` dispatch case is **byte-identical to HEAD** (programmatic cmp) and `run probejob` output/rc byte-identical before/after.
- Incident during verification (self-inflicted, fully recovered): a PATH-shim *symlink* was later written through (`> shim/x` follows symlinks) and clobbered both repo tools with 2-line self-wrappers mid-probe. Both files were restored from HEAD + replayed edits; restoration verified by line counts matching GEN rows (487/151), identical `git diff --stat`, zero gen drift, full gate + probe re-run. Details in Step 6b.
- No commits. AGENT_TODO.md untouched (outside allowed files — left for Orchestrator).

## Step 0: Scope confirmation + plan [DONE]
- Brief + T1 contract report + designer sketches §4.1/§4.4 read; T2 references `bin/pos-media-sync` / `bin/pos-system-backup` cloned structurally (front door → `menu_guard` → loop around `menu_run`; standalone-safe sourcing chain; `# POS_SUBCMDS:` += `menu`, appended last per smb-server canonical).
- Canonical shape re-read from `bin/pos-share-smb-server:378–410`. `lib/menu-lib.sh` contracts confirmed (stderr render, stdout index, EOF/non-tty → rc 1, never exits).
- Both target tools are already dispatcher `INTERACTIVE_CMDS` members (`bin/pos:262`) → no dispatcher change, as briefed.
- Backing-function inventory: compose → `cmd_ls/cmd_installed/cmd_up/cmd_down/cmd_restart/cmd_logs/cmd_update/cmd_config`; schedule → `sched_list/sched_status/sched_run/sched_enable/sched_disable/sched_config_editor/sched_list_jobs`. No item without an existing backing function was added.
- Allowed files only: the two bins, their DOC/POS.md rows, GEN-regenerated blocks, this report.

## Step 1: BEFORE baselines (byte-compat reference) [DONE]
- Throwaway env `/tmp/opencode/t3-p1/` (temp HOME, fake SCALE_DIR with 2 templates, fake SERVICES_BASE with 1 deployment, temp SCHEDULE_DIR/STATE/LOG/USER_SYSTEMD_DIR with one `probejob` NOTIFY=never job). Cleaned at end.
- Captured pre-change: compose `--help`/no-args-nontty(rc0 usage)/`ls`/`installed`/bad-sub(usage); schedule `--help`/no-args-nontty(rc0 usage)/`list`/`status`/unknown-sub(rc1)/**`run probejob`(rc0)**.
- Box facts noted: docker binary present AND daemon reachable; `installed` degrades to real status via read-only query; `ls` needs no daemon.

## Step 2: bin/pos-docker-compose menu door [DONE]
- Header `# POS_SUBCMDS:` += `menu` (last, smb-server precedent); menu-lib sourced via the same 2-path chain as common.sh.
- Usage gained ONLY the 2-line "Bare … opens an interactive menu" note.
- Glue: `menu_list_templates`/`menu_list_deployed` (same enumeration their `cmd_ls`/`cmd_installed` use internally, LC_ALL=C sorted) · `menu_pick_stack` (menu_pick wrapper with designer empty-state hint) · handlers `menu_up/menu_down/menu_restart/menu_logs/menu_update`.
- Items map 1:1: ls, installed, up (pick template — first-deploy `.env`/TS_AUTHKEY prompts fold inside `cmd_up`), down (y/N naming stack), restart (y/N naming stack), logs (`cmd_logs <svc> -f`, guarded so Ctrl-C/error returns into the loop), update (y/N naming `$SERVICES_BASE`, ".env preserved"), config show, config edit (EDITOR modal).
- Front door before `[ $# -eq 0 ] && usage`: `${1:-} = menu` verb or `$# -eq 0 && [ -t 0 ]`; every other invocation falls through to the untouched parser/dispatch.
- Destructive discipline: aborts happen BEFORE any `cmd_*` call, so 'n'/EOF can never reach docker.

## Step 3: bin/pos-system-schedule menu door [DONE]
- Header += `menu` (last); menu-lib sourced after notify.sh.
- Usage note explicitly documents that timers keep calling `'run <name>'` directly.
- Glue: `menu_pick_job` (over existing `sched_list_jobs`, empty-state wording mirrors lib's own message) · `menu_job_action run|enable|disable` calling the SAME functions the CLI verbs dispatch to; run-now additionally y/N-confirm-gated (default N).
- Items: list, timer status, run a job now (confirm-gated), enable, disable, open interactive job editor (`sched_config_editor`, nests and returns).
- Front door inserted BEFORE the `-h|--help|"")` case; no-args non-tty still falls through to `usage` unchanged. No composite "toggle" item (enable/disable cover it via existing verbs; avoids new semantics).

## Step 4: DOC/POS.md rows + make gen [DONE]
- Docker section: new paragraph after `config edit` documenting the hub, its items, confirms naming targets, fail-closed non-tty behavior.
- Schedule table row: appended sentence — interactive hub over the verbs, y/N-gated run-now through the same `run <name>` path the timers use.
- `make gen` regenerated exactly: `_pos_subcmds[docker-compose]="… config menu"`, `_pos_subcmds[system-schedule]="… migrate menu"`, filetable rows 366→487 / 81→151. Other hunks in those GEN files are other tracks' pre-existing regenerated WIP (same caveat as T1/T2 reports).

## Step 5: Gates [DONE]
- `bash -n` both tools ✓
- `make gen` → copy outputs → re-run → byte-compare ⇒ **idempotent** ✓
- `make check` → **OK** ✓
- `make lint` → **0 FAIL, 0 WARN** ✓

## Step 6: pty-harness probes (`script -qec`, hard 20s cap per probe, EOT byte for EOF cases) [DONE]
Excerpts (typescript logs under `/tmp/opencode/t3-p1/pty/`, cleaned):
- **c1/s1 render+quit**: full boxed item list rendered; `q` → rc 0.
- **c2/s2 EOF**: immediate EOT → `COMMAND_EXIT_CODE="0"`, no hang.
- **c3 ls-item end-to-end**: template listing renders (read-only; daemon not required), menu redraws, `q`.
- **s3 list-item**: JOB table renders, redraw, `q`.
- **c4 down PROMPT+ABORT**: picker `-- 1 available -- / 1) jellyfin` → `Stop and remove stack 'jellyfin' (docker compose down)? [y/N]: n` → `[+] Cancelled` → redraw. No docker invocation reachable on abort.
- **c5 restart-abort**: same shape (`Restart stack 'jellyfin'? [y/N]: n`).
- **c6 update PROMPT+ABORT**: confirm names the target root: "Update ALL stacks: … under /tmp/opencode/t3-p1/services (.env preserved)? [y/N]: n" → Cancelled.
- **s4 run-now PROMPT+ABORT**: `Run job 'probejob' now (executes its COMMAND, applies its NOTIFY policy)? [y/N]: n` → Cancelled → redraw (confirm gate proven; nothing executed).
- **s5 editor nesting**: `sched_config_editor` renders its job list + action prompt inside the menu; nested `q` returns to the OUTER menu redraw.
- **c7/s6 non-tty**: `menu </dev/null` → `[!] Interactive menu needs a terminal — use a subcommand instead (see --help).` rc 1 on both tools.
- **Automation-door proof**: `run <name>` dispatch case block extracted and `cmp`'d against HEAD ⇒ BYTE-IDENTICAL; plus live `run probejob` output+rc byte-identical pre/post.
- Byte-compat suite (10 cases): all IDENTICAL except help/no-args texts showing only the intended note lines; `list` compared modulo its minute-resolution LAST-column timestamp (delta traced to my own baseline's `run probejob` writing last-run state — rendering identical).

## Step 6b: Incident + recovery (disclosure) [DONE]
- While smoke-testing through the real dispatcher I created PATH shims; attempt #1 made **symlinks**, attempt #2 wrote wrapper content with `>` which **followed the symlinks and clobbered both repo tools** with 2-line self-referencing wrappers (observed as infinite exec loops / probe hangs).
- Recovery: killed spinners, removed shim dir, `git show HEAD:<tool>` restored both files, then replayed my recorded edits verbatim.
- Restoration evidence: line counts 487/151 match the already-generated filetable rows exactly; `git diff --stat` identical to pre-incident (123/72 changed lines, 193 insertions); `make gen` re-run produces ZERO drift vs pre-incident GEN outputs; `bash -n`, `make check`, `make lint`, and all 13 pty probes re-run green post-restore.
- Root cause logged for my own practice: never `>` through a symlink; wrappers must be created in a dir without prior symlinks of the same name.

## Step 7: Dispatcher smoke (informational) [DONE]
- `/usr/local/bin/pos-*` installed copies (root-owned, pre-menu) shadow repo bins when invoking via `bin/pos` on this dev box — expected design (`command -v` wins), NOT caused by this change; direct repo-file invocations used for all probes.
- With exec-wrappers resolving to the repo copies, `bin/pos docker compose menu </dev/null` reaches the tool correctly (guard fires; INTERACTIVE_CMDS path execs directly). No dispatcher changes made.

## Final diff summary (this task only)
| File | Change |
|---|---|
| `bin/pos-docker-compose` | 366→487: `# POS_SUBCMDS:` += `menu` · menu-lib sourcing chain · usage note · enumerators + pick helper + 5 handlers + `run_menu` (9 items; down/restart/update y/N confirms naming targets) · front door before CLI dispatch |
| `bin/pos-system-schedule` | 81→151: `# POS_SUBCMDS:` += `menu` · menu-lib sourcing chain · usage note (timers keep `run <name>`) · `menu_pick_job`/`menu_job_action` + `run_menu` (6 items; run-now confirm-gated) · front door before `-h` case; verb dispatch untouched |
| `DOC/POS.md` | compose section: new `menu` paragraph; schedule row: hub sentence appended |
| `completions/pos.bash` | GEN only: two `_pos_subcmds[…]+= menu` entries |
| `DOC/AGENT_Context_Project.md` | GEN only: two filetable line-count rows (487 / 151) |
| `reportAgents/2026-08-23-builder-t3-p1-menus-compose-schedule.md` | this report |

## Scope compliance
- In-scope changes confirmed: exactly the brief's allowed set (2 tools, their POS.md rows, GEN-regenerated blocks, this report). No new deps, no state changes, no commits.
- Out-of-scope changes: none. `bin/pos`, `lib/*`, `install.sh`, AGENT_TODO.md untouched. Omitted by constraint: composite toggle item (covered by enable/disable), up-all/down-all items (not in brief's item list), typed-stack entry (pickers exist for both listings).

## Remaining risks / notes for next agent
- `logs -f` menu item relies on `if ! cmd_logs` to survive Ctrl-C (rc 130) — verified pattern-safe in bash conditional context; worst-case degradation is a clean menu exit.
- Choosing an item whose backing command hard-fails (e.g. `up` on a box without docker) exits the whole tool via `err()` — identical to CLI behavior today; predictable empty-states are caught by glue warnings instead.
- On machines with stale installed copies, `pos docker compose menu` reaches the old installed binary until reinstall — pre-existing install-shadowing semantics, worth noting for release comms.
- AGENT_TODO.md still lists P1-menu work as open (file outside my allowed set) — Orchestrator may want to move it to Done dated.

REPORT_PATH: ./reportAgents/2026-08-23-builder-t3-p1-menus-compose-schedule.md
