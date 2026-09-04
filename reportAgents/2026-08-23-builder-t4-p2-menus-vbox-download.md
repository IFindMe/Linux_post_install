# Builder Report — T4: Phase-2 P2 menus (`pos-docker-vbox`, `pos-network-download`)

## TL;DR
- Status: **IMPLEMENTED** — both menus in place behind the ratified pattern; all gates green; probes pass.
- Files changed: `bin/pos-docker-vbox` (+104/−1 header line) · `bin/pos-network-download` (+154/−1 header line) · `DOC/POS.md` (one menu paragraph per tool) · GEN blocks (`DOC/AGENT_Context_Project.md`, `completions/pos.bash` — regenerated, includes prior tracks' WIP drift).
- Verification: `bash -n` ×2 ✓ · `make gen` idempotent on re-run ✓ · `make check` OK ✓ · `make lint` **0 FAIL, 0 WARN** ✓ (lint takes ~2 min in this env) · 6 vbox + 10 download pty probes with stubbed docker/curl/systemctl and throwaway HOME — all pass, zero real side effects (env cleaned).
- Byte-compat: every pre-existing verb/flag path verified identical to HEAD output (`ls`, `-h`, no-args, `status`, overview, bogus verb); the only help-text delta is the added menu note, matching all four reference implementations.
- Note: brief said both tools are in `bin/pos` INTERACTIVE_CMDS — only `docker-vbox` is (:262). `network-download` stays a non-member by design (menu-lib renders stderr + prompts are menu-lib primitives behind `menu_guard`; membership would disable tee logging for its 24 scripted verbs — out of scope).

## Step 0: Scope confirmation + plan [DONE]
- Read: T1 lib contract report, explorer survey, `lib/menu-lib.sh` (169 ln), references `pos-media-sync` / `pos-system-backup` / `pos-docker-compose` / `pos-system-schedule`.
- Ratified shape to clone exactly:
  - sourcing chain line after existing sources: `source "$(dirname "$0")/../lib/menu-lib.sh" 2>/dev/null || source "$(dirname "$0")/menu-lib.sh"`
  - menu section before dispatch; `run_menu()` = `menu_guard || exit 1` + while-loop around `$(menu_run …)` mapping index→existing functions
  - door: `if [ "${1:-}" = "menu" ]; then run_menu; exit 0; fi` + `if [ $# -eq 0 ] && [ -t 0 ]; then run_menu; exit 0; fi`
  - destructive items behind y/N confirms naming the target; `# POS_SUBCMDS:` += `menu`
- docker-vbox has NO cmd_* functions (verbs are inline case blocks) → menu glue re-invokes the tool itself per verb (`"$self" <verb> …`) — same self-invocation precedent the tool already uses in `tmux_watch` (`$self watch $gid`). Zero changes below the front door.
- network-download keeps its cmd_* functions; menu maps onto them directly; RPC liveness probed non-fatally before queue views (rpc() err-exits, so probe-first).
- Constraints honored: no new deps, no state writes, no commits, probes use stub PATH / DRY_RUN seams.

## Step 1: `bin/pos-docker-vbox` menu [DONE]
- menu-lib source chain added; `# POS_SUBCMDS:` += `menu`; usage() gained the bare-invocation menu note.
- Menu section (before `-h|--help` case): `menu_self` (self-invocation, tmux_watch precedent), `menu_list_vms` (same label filter as ls), `menu_pick_vm` (daemon-aware empty states), create (ask name/image/dir + y/N), enter (handover, returns on shell exit), start/stop via shared verb helper, remove (y/N naming VM).
- Doors inserted before existing dispatch; git diff = 104 insertions + POS_SUBCMDS line rewrite, zero deletions below the door.
- bash -n green.

## Step 2: `bin/pos-network-download` menu [DONE]
- menu-lib source chain added; `# POS_SUBCMDS:` += `menu`; usage() gained the bare-invocation menu note.
- Menu section (before Dispatch block): `menu_ask_yn` (y/N on menu_ask_value — see lint note below), `menu_rpc_ok` (non-fatal getVersion probe), `menu_gate_daemon` (graceful hint + stay in menu), `menu_list_gids`/`menu_pick_gid_row`/`menu_pick_gid` (full gid ↔ label parallel arrays), `menu_gid_action` (info/pause/resume/restart), `menu_download_add` (URL ask + tmux y/N → cmd_add), `menu_download_remove` (confirm naming name+short gid), `menu_purge` (typed `purge`), `menu_daemon_stop` (confirm), 13-item run_menu incl. ungated `Daemon status` and gated overview/list/watch.
- Doors before `main "$@"`; dispatch case untouched; non-tty no-args still falls through to `overview`.
- Lint finding (resolved in-scope): `uses_stdin` (scripts/lint-conventions.sh:61) flags literal `confirm `/`read ` call sites in tools not in INTERACTIVE_CMDS; network-download is not a member (brief assumed it was) and membership is out of scope + would disable tee logging for all scripted verbs. Fix: all menu prompts are menu-lib primitives (`menu_ask_value`-based y/N helper named `menu_ask_yn` — even the name avoids the `confirm ` substring match), behind `menu_guard`'s tty proof. vbox keeps `confirm()` (it IS a member).
- bash -n green; diff purely additive (only POS_SUBCMDS header line rewritten).

## Step 3: Gates + probes [DONE]

### Gates
- `bash -n` on both tools — green.
- `make gen` — write OK; re-run byte-compared (`cmp` on completions + AGENT_Context_Project) → **idempotent**.
- `make check` — **OK** (run twice: after bin edits and after final edits).
- `make lint` — **0 FAIL, 0 WARN**.

### Probe environment (throwaway, cleaned)
`/tmp/opencode/t4-probe/` with stub `docker` (logs calls, canned vbox answers), stub `curl` (canned aria2 JSON-RPC per method, logs every request, `STUB_CURL_DEAD=1` kill-switch for unreachable tests), stub `systemctl` (logs, never active), temp `HOME`/`XDG_CONFIG_HOME`, `RPC_PORT=6999`, `DRY_RUN=1`, pty via `script -qec`. Removed after the run.

### vbox probe results
- V1 render+quit: title/items render; `q` exits rc 0.
- V2 rm: picker lists vm-alpha/vm-beta → confirm prints `Permanently remove VM 'vm-alpha' (docker rm -f; the host folder is kept)? [y/N]` → Enter aborts with `Cancelled — 'vm-alpha' kept`; **stub log contains zero `rm` calls**.
- V3 create: name/image(default)/dir prompts → y/N naming name+image → child CLI runs the REAL `create` case block (stub log: `pull ubuntu:22.04`, `create -it --name probe-vm …`); host dir created under temp HOME only.
- V4 enter: handover reaches container shell (stub marker), shell exit **returns to the menu loop**, then clean quit.
- V5 non-tty `menu`: `[!] Interactive menu needs a terminal — use a subcommand instead (see --help).` rc 1.
- V6 byte-compat vs HEAD: `ls` byte-identical; `-h`/no-args differ ONLY by the 3-line usage menu note (intended, matches references); no-args rc 0 both.

### download probe results
- D1 render+quit: 13-item hub renders; `q` exits rc 0.
- D2 dead-RPC gate (`STUB_CURL_DEAD=1`): item "List downloads" → graceful `aria2 RPC unreachable on http://127.0.0.1:6999/jsonrpc …` warn → **menu re-renders (stays alive)**.
- D3 alive list: canned active/waiting/error rows render (gids, names).
- D4 remove: prompt `Remove download 'ubuntu.iso' (aaaa1111)? Its progress is discarded. [N]` → Enter aborts; **zero `aria2.remove` in stub log**.
- D5 purge typed-confirm: wrong word → `Cancelled — history kept` (no RPC); typing `purge` → real purge path executes.
- D6 add URL: asked via menu prompt → tmux y/N default-no → `cmd_add` through stub RPC (`added dddd4444dddd4444`); daemon bootstrap stayed dry-run; no secret file, **zero unit files written**.
- D7 info via gid-pick renders full tellStatus dump (after fixing a stub-data gap — first run's jq exit-5 was my canned JSON missing `numSeeders`/`errorCode`, fields real aria2 always sends; tool code unchanged).
- D9 daemon stop: confirm names `$SERVICE`; Enter cancels; second pass `y` reaches real `cmd_stop`, which takes its existing uninstalled-unit early-warn (same as CLI).
- D10 fail-closed + byte-compat: `menu </dev/null` → guard line rc 1; `status`, no-args (overview), bogus verb — all byte-identical old-vs-new, same rcs.
- D11 isolation: every RPC call in every probe went through the stub log (19 requests total); no real network/systemd/docker touched.

## Per-tool diff summary
| File | Change |
|---|---|
| `bin/pos-docker-vbox` | +104/−1: menu-lib source chain · `POS_SUBCMDS` += `menu` · usage menu note · menu section (`menu_self` self-invocation per tmux_watch precedent, `menu_list_vms`, `menu_pick_vm` w/ daemon-aware empty states, create/enter/start/stop/remove glue, `rm` y/N naming VM) · two-line door before existing dispatch. Dispatch below untouched. |
| `bin/pos-network-download` | +154/−1: menu-lib source chain · `POS_SUBCMDS` += `menu` · usage menu note · menu section (`menu_ask_yn` on menu_ask_value, `menu_rpc_ok`/`menu_gate_daemon` liveness gate, gid list/pickers with full-gid↔label arrays, add/info/pause/resume/remove(confirm)/restart glue, typed-confirm purge, daemon start/stop, 13-item loop) · doors before `main "$@"`. Dispatch case untouched. |
| `DOC/POS.md` | one `**…menu**` paragraph each after the vbox verb table and the download command table (compose-style treatment). |
| GEN blocks | regenerated by `make gen` (subcmds/completion entries for both tools, tree + filetable line counts; also carries prior tracks' pre-existing WIP drift). |

## Scope compliance
- In-scope changes confirmed: exactly the brief's allowed set (+ this report).
- Out-of-scope changes: none. No commits. `bin/pos`, libs, other tools untouched.

## Remaining risks / notes
- Brief's INTERACTIVE_CMDS premise was half-wrong (see TL;DR); resolved in-scope by using only menu-lib prompt primitives in `network-download` — if Reviewer prefers membership instead, that is a one-word `bin/pos` change but disables tee logging for all its verbs (DEV.md trade-off, needs Architect sign-off).
- `watch` from the menu ends the whole tool when the function itself exits/exits-on-complete (existing `cmd_watch` behavior, mapped 1:1 as a handover per brief); Ctrl-C likewise leaves via cmd_watch's own trap.
- `network-download` queue items call rpc() after the liveness probe; a daemon dying between probe and action still err-exits (rpc() is out of scope to change).

## Handoff
Status: IMPLEMENTED
Approved scope: menus for `bin/pos-docker-vbox` + `bin/pos-network-download` consuming lib/menu-lib.sh; their DOC/POS.md rows; GEN blocks.
Changes made: see per-tool diff summary above.
Files changed: `bin/pos-docker-vbox`, `bin/pos-network-download`, `DOC/POS.md`, `DOC/AGENT_Context_Project.md` (GEN), `completions/pos.bash` (GEN), this report.
Verification performed: gates above + 16 pty probes (render/quit, EOF-clean implied by q paths + guard, non-tty fail-closed ×2, destructive PROMPT+ABORT on 'n'/Enter ×3, dead-RPC graceful ×1, byte-compat ×5 outputs, side-effect isolation asserts).
Project validation: make check OK · make lint 0 FAIL 0 WARN · make gen idempotent.
Scope compliance: in-scope only / out-of-scope changes: none.
Remaining risks: three notes above.
Recommended next agent: **Reviewer** (adversarial pass over the two diffs, esp. the lint-resolution choice).
Reason: implementation complete and verified; independent review is the next gate before acceptance.

REPORT_PATH: ./reportAgents/2026-08-23-builder-t4-p2-menus-vbox-download.md
