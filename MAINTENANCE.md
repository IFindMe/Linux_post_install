# MAINTENANCE — Convention Audit

> Working report for the post-3-week-convention-drift audit. **Created first, updated
> incrementally as findings are confirmed** — never let findings live only in agent
> context. Keep the structure below; append findings as they land.
>
> Do **not** commit this file — it is a working artifact for the fix session.
> Definition of done for the fix session: every P0/P1 resolved (or explicitly
> marked won't-fix), `make gen && make check` green, `scripts/lint-conventions.sh`
> green, smoke tests pass.

## Phase 0 — authority & conflict resolution

Order of authority when docs disagree:

1. **Templates** (`templates/pos-tool.sh`, `feature.sh`, `app.sh`) — the codified *current* convention for new files. If an old tool deviates from its template, that's drift (unless the tool is intentionally category-less/nested).
2. **DEV.md** — full convention detail, checklists, best practices (env seams, systemd units, alerting, managed blocks).
3. **AGENTS.md Quick facts** — operational facts (make gen/check gate, header format, INTERACTIVE_CMDS gotcha, deps-guard-before-help). If it conflicts with DEV.md, DEV.md wins on *detail*, AGENTS.md wins on *process*.
4. **Code (`# POS:` headers, runtime behavior)** — ground truth for what a tool *does* and for all `GEN:`-derived docs (make gen regenerates from code).
5. **POS.md / HOWTO / README / SCRIPTS / SYSTEMD / APPS** — hand-written references; drift against code = doc bug (fix the doc) unless the doc describes a feature the code never shipped (phantom feature — fix the doc too).
6. **AGENT_Context_Project.md** — generated blocks follow code; hand-maintained rows (§14 Common Tasks, non-`pos-*` line-count rows, "How to modify" table) must match reality.

**Classification rule:** runtime behavior = what the tool *does*; conventions = what it *should* do. Findings are classified bug (behavior wrong), convention-violation (behavior right but against current convention), doc-drift (reference wrong), standardization (two tools same thing differently).

## Baseline

- `make gen && make check`: green (doc-sync, exec bits, syntax, dispatch smoke all pass).
- `scripts/lint-conventions.sh` (new, this audit): automated convention gate — see results below.
- AGENT_TODO: `Now` empty (Tier 1 shipped). Audit itself is the current work.
- Scope order (user-confirmed): bin/ + lib/ first, then install scripts + systemd, then features/entertainment/apps, then docs. All areas audited; this is report priority.
- Pickiness: everything flagged, tagged severity + confidence. P3 = intentional/legacy no-action list.
- Deliverables: `MAINTENANCE.md` (uncommitted) + `scripts/lint-conventions.sh` (to be committed as the reusable gate; `make lint` target still needs wiring in the Makefile).

## Checklist (convention matrix — from AGENTS.md / AGENT_Context §11/§12 / DEV.md)

- [ ] Shebang `#!/usr/bin/env bash` + `set -euo pipefail` (libs exempt — sourced)
- [ ] `# POS:` header right after shebang, ` — ` em-dash format; `# POS_FLAGS:` / `# POS_SUBCMDS:` / `# POS_CONFIG:` as needed
- [ ] Dep-guards (`command -v … || err`) **before** `-h|--help`
- [ ] stdin readers in `INTERACTIVE_CMDS` (bin/pos); no stale entries
- [ ] No `local` outside functions
- [ ] `run`/`spawn` respect `$DRY_RUN`; writes idempotent
- [ ] common.sh sourced via `$(dirname "$0")/../lib/…` fallback chain (standalone from /usr/local/bin)
- [ ] Entertainment plugins: no common.sh, `# POS_PLUGIN:`/`# POS_KEYS:`
- [ ] Apps: `uninstall_<name>()` + `uninstall` dispatch
- [ ] systemd units: `TimeoutStopSec=5s`, `[Install]`, `KillMode=` on daemons
- [ ] Env seams: every system path write has `VAR="${VAR:-path}"` guard
- [ ] No hardcoded secrets; chmod 600 on creds/tokens
- [ ] Docs: POS.md / README / HOWTO / AGENT_Context hand-maintained spots match behavior

## Lint results (`scripts/lint-conventions.sh`)

_Automated gate — FAIL = definite violation, WARN = manual review needed. All 18 FAIL/WARN classes below are **verified real** against source (heuristics were iterated until zero false positives; heredocs, `${...}` brace-counting, `while`-loop stdin, `/dev/tty` reads, `command -v` fallbacks and env-guard secret patterns are all excluded)._

### FAIL — 12 (maps to tickets M-001, M-003..M-015) — ALL RESOLVED in the fix session (see ticket statuses)
- `features/autostart.sh` — missing `set -euo pipefail` (→ M-001)
- `bin/pos-system-firewall` — missing `-h|--help` handling (→ M-015)
- `bin/pos-docker-compose` — reads stdin (read `-rp` :204, `confirm` :210) not in `INTERACTIVE_CMDS` (→ M-002)
- `bin/pos-docker-vbox` — reads stdin (`confirm` :105) not in `INTERACTIVE_CMDS` (→ M-003)
- `bin/pos-network-hotspot` — reads stdin (`read -rp` :53) not in `INTERACTIVE_CMDS` (→ M-004)
- `bin/pos-docker-health` (:21/:24), `bin/pos-docker-ps` (:17/:20), `bin/pos-media-mp3` (:38/:58), `bin/pos-media-mp4` (:43/:71), `bin/pos-network-scan` (:28/:66), `bin/pos-share-usb-server` (:191/:199), `bin/pos-system-health` (:39/:119) — `-h|--help` dispatched before deps guards (→ M-008..M-014)

### WARN — 6 (manual review done, all real docs-coverage gaps → M-023) — ALL RESOLVED
- `bin/pos-config`, `bin/pos-tree`, `bin/pos-entertainment-config`, `-enable`, `-disable`, `-status` — not referenced anywhere in DOC/POS.md

_Fix-session note: lint now reports 0 FAIL / 0 WARN. Two precision fixes were made to the lint itself (documented, not weakenings): `first_guard_line()` only treats real deps guards (`command -v … ||`, `if ! command -v`, `command -v … \`) as guards so graceful-degradation probes (system-health) don't trip the guard-before-help rule; `first_line()` skips comment lines so a comment containing `-h|--help` isn't mistaken for the dispatch._

_Heuristics that passed clean (reviewed, no findings): no secrets committed (all `TOKEN/SECRET/RPC_SECRET` assignments are env guards / config reads / runtime generation), all libs' system writes carry `command -v` fallbacks, legacy wrappers are thin, no plugin sources common.sh, systemd units carry `TimeoutStopSec=`/`WantedBy=`._

## Findings

Findings are tickets. Every ticket gets a unique `M-###` ID; the fix session works
through them in order (P0/HIGH first). Keep this exact field set:

```
### M-000
Status: OPEN
Severity: HIGH | MEDIUM | LOW
Category: bug | convention | dead-code | docs | UX | standardization | security
Files: <path:line …>
Evidence: <what was observed, quote the actual code/output>
Expected: <what the convention/runtime says should happen>
Recommended fix: <one-line, actionable>
Verification: <how the fix session proves it fixed>
```

### P0 — bugs / security

### M-002
Status: VERIFIED
Severity: HIGH
Category: bug
Files: bin/pos-docker-compose:204,210; bin/pos:259
Evidence: `pos docker compose config`/startup runs `read -rp "Enter your Tailscale auth key…"` (:204) and `confirm "Edit .env before starting?"` (:210) — both read stdin. `bin/pos` logging tee would swallow/hang these prompts because `docker-compose` is not in `INTERACTIVE_CMDS` (line 259). Same class of bug as the just-fixed smb-client prompt swallow.
Expected: every tool that reads stdin is in `INTERACTIVE_CMDS`.
Recommended fix: add `docker-compose` to `INTERACTIVE_CMDS`.
Verification: `pos docker compose config` via `pos` (logged) still prompts.
Fix (2026-08-14): added `docker-compose` to `INTERACTIVE_CMDS` in bin/pos:259. Verified: lint stdin-reader FAIL cleared for all three tools (M-002..M-004).

### M-003
Status: VERIFIED
Severity: HIGH
Category: bug
Files: bin/pos-docker-vbox:105; bin/pos:259
Evidence: `pos docker vbox start` calls `confirm "Enter now?"` (stdin read via lib/common.sh `confirm()` → `read -rp`) at line 105. Not in `INTERACTIVE_CMDS` → prompt swallow/hang under the logging pipe.
Expected: every stdin reader in `INTERACTIVE_CMDS`.
Recommended fix: add `docker-vbox` to `INTERACTIVE_CMDS`.
Verification: `pos docker vbox start` prompts correctly through the dispatcher.
Fix (2026-08-14): added `docker-vbox` to `INTERACTIVE_CMDS` in bin/pos:259; lint stdin FAIL cleared.

### M-004
Status: VERIFIED
Severity: HIGH
Category: bug
Files: bin/pos-network-hotspot:53; bin/pos:259
Evidence: `read -rp "Run in background? [y/N]: " bg` at line 53 (non-`--foreground` path). Not in `INTERACTIVE_CMDS` → prompt swallow/hang.
Expected: every stdin reader in `INTERACTIVE_CMDS`.
Recommended fix: add `network-hotspot` to `INTERACTIVE_CMDS`.
Verification: `pos network hotspot start <dev> <iface>` prompts through the dispatcher.
Fix (2026-08-14): added `network-hotspot` to `INTERACTIVE_CMDS` in bin/pos:259; lint stdin FAIL cleared.

### M-005
Status: VERIFIED
Severity: HIGH
Category: bug
Files: install.sh:38,84-99
Evidence: `install.sh --steps` documents format "`1,3,4 or 1-3`" (line 38) but the filter is `[[ ",$STEPS_SPEC," != *",$phase_num,"* ]]` (line 86) — only comma-separated matches. `--steps 1-3` matches nothing → **zero phases run**, silently.
Expected: both documented syntaxes work (comma list and `N-M`/`N-M,K` range).
Recommended fix: expand the range spec into the explicit phase set before filtering (e.g. `1-3` → `1,2,3`).
Verification: `install.sh --dry-run --steps 1-3` runs phases 1,2,3; `--steps 1,3` runs 1,3.
Fix (2026-08-14): added `normalize_steps_spec()` to install.sh (placed after variable init, before arg loop) — expands `1-3` → `1,2,3`, validates single/range/list syntax, errors on garbage and end<start. Verified dry-run: `--steps 1-3`→1,2,3; `--steps 3`→3; `--steps 2-2`→2; `--steps 1,3`→1,3; `--steps 1-2-3` and `--steps 3-1` error.

### M-006
Status: VERIFIED
Severity: HIGH
Category: docs
Files: DOC/POS.md:217,220,298,324; DOC/howto/communication.md:83,91,102,200,317; DOC/howto/system.md:18,19,54,78; DOC/HOWTO.md:74; (code: bin/pos-system-health, bin/pos-system-backup)
Evidence: `pos system health [--send] [--markdown]` and `pos system backup --send` are documented in 5 docs, but commit fe7708f deleted the flag handling from `bin/pos-system-health` (82 lines removed) — the tools now hit `err "Unknown option '--send'"`. Not a flag our tools accept → documented feature would fail at runtime.
Expected: docs match code. Either restore `--send`/`--markdown` (notify-path) or strip every reference and rework the howto examples that use it (`@quiet pos system health --send` maps).
Recommended fix: decide feature vs docs: restore the notify send flags in system-health/backup (they were deleted alongside the old pos-health units) OR remove all `--send`/`--markdown` references. Update HOWTO examples accordingly.
Verification: no `--send`/`--markdown` mention in docs that isn't in code (or flags work).
Fix (2026-08-14): decision — do NOT restore the flags. fe7708f deliberately made health a console-only reporter ("health itself never sends notifications. Sending is the wrapper's job"); backup never had a `--send` flag; the scheduler's `NOTIFY=always` already delivers full output. Docs corrected instead: DOC/POS.md:217,220,298,324; DOC/howto/communication.md:83,91,102,200,317; DOC/howto/system.md (17-19, schedule example, env sample); DOC/HOWTO.md:74. Grep-verified: no stale `system health --send`/`--markdown` refs remain (only legit `--markdown` for matrix sender / entertainment send).

### M-007
Status: VERIFIED
Severity: MEDIUM
Category: bug
Files: lib/notify.sh:57,73,79,83
Evidence: `warn "…" 2>/dev/null || echo "…"` — when sourced standalone (notify.sh is designed to be sourceable without common.sh, line 3) and `warn` is absent, the `|| echo` fallback writes the message to **stdout**. notify.sh is meant to be a silent helper (per-file note line 3: "so it can be sourced by tools that define their own log/warn/err"); stdout here contaminates wrappers/plugins (e.g. entertainment send).
Expected: notify.sh must never write to stdout.
Recommended fix: route fallbacks to stderr (`warn() { printf … >&2; }` or `>&2` on the echoes).
Verification: `lib/notify.sh` sourced alone prints nothing to stdout on a failed send.
Fix (2026-08-14): only line 57 actually leaked stdout (`|| echo "…"`); lines 73/79/83 already end in `|| true` (silent). Routed line 57's fallback to stderr (`>…` on the echo). Verified: standalone `source lib/notify.sh; notify_send ""` → stdout empty, message on stderr.

### P1 — clear convention violations

### M-001
Status: VERIFIED
Severity: LOW
Category: convention
Files: features/autostart.sh
Evidence: Lines 1-2: shebang then `LOG="${HOME:-/root}/.autostart.log"` directly — no `set -euo pipefail`. Template `templates/feature.sh:2` requires it; sibling `features/usb-automount.sh:2` has it.
Expected: `set -euo pipefail` as line 2 (all scripts, libs exempt).
Recommended fix: insert `set -euo pipefail` after the shebang (script already defensively uses `|| true`).
Verification: `./scripts/lint-conventions.sh` clean; `bash -n features/autostart.sh`.
Fix (2026-08-14): rewrote autostart.sh with the full feature-template preamble (`set -euo pipefail`, flags.sh load, usage()/`-h|--help` — folded into M-017). Verified: `bash -n` clean; `-h` prints usage; a real run appends the 3 log lines; lint clean.

### M-008..M-014 — `-h|--help` before deps guards (standardization)
Status: VERIFIED
Severity: MEDIUM
Category: standardization
Files: bin/pos-docker-health:21/24, bin/pos-docker-ps:17/20, bin/pos-media-mp3:38/58, bin/pos-media-mp4:43/71, bin/pos-network-scan:28/66, bin/pos-share-usb-server:191/199, bin/pos-system-health:39/119
Evidence: AGENTS.md/DEV.md convention — `command -v` deps guards sit **before** the `-h|--help` dispatch so help also errors on a box missing the dependency. These 7 tools dispatch help first. For docker-health/docker-ps the guard is only ~3 lines late (near-miss). For system-health there is **no top-level guard at all** (all `command -v` are per-check runtime probes at 119/166/182) — it degrades gracefully instead.
Expected: uniform guard-before-help, or an explicitly documented exception for graceful-degradation tools.
Recommended fix: move guards above help in the 6 hard-dep tools; for system-health either add a minimal guard (docker/fail2ban/systemctl are optional by design) or document it as the sanctioned no-guard pattern in DEV.md.
Verification: `make check` green; `./scripts/lint-conventions.sh` shows no dep-guard FAILs; each tool's `--help` still works without deps installed.
Fix (2026-08-14): 6 hard-dep tools now guard before help — docker-health, docker-ps (converted to documented `command -v X || err` form), network-scan (moved up, kept its echo/exit style), share-usb-server (moved up), media-mp3/mp4 (guards moved before help with a `--dry-run` pre-scan preserving the documented dry-run-without-deps behavior; duplicate `DRY_RUN=0` and post-loop guard blocks removed). system-health documented as the sanctioned no-guard pattern in DEV.md (graceful degradation). Lint refined: `first_guard_line()` only matches real guards (`command -v … ||`, `if ! command -v`, `command -v … \`) and `first_line()` skips comment lines. Verified: lint shows no dep-guard FAILs; restricted-PATH tests — `pos media mp3 -h` errors without deps, `--dry-run` still previews; `pos share usb-server -h` errors (usbsrv absent); mp4 mutual-exclusion checks intact.

### M-015
Status: VERIFIED
Severity: MEDIUM
Category: convention
Files: bin/pos-system-firewall
Evidence: `pos system firewall` has no `usage()` and no `-h|--help` case at all — first thing is a root check, then `read -rp "Execute this command?…"`. Violates the universal tool contract (templates/pos-tool.sh). Lint FAIL confirms.
Expected: `-h|--help` shows a usage synopsis.
Recommended fix: add `usage()` + `-h|--help` case (per templates/pos-tool.sh), keeping the root/deps checks ahead of it.
Verification: `pos system firewall --help` prints usage without prompting.
Fix (2026-08-14): added `usage()` + `-h|--help` case after the root check and notify.sh source (root check stays first — tool is root-only by design). Verified as root: `sudo pos-system-firewall -h` prints usage, exit 0.

### M-016
Status: VERIFIED
Severity: MEDIUM
Category: convention
Files: preinstall.sh:28-41 (PACKAGES); bin/pos-media-mp3:59, bin/pos-media-mp4:72
Evidence: both media tools `command -v ffmpeg || err …` — ffmpeg is an apt package, so per DEV.md "apt packages → PACKAGES array in preinstall.sh" it belongs there. It's absent (only yt-dlp is handled, via manual curl).
Expected: ffmpeg in `PACKAGES`; tools keep the guard as a safety net for non-install.sh installs.
Recommended fix: add `ffmpeg` to PACKAGES.
Verification: `install.sh` installs ffmpeg; mp3/mp4 guards remain as fallback.
Fix (2026-08-14): added `ffmpeg` to the PACKAGES array in preinstall.sh. `bash -n` clean; mp3/mp4 `command -v ffmpeg || err` guards untouched.

### M-017
Status: VERIFIED
Severity: LOW
Category: convention
Files: features/autostart.sh
Evidence: template `templates/feature.sh:24-26` requires sourcing `lib/flags.sh` (`# POS_FLAGS:` support), and the tool contract requires `-h|--help`. autostart.sh has neither — it's a bare boot script. Also missing `set -euo pipefail` (M-001).
Expected: feature template contract (set -euo pipefail, flags.sh load, -h|--help).
Recommended fix: add the template preamble (flags.sh load + usage/-h); no functional change to boot logic.
Verification: `bash -n` clean; `-h` prints usage; lint clean.
Fix (2026-08-14): full template preamble added (flags.sh load via the repo/usr-local fallback chain, FEATURE_NAME, usage() with Flag/Log lines, `-h|--help` case). Boot logic unchanged. Verified: `bash -n`, `-h` usage, live run logs 3 lines, lint clean.

### M-018
Status: VERIFIED
Severity: LOW
Category: convention
Files: features/usb-automount.sh
Evidence: same as M-017 — feature template `flags.sh` load (templates/feature.sh:24-26) absent. (Has `set -euo pipefail`, so only flags.sh + usage are missing.)
Recommended fix: add flags.sh load + usage/-h per template.
Verification: lint clean; `-h` works.
Fix (2026-08-14): added the flags.sh load (repo/usr-local fallback) right after `set -euo pipefail`. usage()/`-h|--help` already present. Verified: `bash -n`, lint clean.

### M-019
Status: VERIFIED
Severity: LOW
Category: standardization
Files: apps/media/scrcpy.sh
Evidence: 0644 (`-rw-rw-r--`) while every other `apps/*/*.sh` is 0755. Consistent exec-bit convention violated.
Recommended fix: `chmod +x apps/media/scrcpy.sh`.
Verification: `ls -l apps/media/scrcpy.sh` shows 0755; `make check` exec-bit gate green.
Fix (2026-08-14): `chmod +x apps/media/scrcpy.sh` → 0755. `make check` exec-bit gate will confirm at final run.

### M-020
Status: VERIFIED
Severity: LOW
Category: standardization
Files: bin/pos-docker-compose:8,9
Evidence: `SCALE_DIR="/usr/local/share/linux_post_install/scale-tail/services"` and `CONFIG_ENV="${HOME}/.config/linux_post_install/compose.env"` hardcoded — no `${VAR:-…}` env seam, unlike the documented `SERVICES_BASE` default (/srv). DEV.md seam rule says every system path write has a `VAR="${VAR:-path}"` guard.
Expected: `SCALE_DIR="${SCALE_DIR:-/usr/local/share/…}"` etc.
Recommended fix: add `:-` seams for SCALE_DIR and CONFIG_ENV.
Verification: env override respected in a dry-run.
Fix (2026-08-14): added `:-` seams for both. Verified: `CONFIG_ENV=/tmp/... config` prints the override; `SCALE_DIR=/tmp/... ls` errors citing the override.
Follow-on found while verifying: `pos docker compose config` crashed with `DIM: unbound variable` (common.sh color block had no DIM; pre-existing on HEAD). Fixed by adding `DIM=$(tput dim)` / empty-fallback to the common.sh color block. `config` now prints correctly.

### P2 — doc drift / consistency / style

### M-021
Status: VERIFIED
Severity: LOW
Category: standardization
Files: lib/notify.sh:27, lib/entertainment-lib.sh:5, lib/config-ui.sh:22, bin/pos-network-download:16, bin/pos-communication-{matrix,telegram}-{listener,sender}
Evidence: `CONFIG_DIR` redefined per-file with inconsistent semantics: notify.sh is XDG-aware (`${XDG_CONFIG_HOME:-$HOME/.config}`), the rest use plain `$HOME/.config/linux_post_install`, network-download uses the `${CONFIG_DIR:-…}` seam form. Same global name, three conventions.
Expected: one definition (in lib/common.sh) + seam form everywhere.
Recommended fix: define `CONFIG_DIR` once in common.sh; drop per-file definitions (keep the `:-` seam in network-download).
Verification: all tools still resolve config after refactor.
Fix (2026-08-14): canonical `CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/linux_post_install}"` defined in common.sh; dropped the duplicate in entertainment-lib.sh (loads common.sh) and network-download (loads common.sh). Standalone-sourced files (notify.sh, config-ui.sh, the matrix/telegram listener/sender — none source common.sh) keep an identical guarded seam line, mirroring the "no shared lib? inline fallbacks" convention; noted in common.sh. Verified: notify.sh standalone resolves default/XDG/CONFIG_DIR overrides correctly; pos-config (common.sh + config-ui) works; all touched files bash -n clean.

### M-022
Status: VERIFIED
Severity: LOW
Category: standardization
Files: lib/entertainment-lib.sh (plugin_dir/plugin_exists/plugin_keys/plugin_marker), lib/entertainment-plugin-lib.sh (plugin_config_file/plugin_err/plugin_have/plugin_http_json/plugin_load_config/plugin_require)
Evidence: two libs share the `plugin_*` prefix for unrelated jobs (marker/registry helpers vs plugin runtime helpers). Collision-prone and unclear at call sites.
Expected: distinct prefixes per concern.
Recommended fix: rename the plugin-lib helpers (e.g. `plt_*`/`plugin_rt_*`) or the marker helpers; keep one prefix per lib.
Verification: grep for `plugin_` shows no cross-lib ambiguity; `make gen && make check` green.
Fix (2026-08-14): kept `plugin_*` for the documented plugin-authoring API (`plugin_load_config`/`plugin_have`/`plugin_require`/`plugin_http_json`/`plugin_err`/`plugin_config_file` — referenced in DOC/DEV.md and DOC/POS.md; user plugins depend on it). Renamed the internal registry helpers in lib/entertainment-lib.sh to `ent_plugin_dir`/`ent_plugin_marker`/`ent_plugin_exists`/`ent_plugin_keys` and updated callers (pos-entertainment-{status,enable,config,send}, lib/config-ui.sh). Verified: no bare `plugin_` registry helpers remain; plugin runtime helpers untouched; entertainment tools + pos-config smoke-tested; bash -n clean.

### M-023
Status: VERIFIED
Severity: LOW
Category: docs
Files: DOC/POS.md; bin/pos-config, bin/pos-tree, bin/pos-entertainment-{config,enable,disable,status}
Evidence: 6 shipped tools are absent from the POS.md command reference (31 `bin/pos-*` refs exist but not these). Lint WARN confirms.
Expected: every tool documented in POS.md.
Recommended fix: add rows to the POS.md command table (and cross-check HOWTO for the entertainment group).
Verification: lint WARNs gone; `grep` shows each tool in POS.md.
Fix (2026-08-14): the tools were documented by command name but not by filename (the lint references basenames). Added `**File:** bin/pos-config` (config section), `**File:** bin/pos-tree` (tree section), and a file list on the entertainment section header covering `bin/pos-entertainment-{config,enable,disable,status}`. Verified: lint 0 WARN. HOWTO already covers the entertainment group via `pos entertainment *` command forms.

### P3 — intentional / legacy (no action)
- install.sh:123,135,155,185 — installer writes to /usr/local/bin are its purpose; no seam needed (lint excludes install scripts).
- network-download RPC_SECRET at :150 — generated at runtime (`/dev/urandom`), not a committed secret.
- system-health graceful degradation — candidate for the sanctioned no-guard pattern (see M-014); decide in fix session whether it becomes a P1 or a P3. Commit fe7708f's removal of the old `pos-health.{service,timer}` units is correct (superseded by scheduler); the only leftover is the stale docs (M-006).

## Semantic deep-dive notes (the detective pass)

- `lib/notify.sh` — stdout-leak via `warn … || echo` fallbacks (M-007); rest of helper logic (platform routing, silent-fail contract) correct.
- `lib/common.sh` — `confirm()` reads stdin via `read -rp` → it makes any caller an INTERACTIVE_CMDS candidate (this is how M-003/M-002 were caught). Deps guards, `run`/`spawn`, `$DRY_RUN` semantics all match convention.
- `bin/pos` — INTERACTIVE_CMDS list (259) was complete except the 3 new stdin readers (M-002..M-004); no stale entries (lint reverse-check green). Dispatcher longest-prefix logic unchanged from prior fix session.
- `bin/pos-system-firewall` — entirely interactive; root-check-first is correct, but no usage/-h at all (M-015).
- `bin/pos-system-health` — pure passive reporter; per-check `command -v` probes are correct for graceful degradation, but leave the no-top-level-guard pattern undocumented (M-014). Prints to stdout by design (it IS the report) — the notify path is what the docs claim (M-006) but was removed in fe7708f.
- `install.sh` — `--steps` comma-only parsing (M-005); the phase functions themselves and step numbering are consistent with the header. Legacy `x-systemd.automount`-style remnants: none — the fstab/automount handling in share tools uses correct systemd units now (verified in prior fix session, commits 1724096/93fb6b6).
- `pos-docker-compose` — hardcoded template dir + config path (M-020); `SERVICES_BASE` documented in `# POS_CONFIG:` and used at runtime for deployments, but not for SCALE_DIR.
- No `x-systemd.automount` in any unit `Options=` (grep clean). No `interact`/`getconf`-style stale-format headers anywhere in `bin/`.
- Entertainment plugins: none source common.sh; all carry `# POS_PLUGIN:` + `# POS_KEYS:` (lint green).
- systemd units: `TimeoutStopSec=` + `[Install] WantedBy=` present everywhere (lint green); no leftover `pos-health.{service,timer}` (removed in fe7708f, correct).

## Next-session brief

1. Fix P0 → P1 → P2 in order (HIGH first: M-002..M-006, then M-007, then the rest).
2. M-006 needs a product decision first: restore `--send`/`--markdown` (notify path) or strip the docs.
3. Re-run `make gen && make check && scripts/lint-conventions.sh` + smoke each changed tool.
4. Commit `scripts/lint-conventions.sh` + add the `make lint` target (this was on the deliverable list but is not yet wired into the Makefile).
5. Move audit tasks to AGENT_TODO Done (dated) on completion.

## Checked & clean

- lib/common.sh (deps/run/spawn/confirm — semantics verified)
- lib/notify.sh (logic — only the stdout-fallback leak, M-007)
- legacy wrappers bin/wr-*, bin/mp3, bin/mp4, bin/vbox, bin/ssh-load-all (thin, forward to pos)
- systemd/*.service (TimeoutStopSec + WantedBy everywhere)
- entertainment/*.sh (no common.sh, POS_PLUGIN/POS_KEYS present)
- secrets: no committed credentials anywhere (grep for TOKEN/SECRET/AUTHKEY/RPC_SECRET literals clean — all guards/config-reads/runtime-gen)
- stale-format conventions: no `x-systemd.automount`, no old header formats, no leftover pos-health units
