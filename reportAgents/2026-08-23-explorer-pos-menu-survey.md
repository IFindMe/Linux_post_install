# Exploration Report — `pos` CLI Tool Interaction-Model Survey

> Provenance note: written by Orchestrator on behalf of Explorer, whose sandbox denied all file writes. Content is the Explorer's inline delivery, verbatim.

## TL;DR
- 37 tools inventoried. Interaction models: **full looping menu 8** (system-firewall; share×5; media-ytsync; config), **REPL/chat 1** (ai-gemini `chat`), **long-running listener 2**, **flags+prompts 6**, **subcmds+opt-in-editor 2** (system-schedule, entertainment-config), **pure-output dashboard 9**, **flags/subcmds-only 9**.
- Two reusable menu precedents confirmed with line refs: Pattern A (ytsync embedded) and Pattern B (lib/share-lib.sh, consumed by all 5 share tools).
- Key mechanic: both patterns render menus to **stderr** and read **/dev/tty**, so they work even though their tools are *not* in `INTERACTIVE_CMDS` (`bin/pos:262`) and run under the dispatcher's `| tee` (`bin/pos:286`). Membership in `INTERACTIVE_CMDS` (bare `exec`, :283) is the alternative escape hatch.
- `pos-share-usb-server` is a mid-migration hybrid as-found (uncommitted WIP): new `share_pick` menu layer with legacy `read -rp` fallbacks still present.
- No pos tool shells out to another pos tool; automation coupling is systemd **user timers** (→ `pos-entertainment-send`, `pos system schedule run`), listeners' self-installed user services, and outbound `notify_send` fan-out via `lib/notify.sh`.

## Step 1: Dispatcher mechanics (context for feasibility)
[DONE]
- `bin/pos:262` — `INTERACTIVE_CMDS` lists 18 stdin-readers; they are `exec`'d without logging (:280–283). All others run as `tool 2>&1 | tee $LOG_FILE` (:286–289) — tool **stdin is still the caller's tty**; only stdout is piped. So prompts technically work in tee'd mode, but stdout is non-tty (colors auto-off, `[ -t 1 ]` checks fail) and AGENTS.md documents prompt-hang/swallow risk as the reason for the list.
- Longest-prefix dispatch: `pos media ytsync` (no verb) resolves to `pos-media-ytsync` with zero args → its menu front door (:264–291).

## Step 2: Per-tool evidence table (all 37)
Legend — Model: MENU=looping menu · PROMPTS=flags+conditional prompts · DASH=pure-output dashboard · ACTION=flags/subcmds-only · REPL · LISTENER · HYBRID=subcmds+editor. IC = listed in `INTERACTIVE_CMDS` (`bin/pos:262`).

| Tool | Purpose (`# POS:` bin/*:3) | Model | Stdin/tty | IC | Automation coupling | Prompts/menus (lines) | Menu feasibility (no-args+tty) |
|---|---|---|---|---|---|---|---|
| ai-gemini | Chat with Google Gemini (ask, chat, models, sessions) | REPL + ACTION (`ask`) | chat loop reads stdin :199; `ask` reads stdin pipe when `[ ! -t 0 ]` :163 | yes | none found | chat REPL :184–219; `/reset`, q handlers :200–207 | REPL already exists; `ask` must stay pipe-filterable |
| communication-matrix-listener | Matrix listener: /command → bash on room messages | LISTENER | daemon loop; map-editor menu reads stdin | yes | self-installs user service `systemctl --user enable --now` :348 | map editor loop `[a]dd [e]dit [r]emove [t]est` :300; entry prompts :190–271 | menu around config/edit only; listening itself is the daemon |
| communication-matrix-sender | Send Matrix room messages (send, test, login) | ACTION+PROMPTS | password `read -rsp </dev/tty` :167 | no | target of notify fan-out (lib/notify.sh) | login password prompt :167 | feasible; single prompt already tty-safe |
| communication-scrcpy | Mirror/control Android via scrcpy+adb (9 subcmds) | ACTION | no prompts; `mirror` runs foreground GUI proc | no | none | none | feasible; menu item replaces terminal until mirror exits |
| communication-telegram-listener | Telegram bot listener: /command → bash | LISTENER | same as matrix-listener | yes | self-installs user service :385 | map editor loop :337; prompts :221–308 | same as matrix-listener |
| communication-telegram-sender | Send Telegram messages/files via Bot API (send, test) | ACTION | none | no | notify backend for notify_send | none | feasible |
| config | Interactive editor for runtime config (POS_CONFIG registry) | MENU+EDITOR | requires `[ -t 0 ]` for no-arg picker :69, else usage | yes | none | scope picker :42–66; `cfg_ui` editor loop (lib/config-ui.sh:298) | already menu-first |
| docker-compose | Compose service manager (ls/up/down/restart/logs/update/config) | PROMPTS | TS_AUTHKEY prompt :204; EDITOR confirm :210 | yes | manages external compose stacks; `config edit` opens `${EDITOR:-nano}` :333–334 | authkey :201–208; nano :210–213 | feasible; prompts only on first deploy |
| docker-health | Container health dashboard (exit 1 unhealthy) | DASH | none | no | none | none | trivial wrap |
| docker-ps | Enhanced container overview | DASH | none | no | none | none | trivial wrap |
| docker-stack | Containers grouped by compose stack | DASH | none | no | none | none | trivial wrap |
| docker-vbox | Disposable Docker VMs (create/enter/start/stop/rm/ls) | ACTION | `enter` execs interactive shell `docker exec -it … bash` :107/127/129 | yes (shell attach consumes stdin) | none | none (shell is the interactivity) | feasible; `enter` item hands over terminal |
| entertainment-config | Show/edit entertainment config (ENABLED, weather keys) | HYBRID | `edit` → cfg_ui; default no-arg just cats config :129–134 | yes | writes config consumed by timers/plugins | `edit` → `cfg_ui entertainment` :96–100; scripted `set/get/unset/ls` :68–128 | partially menu'd already |
| entertainment-disable | Disable plugin auto-trigger | ACTION | none | no | triggers timer re-sync (sync_timers, lib/entertainment-lib.sh:225) | none | trivial wrap |
| entertainment-enable | Enable plugin auto-trigger on schedule | ACTION | none | no | same — writes ENABLED, sync_timers | none | trivial wrap |
| entertainment-send | Run plugin, send output via notify platforms | ACTION | none (`--print` local preview) | no | **invoked by systemd user timers**: runner resolved `command -v pos-entertainment-send`, unit pair ExecStart `pos entertainment send $plugin` (lib/entertainment-lib.sh:255–259) | none | feasible wrapper, but must not become default front-door (timers depend on direct CLI) |
| entertainment-status | Show enabled plugins + scheduler state | DASH | none | no | reads last-run state written by send (save_last_run lib:292) | none | trivial wrap |
| media-mp3 | Download audio as MP3 (yt-dlp) | ACTION | none | no | none | none | feasible |
| media-mp4 | Download video as MP4 (smart/interactive format select) | PROMPTS | format prompt reads stdin :104 | yes (prompt swallows under tee) | none | curated format table → prompt :92–117; skipped if `--format/--best/--worst` :85–90 | already half-interactive; needs tty-guard like ytsync |
| media-sync | Incremental Music→USB sync | PROMPTS | `usb_pick_root` picker/mount-offer :89 (lib/usb-lib.sh:86/145) | yes | none | USB pick flow :89–93 | feasible; picker infra exists |
| media-ytsync | Incremental YouTube channel/playlist sync into ~/Videos | MENU | `require_tty` gates menu :792–798; all prompts `</dev/tty` :761/819/1074/1090/1129 | **no** (by design; stderr+/dev/tty make it tee-safe) | none found (manual `sync` is the unattended path) | `menu_render` :1040–1056; `interactive_menu` :1119–1153; remove flow :1058–1108; empty-state :1110–1117; dispatch no-arg→menu :1176–1183 | **reference implementation** (Pattern A) |
| network-checkport | TCP/UDP port reachability + interface view | DASH | none | no | none | none | trivial wrap |
| network-download | aria2 RPC daemon + queue control (24 subcmds) | ACTION | none | no | controls external aria2 daemon; usage shows `--tmux` live view (bin/pos:145) | none | feasible; daemon does the work |
| network-hotspot | Wi-Fi hotspot via create_ap + wihotspot-gui | PROMPTS | bg y/N prompt :53; no-arg `exec wihotspot-gui` GUI :42 | yes | none | GUI launch :42; background prompt :52–58 | partial; no-arg already launches a GUI "menu" |
| network-ip | Interfaces, routes, public IP + location | DASH | none | no | none | none | trivial wrap |
| network-scan | Parallel ping sweep of CIDR | DASH | none (`-t 0` at :90 only tests sudo-ask feasibility) | no | none | none | trivial wrap |
| share-nfs-client | Mount NFS shares (ephemeral/systemd persist) | MENU+PROMPTS | share-lib guards/pickers (stdin tty required) | yes | none | `run_menu` :292; picks/prompts :195–282 | **done** (Pattern B consumer) |
| share-nfs-server | Manage NFS kernel server | MENU+PROMPTS | same | yes | none | `run_menu` :207; picks :154–197 | done |
| share-smb-client | Mount SMB/CIFS shares | MENU+PROMPTS | password `<"$pw_in"` (/dev/tty default) :125–126; user prompt :468 | yes | none | `run_menu` :531; picks :439–521 | done |
| share-smb-server | Manage Samba server | MENU+PROMPTS | share-lib | yes | none | `run_menu` :378–404 (entry `""|menu)` :406–408); picks :310–372 | done |
| share-usb-server | USB Redirector server control (--ls, --share; prompts when args omitted) | MENU+PROMPTS (hybrid, WIP tree) | share-lib guards + legacy raw prompts | yes | none | new menu layer `menu_pick_from_records` :196–213, menu fns :215–306, `share_menu_run` :306; **legacy** arg-omitted `read -rp` fallbacks :69–182 | mostly done; legacy prompts coexist (see E-004) |
| ssh-load-keys | Load all SSH keys into agent | ACTION | none | no | pairs with systemd/ssh-agent.service (socket at /run/ssh-agent) | none | trivial wrap |
| system-backup | Encrypted AES-256 folder snapshots | PROMPTS | `--service` folder pick :143–158; usb pick via usb-lib | yes | none | folder picker :132–158; `err` if no folder/--service :123 | feasible; pickers exist |
| system-firewall | Interactive UFW management | MENU | every action prompts; root-required gate :6–10 | yes | notify_send on mutating cmds :53 | main loop :243–308; per-cmd confirm :45; RESET confirm :270; Enter-pager :306 | **already full TUI** (oldest style; stdout-rendered, unlike A/B) |
| system-health | Host health dashboard (exit 1 on FAIL) | DASH | none | no | checks backup age state (not invocation) | none | trivial wrap |
| system-schedule | Scheduled jobs on timers with notify policies | HYBRID | `config` editor reads stdin (sched_config_editor lib/scheduler-lib.sh:639, add/edit/remove/toggle :669–746) | yes | **timers invoke `pos system schedule run <name>`**: `ut_write_unit_pair … "$SCHED_RUNNER run $name"` lib:379–384 | `config` → interactive editor :75→lib:639 | partially menu'd; rest is clean subcmds |
| tree | Show pos CLI command tree | DASH | none | no | none | none | trivial wrap |

Counts: MENU 8 · REPL 1 · LISTENER 2 · PROMPTS 6 (matrix-sender, scrcpy*, compose, mp4, sync, backup, hotspot — scrcpy/hotspot borderline; see cells) · HYBRID-editor 2 · DASH 9 · ACTION 9 = **37**.

## Step 3: Pattern extractions
[DONE]

### Pattern A — ytsync embedded menu (self-contained, per-tool)
- `require_tty()` — `pos-media-ytsync:792–798`: fails closed with pointer to unattended subcommand when `[ ! -t 0 ]`.
- `menu_render()` — :1040–1056: box title + numbered items + separator, rendered **to stderr** (`} >&2`) so stdout stays clean and tee can't swallow it.
- `interactive_menu()` — :1119–1153: tty gate → empty-state short-circuit (:1121–1124, zero sources → straight to add-flow) → redraw loop, unknown/empty input redraws, `0/q/Q` exits.
- `menu_remove_flow()` — :1058–1108 and other flows: numbered pick + explicit y/N confirm; every `read … </dev/tty` is EOF-checked ("Cancelled" on failure) — safe under pipes/cron.
- Dispatch contract — :1176–1191: no args (and not `--dry-run`) → menu; any verb (`add/sync/list/remove`) bypasses. Subcommands registered via `# POS_SUBCMDS:` (line 4).
- Deliberately **not** in `INTERACTIVE_CMDS`; works under the dispatcher's tee because menu goes to stderr and input comes from /dev/tty.

### Pattern B — lib/share-lib.sh shared menu library (uncommitted WIP; as-found)
Consumed by all 5 share tools via `source …/lib/share-lib.sh` (e.g. pos-share-smb-server:8). Helper inventory:
- `share_menu_guard` :38–44 — rc 0 iff stdin is tty, else warn "use a subcommand" + rc 1 (tools `exit 1` on it, e.g. smb-server:379).
- `share_menu_run <title> <items…>` :46–80 — looping boxed menu; items→stderr, **chosen index→stdout**; EOF/quit→rc 1; empty input redraws.
- `share_pick <prompt> <items…>` :88–145 — type-to-filter numbered picker (case-insensitive substring, `/` clears, match-count banner); index→stdout; EOF/back→rc 1; own non-tty guard.
- `share_ask_value <label> [default]` :151–163 — prompt-with-default; value→stdout; EOF/empty-no-default→rc 1.
- Probes/data providers feeding the pickers: `share_require_bin` :169, `share_port_probe` :176, `share_service_active` :182, `share_path_probe` :193, `share_ufw_blocks_ports` :202, `share_offer_fix` :218, `share_nfs_exports` :241, `share_smb_shares` :269, `share_usb_records` :329, `share_usb_devices` :351, `share_usb_clients` :369, `share_folder_candidates` :393.
- Consumption shape (identical ×5): `case ""|menu) run_menu` (smb-server:406–408) → `while` loop around `share_menu_run` mapping index→`cmd_*`; every subcommand remains fully scriptable outside the menu. usb-server adds `menu_pick_from_records` (:196–213, share_pick + legacy `read -rp` manual fallback) — see E-004.

## Step 4: Other prompt-like behavior (downstream notes)
[DONE]
- hotspot: no-args launches GUI (`exec wihotspot-gui`, :42); `start` without `--foreground` prompts "Run in background? [y/N]" (:53).
- usb-server: header itself documents "prompts when args omitted" — raw `read -rp` chains in cmd fallbacks (:69–182).
- ai-gemini: `chat` REPL (:184–219); `ask` doubles as pipe filter (`[ ! -t 0 ]` → read stdin, :163–165).
- config editors: `cfg_ui` (lib/config-ui.sh:298) drives `pos config` and `pos entertainment config edit`; rules "Enter keeps, `-` clears, q quits" (pos-config:32–33).
- system-schedule `config` → `sched_config_editor` (lib/scheduler-lib.sh:639; add/edit/remove/toggle :669–746).
- docker-compose `up`: first-deploy TS_AUTHKEY prompt (:201–208) + "Edit .env before starting?" → `${EDITOR:-nano}` (:210–213); `config edit` opens `$EDITOR` (:333–334). Only tool shelling to `$EDITOR` (grep: 4 hits, all here).
- Password prompts deliberately read `/dev/tty`: matrix-sender login (:167), smb-client (`SMB_PW_FILE` override, :125–126).
- firewall: oldest style — stdout-rendered menu, confirm-per-command, typed `RESET` gate, Enter-pager (:45, :270, :306).

## Step 5: Findings
[E-001] Type: architecture. Classification: FACT. Two competing menu styles coexist: stdout-rendered firewall menu (pos-system-firewall:243–260) vs stderr-rendered + `/dev/tty` input patterns A/B. Only the latter survives stdout redirection and `$( )` capture; share-lib comment calls firewall "precedent" (lib/share-lib.sh:31), showing evolution. Confidence: high.
[E-002] Type: mechanism. Classification: FACT. `INTERACTIVE_CMDS` (`bin/pos:262`) selects bare `exec` (:283) vs `| tee` (:286). ytsync + share suite are NOT members yet are fully interactive — stderr rendering + /dev/tty reads are sufficient; membership is not the only escape hatch. Confidence: high.
[E-003] Type: coupling. Classification: FACT (timer targets) / INFERENCE (exact `SCHED_RUNNER` value). Automation enters only 3 doors: systemd user timers → `pos-entertainment-send <plugin>` (entertainment-lib.sh:255–259); user timers → `pos system schedule run <name>` (scheduler-lib.sh:379–384); listeners self-install user services (telegram:385, matrix:348). Repo-static units (systemd/*.service) reference autostart.sh/ssh-agent/usb-automount.sh, not pos tools. No tool-to-tool subprocess calls found. Confidence: high.
[E-004] Type: convention drift (expected — flagged WIP). Classification: FACT. pos-share-usb-server working tree mixes new share_pick menu layer (:196–306) with pre-existing raw `read -rp` fallback prompts (:69–182); siblings (smb/nfs server/client) are fully converted. Describe, don't touch (other track owns it). Confidence: high.
[E-005] Type: feasibility blocker inventory. Classification: FACT. Hard blockers for a naive no-args+tty menu: none library-wise; situational ones: listeners (front-door IS the daemon), `docker vbox enter`/scrcpy `mirror` (replace terminal with attached shell/GUI), `ai gemini ask`/`mp3`-style pipe filters must keep non-tty behavior, root requirement (firewall:6). Everything else is wrap-or-wire. Confidence: high.

## Step 6: Uncertainties
- Exact value of `SCHED_RUNNER` constant not read (inferred `pos-system-schedule` from unit description string lib:382) — one-line check in scheduler-lib.sh head.
- Runtime behavior of tee'd prompts under cron/non-tty parents not executed (read-only mandate); established statically only.
- DOC/HOWTO "docs-as-scriptable" mentions not audited (effort cap); POS.md coverage assumed per lint gate.
- Sandbox denied all file writes (including `AgentsReport/**`), so no report file exists on disk — this message is the sole deliverable copy.

## Step 7: Important files
- `bin/pos` :262–290 — dispatch split INTERACTIVE vs tee (governs every feasibility answer)
- `bin/pos-media-ytsync` :792–798, :1040–1153, :1176–1191 — Pattern A
- `lib/share-lib.sh` :31–163 (+probes to :436) — Pattern B
- `bin/pos-share-smb-server` :378–408 — canonical Pattern B consumption
- `lib/config-ui.sh` :298 (`cfg_ui`) — existing generic editor loop reused by 2 tools
- `lib/entertainment-lib.sh` :225–301, `lib/scheduler-lib.sh` :362–407, :639–746 — timer coupling + schedule editor
- `lib/usb-lib.sh` :86/:145 — existing pick/mount-offer flow reused by backup + media-sync

## Step 8: Handoff
Status: COMPLETE. Objective met: all 37 tools profiled with evidence; both menu patterns extracted; feasibility signals recorded as facts, no recommendations made.
Recommended next agent: **Designer** — classification of which tools fit an opt-in menu path is now a pure decision task over this table. Secondary: **Builder** (only if the designer opts to finish the usb-server conversion, E-004) and note for any implementer: new menus should follow Pattern A/B mechanics (stderr render + /dev/tty + require-tty guard + subcommand bypass) rather than `INTERACTIVE_CMDS` membership, per E-001/E-002 evidence.

REPORT_PATH: ./reportAgents/2026-08-23-explorer-pos-menu-survey.md
