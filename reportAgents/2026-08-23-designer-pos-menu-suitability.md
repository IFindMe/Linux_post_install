# Design Report — `pos` Tool Menu-Suitability Classification

> Provenance: Designer pass over `reportAgents/2026-08-23-explorer-pos-menu-survey.md` (sole evidence base, trusted per brief). Classification only — no implementation proposed here.

## TL;DR
- **37 tools classified: 14 MENU-FIT (6 need new work, 8 already menu'd) · 7 CONDITIONAL · 16 NO-FIT.**
- Headline: add opt-in no-args+tty menus to exactly **6 tools** — docker-compose, media-sync, system-backup, system-schedule (P1) and docker-vbox, network-download (P2).
- Everything new must follow Pattern A/B mechanics (stderr render + `/dev/tty` + fail-closed tty guard + subcommand bypass); **do not** grow `INTERACTIVE_CMDS` (E-002).
- Pivotal open decision before mass-building: generalize Pattern B out of `share-lib.sh` into a category-neutral menu library (flagged, not decided).
- system-firewall's legacy stdout-rendered menu is flagged for migration evaluation (debt a); usb-server E-004 stays owned by its track (classify only).
- Automation doors (entertainment timers, schedule timers, listener services) keep byte-identical invocations — none of the proposed menus touches them.

## Step 1: Classification criteria [DONE]

A tool gets an opt-in menu (no-args + tty front door, subcommand bypass) only if **at least one** benefit-criterion holds AND **none** of the blocker-criteria applies.

**Benefit criteria (menu adds value):**
- B1 — *Multi-step stateful workflow*: a session naturally chains related actions on the same objects (add→list→sync→remove; pick job→toggle→edit). Single verbs don't qualify.
- B2 — *Destructive or sensitive ops need guided confirms*: remove/reset/overwrite/restore flows gain from numbered pick + explicit confirm.
- B3 — *Discoverability debt*: verb surface too large to memorize (≥10 subcommands) and used intermittently.
- B4 — *Periodic manual chore*: recurring human-driven task where remembering exact syntax is friction.

**Blocker criteria (menu is wrong or harmful):**
- X1 — *Daemon/listener*: the front door IS the service lifecycle; self-installed units invoke it directly.
- X2 — *Pure one-shot read/compute* (dashboard, lookup, scan): consumed once by eyes or by scripts; exit-code contracts must stay clean.
- X3 — *Trivial single action*: one verb, no state; menu = pure indirection.
- X4 — *Terminal-handover nature*: core experience replaces the terminal (attached shell, GUI takeover).
- X5 — *Automation-coupled entry point*: timers/services call it with args — CLI-first is binding; any interactive surface may only be additive behind an explicit verb.
- X6 — *Pipe filter*: non-tty stdin behavior is a feature (`ai gemini ask`, mp3-style downloads) — untouched by verdicts here since Pattern A/B guards fail closed anyway.

**Verdicts:**
- **MENU-FIT** — meets B1–B4, no blocker → opt-in menu warranted (or already present).
- **CONDITIONAL** — partial benefit or existing UI covers it; build only on explicit user want, or as a bounded variant (watch-loop, hub item, debug verb).
- **NO-FIT** — blocker applies.

**Pattern choice rule:** prefer **B** when picker/probe infrastructure exists or multiple tools would share flows; prefer **A** for small self-contained tools; final call on new B-consumers is deferred to the library-generalization decision (Step 5b) — A is the safe default meanwhile.

## Step 2: THE TABLE — all 37 tools [DONE]

| # | Tool | Verdict | Pattern | Tier | Rationale |
|---|------|---------|---------|------|-----------|
| 1 | ai-gemini | NO-FIT | — | — | Interactive REPL already exists; `ask` must stay pipe-filterable; a menu adds indirection, not capability (X3/X6). |
| 2 | communication-matrix-listener | NO-FIT | — | — | Front door IS the daemon w/ self-installed service (X1); map-editor loop already covers its config UX. |
| 3 | communication-matrix-sender | NO-FIT | — | — | Single action + tty-safe login prompt already; nothing multi-step to guide (X3). |
| 4 | communication-scrcpy | NO-FIT | — | — | GUI/terminal handover by nature (X4); device-pick→mirror belongs in a `mirror --pick` flag someday, not a front door. |
| 5 | communication-telegram-listener | NO-FIT | — | — | Same as matrix-listener (X1). |
| 6 | communication-telegram-sender | NO-FIT | — | — | Single action; notify backend must stay instantly scriptable (X3/X5). |
| 7 | config | MENU-FIT (done) | bespoke | done | Already menu-first: `[ -t 0 ]` scope picker + `cfg_ui` editor loop — philosophically matches A/B; no work. |
| 8 | docker-compose | MENU-FIT | B (new consumer) | P1 | Stack lifecycle is multi-step + destructive (B1/B2); first-deploy prompts fold into the flow; EDITOR shell-out is modal-safe. |
| 9 | docker-health | CONDITIONAL | A-lite | P3 | Exit-1 script contract (X2); value only as a view inside a combined docker watch-loop. |
| 10 | docker-ps | CONDITIONAL | A-lite | P3 | Pure view (X2); only worth a refresh loop merged with stack/health views. |
| 11 | docker-stack | CONDITIONAL | A-lite | P3 | Same — one view of the hypothetical combined docker dashboard. |
| 12 | docker-vbox | MENU-FIT | A (embedded) | P2 | VM lifecycle with destructive rm benefits from pick+confirm (B1/B2); `enter` becomes a bounded handover that returns to menu. |
| 13 | entertainment-config | CONDITIONAL | B-ish | P2 | `cfg_ui` edit exists; a status/edit/enable-disable hub adds modest value (B1-lite); low effort if built. |
| 14 | entertainment-disable | NO-FIT | — | — | Trivial toggle (X3); candidate *item* inside an entertainment hub, not its own menu. |
| 15 | entertainment-enable | NO-FIT | — | — | Same (X3). |
| 16 | entertainment-send | CONDITIONAL | A-lite | P3 | Timer target — CLI-first binding (X5); at most an explicit-verb debug/preview (`--print`) menu, never the default door. |
| 17 | entertainment-status | NO-FIT | — | — | Trivial single view (X2/X3); belongs as a hub item at most. |
| 18 | media-mp3 | NO-FIT | — | — | Single-action downloader, commonly scripted; non-tty path must stay pristine (X3/X6). |
| 19 | media-mp4 | CONDITIONAL | A-lite | P3 | Format-select prompt already interactive; only a guided URL→format→repeat loop adds anything; tty-guard consistency fix worthwhile regardless. |
| 20 | media-sync | MENU-FIT | B (new consumer) | P1 | Periodic chore: pick USB root → preview → confirm (B4/B2); picker/mount-offer infra already in usb-lib. |
| 21 | media-ytsync | MENU-FIT (done) | A (reference) | done | Reference Pattern A implementation; zero work. |
| 22 | network-checkport | NO-FIT | — | — | Arg-driven one-shot probe (X2). |
| 23 | network-download | MENU-FIT | B (new consumer) | P2 | 24-subcmd queue control is memorization debt (B3); menu maps ~top verbs, probe-gated on daemon alive; tmux live view = handover item. |
| 24 | network-hotspot | CONDITIONAL | A-lite | P3 | No-arg already launches the GUI — that's its "menu" (X4-ish); a tty start/stop/status menu only if user prefers non-GUI. |
| 25 | network-ip | NO-FIT | — | — | One-shot lookup (X2). |
| 26 | network-scan | NO-FIT | — | — | One-shot compute requiring CIDR arg (X2). |
| 27 | share-nfs-client | MENU-FIT (done) | B | done | Pattern B consumer as-found. |
| 28 | share-nfs-server | MENU-FIT (done) | B | done | Pattern B consumer as-found. |
| 29 | share-smb-client | MENU-FIT (done) | B | done | Pattern B consumer as-found. |
| 30 | share-smb-server | MENU-FIT (done) | B (canonical) | done | Canonical consumption shape (`""|menu)` entry, smb-server:406–408). |
| 31 | share-usb-server | MENU-FIT (~done) | B | done* | ~Converted to share_pick layer; E-004 legacy `read -rp` fallbacks owned by another track — classify only, no work proposed. |
| 32 | ssh-load-keys | NO-FIT | — | — | Trivial single action paired with systemd unit (X3). |
| 33 | system-backup | MENU-FIT | B (new consumer) | P1 | Sensitive multi-step flow folder→target→passphrase (B1/B2/B4); restore-overwrite demands the strongest guided confirm. |
| 34 | system-firewall | MENU-FIT (done, legacy style) | legacy → A/B? | decision | Full menu already; stdout-rendered oldest style — migration evaluation is flagged decision (a), not scheduled work. |
| 35 | system-health | NO-FIT | — | — | Exit-1 scripting contract (X2); watch loops are `watch`'s job. |
| 36 | system-schedule | MENU-FIT | B-ish (new consumer) | P1 | Job CRUD editor already lib-based; menu adds list→run/toggle/edit/remove hub (B1/B2); timer invocations via `run <name>` untouched. |
| 37 | tree | NO-FIT | — | — | Pure reference output (X2). |

Counts: MENU-FIT 14 (6 new · 7 done · 1 decision-pending style) · CONDITIONAL 7 · NO-FIT 16 = **37** ✓

## Step 3: Global interaction contract for ALL new menus [DONE]

Non-negotiable mechanics every new menu must implement (extracted from Patterns A/B evidence):

1. **Front door:** zero args (and not a bypass flag like `--dry-run`) + tty → menu; any registered verb bypasses to direct execution. Subcommands stay 100% scriptable.
2. **Render to stderr, read `/dev/tty`:** menu UI never touches stdout; stdout stays clean under the dispatcher's `| tee` and inside `$( )`.
3. **Fail closed on non-tty:** guard prints one-line pointer to the scriptable subcommand and exits non-zero (ytsync `require_tty`, share_menu_guard semantics).
4. **EOF-safe reads:** every read checks EOF → "Cancelled" + safe abort. Menus must be cron/pipe-proof by construction.
5. **Do NOT add tools to `INTERACTIVE_CMDS`** — stderr+/dev/tty is sufficient and keeps logging for all non-menu paths (E-002).
6. **Destructive items confirm:** y/N minimum; repo-widest confirm (typed name) reserved for restore-overwrite.
7. **Loop discipline:** unknown/empty input redraws; `0/q/Q` exits; long streams (logs) quit back into the loop, never kill it.
8. **Automation invariance:** timer/service invocations (`pos entertainment send <plugin>`, `pos system schedule run <name>`, listener service units) remain byte-identical.
9. **Handover items** (`vbox enter`, tmux live view): run foreground, resume loop on exit — never `exec` from within the menu.

Accessibility (terminal UX): numbered linear text menus are keyboard-only and screen-reader/braille-friendly by nature — no cursor addressing, no arrow-key requirement, no timeouts on prompts; meaning never carried by color alone (symbols + labels); consistent quit key across all menus (`q`); destructive actions require explicit confirmation keystrokes. WCAG intent mapped to TUI: perceivable = plain-text render, operable = single-key input + visible options, robust = no terminal-emulator-specific escape sequences.

## Step 4: Per-tool menu sketches — MENU-FIT needing work [DONE]

### 4.1 docker-compose — Pattern B consumer · P1
- **Menu items:** pick stack (type-to-filter over discovered stacks) → `[u]p` / `[d]own` (confirm) / `[r]estart` (confirm) / `[l]ogs -f` (q returns) / `[U]pdate (pull+up)` (confirm) / `[c]onfig edit` (EDITOR, modal) / status summary · global: list all stacks w/ health · up-all / down-all (typed-stack-count confirm).
- **States:** no stacks found → empty-state hint pointing at init flow; daemon down → probe-gated offer; first deploy → existing TS_AUTHKEY prompt + "Edit .env before starting?" fold into `up` item flow.
- **Risks:** EDITOR shell-out blocks loop (acceptable, modal); `logs -f` needs explicit quit-to-loop contract; down-all is the widest blast radius — confirm must name affected stacks.

### 4.2 media-sync — Pattern B consumer · P1
- **Menu items:** run sync now (USB root picker → mount-offer → dry-run preview of copy/skip counts → confirm) · show pending changes (preview only) · mount/unmount helpers · set source/target paths (ask_value or cfg_ui).
- **States:** no USB device → offer mount/rescan; multiple devices → share_pick-style chooser; sync running → block re-entry.
- **Risks:** mount ops may need polkit/sudo (surface error inline); device unplug mid-flow → EOF-safe abort mandatory.

### 4.3 system-backup — Pattern B consumer · P1
- **Menu items:** new snapshot (folder picker → target/USB picker → passphrase prompt via /dev/tty, hidden) · restore (pick snapshot → pick destination → **typed-name confirm**) · list snapshots + age vs. policy · install `--service` timer flow (existing folder picker).
- **States:** no snapshots → empty-state straight to new-snapshot (Pattern A empty-state convention); gpg missing → deps-guard error as today.
- **Risks:** passphrase handling — never argv/env-echo, read tty only; restore overwrite is the most destructive op in the suite → strongest confirm in repo; long-running ops should stream progress to stderr.

### 4.4 system-schedule — B-ish consumer (its editor lib already shared) · P1
- **Menu items:** list jobs (name · schedule · enabled · next-run · notify policy) · pick job → run now / toggle enable / edit (existing sched_config_editor flow) / remove (confirm) · add job (wizard) · open full config editor.
- **States:** no jobs → empty-state straight to add wizard; job run-now shows notify outcome inline.
- **Risks:** timers invoke `schedule run <name>` — verb dispatch untouched; menu mutations MUST go through the same write path as subcmds (single source of truth, no parallel state writes); avoid re-syncing timers twice per mutation.

### 4.5 docker-vbox — Pattern A embedded · P2
- **Menu items:** create VM (name/image prompts) · pick VM → start / stop / enter (**foreground handover, returns to menu on shell exit**) / rm (confirm + red warning) · list VMs with state.
- **States:** no VMs → empty-state straight to create-flow (Pattern A convention); image pull progress to stderr.
- **Risks:** tool is INTERACTIVE_CMDS-member (bare exec path) — fine, but `enter` must call docker attach in foreground rather than exec-replacing the process so the loop survives; rm destroys disk data → explicit confirm wording.

### 4.6 network-download — Pattern B consumer (probe-gated) · P2
- **Menu items:** daemon: status / start / stop / live view (`--tmux`, handover item) · queue: add URI/magnet (ask_value) · list queue w/ progress · pause-all / resume-all · purge finished (confirm).
- **States:** daemon dead → fail soft: menu still opens with "start daemon?" offer (probe pattern à la share_service_active); aria2 secret token read via ask_value if configured unset.
- **Risks:** only ~8 of 24 subcmds get menu mapping by design — power verbs stay CLI-only; tmux view is a handover (contract rule 9).

### Done register (no sketches — already implemented)
- **media-ytsync** — Pattern A reference implementation; future menus copy its empty-state + remove-flow conventions.
- **share nfs-client/nfs-server/smb-client/smb-server** — canonical Pattern B consumption; smb-server is the shape template.
- **share-usb-server** — ~converted; E-004 legacy fallbacks owned elsewhere. No design work proposed.
- **config** — bespoke menu-first UI (scope picker + cfg_ui); would *consume* a generalized menu lib if decision 5b lands, but has no gap today.
- **system-firewall** — functionally complete menu; style debt handled in Step 5a, not here.

## Step 5: Flagged decisions (NOT decided here — no implementation proposed) [DONE]

### 5a. system-firewall legacy menu style (debt a)
- **Fact:** firewall renders its menu to **stdout** with per-command confirms and an Enter-pager (firewall:243–308) — the oldest style, predating A/B. It breaks under stdout redirection/`$( )` capture and lacks the EOF-safe `/dev/tty` discipline.
- **Candidate:** migrate to A/B mechanics (stderr render + /dev/tty + fail-closed guard), keeping its item set and root-gate behavior identical.
- **Trade-offs to weigh:** uniformity + redirection-safety vs. rewriting a working, root-gated TUI that users may have muscle memory for.
- **Decision owner:** Architect/user (mechanics + sequencing). **Designer recommendation only:** migrate *after* the P1 menus land and after 5b is resolved, so it can adopt the same library if one exists.

### 5b. Generalize Pattern B into a shared menu library (debt b)
- **Fact:** Pattern B lives in `lib/share-lib.sh` but `share_menu_guard / share_menu_run / share_pick / share_ask_value` (+ probe helpers) are category-generic in everything but name.
- **Open architectural question:** extract a neutral `lib/menu-lib.sh` (renamed primitives + thin `share_*` compat shims for the 5 existing consumers), or leave share-local and have new tools embed Pattern A instead.
- **Impact:** decides the implementation shape of all six new menus in Step 4 (B-consumer sketches assume extraction; A fallback is always viable).
- **Decision owner:** Architect + user. **Designer recommendation:** extract — 6 new consumers + 5 existing = 11 tools sharing one interaction vocabulary; naming debt compounds otherwise.

### 5c. usb-server E-004 mid-migration state
- Owned by another track. Classified MENU-FIT (~done). **No work proposed from this report.**

### 5d. Conditional-tier activations (explicit user want required)
- Combined docker watch-loop (ps+stack+health views) · entertainment-config hub · media-mp4 guided loop · network-hotspot tty menu · entertainment-send debug/preview verb-menu · ai-gemini no-arg→`chat` routing nicety. None scheduled.

## Step 6: Phased rollout [DONE]

| Phase | Scope | Rough effort | Gate |
|---|---|---|---|
| 0 — Decision gate | Resolve 5b (library generalization); stance on 5a | discussion only | before any build |
| 1 — P1 menus | media-sync → system-backup → docker-compose → system-schedule (order: smallest first as pattern proof) | ~0.5–1 day each; B-consumer wiring ≈ smb-server shape (~30 lines of loop/mapping) once library exists | 5b resolved |
| 2 — P2 + migrations | docker-vbox, network-download; execute 5a firewall migration per decision outcome | ~0.5 day each + migration session | Phase 1 shipped |
| 3 — Conditionals (on request only) | items in 5d list | small, ad hoc | explicit user ask |
| Untouched forever | listeners ×2, senders ×2, scrcpy, ai-gemini REPL/ask, mp3, tree, one-shot network lookups, ssh-load-keys, enable/disable toggles, entertainment-status standalone, all pipe-filter non-tty paths, automation door invocations | — | — |

Per-phase definition of done follows repo gates: `make gen` (if headers change) → `make check` → `make lint`, plus manual non-tty regression (`tool < /dev/null`, `tool \| cat`) proving fail-closed guards.

## Step 7: Handoff [DONE]

Status: DESIGN_PROVISIONAL — classification complete; two style-debt decisions (5a, 5b) intentionally open and gated on Architect/user before implementation.

Recommended next agent: **Orchestrator** — table 5b/5a decisions with user; then Builder for Phase 1 against this spec.

REPORT_PATH: ./reportAgents/2026-08-23-designer-pos-menu-suitability.md
