# Reviewer Report — Phase-1 Menu Changeset (T1+T2+T3)

> Provenance note: written by Orchestrator on behalf of Reviewer, whose sandbox denied all file writes. Content is the Reviewer's inline delivery, verbatim.

## TL;DR
- Verdict: **ACCEPT_WITH_NOTES** — zero blocking/required defects.
- Defect count: 0 blockers · 0 required · 2 suggestions · 4 notes.
- T3 integrity: CLEAN — recovery from the symlink clobber was faithful.
- Gates: bash -n ×7 verified independently; make-trio + pty probes UNVERIFIED (sandbox denies execution).

## Checklist results
1. [PASS] Scope fence · 2. [PASS] Shim fidelity · 3. [PASS] Automation doors · 4. [PASS] Non-tty/scriptability (static) · 5. [PASS] Destructive safety · 6. [PASS] Conventions/docs · 7. [PARTIAL] gates (bash -n done; make trio blocked) · 8. [BLOCKED-sandbox] pty probe.

## Step A: Inputs & baselines [DONE]
Explorer survey, designer suitability, builder T1/T2/T3 read in full. wc -l matches all claims. Caveat: `lib/share-lib.sh` is untracked other-track WIP → no git baseline; verified structurally against explorer's documented Pattern-B contracts + line arithmetic (old domain :165–436 = 272 ln == new :47–318). [DONE]

## Step B: Scope fence [DONE] — PASS
- Phase-1 file set exact: menu-lib (new), share-lib, 4 tools, install.sh:143 single hunk (+`share-lib.sh menu-lib.sh`; share-lib entry is the share track's per their AGENT_TODO entry, menu-lib is T1's), DOC rows (POS.md ×4, DEV.md:34, SCRIPTS.md:41/:220/:224+, Context_Project :209/:584/:585 + GEN), completions (exactly 4 Phase-1 entries).
- Other tracks' files audited for contamination — none: preinstall.sh = +smbclient only; bin/pos = +nfs×2 INTERACTIVE_CMDS only; AGENTS.md = CI bullet + hotspot bullet; AGENT_TODO = share-suite entry only (**no Phase-1 Done entries yet**); share-* ×5 still consume only `share_menu_guard` shims (corroborates T1 "zero edits"); ytsync/howto/share.md untouched by Phase-1.
- Unclaimed untracked `opencode_helper/` present — keep out of commits.

## Step C: Shim fidelity [DONE] — PASS
share-lib.sh:37–45: 4-way sourcing chain + exactly 4 pure `"$@"` delegators, no leaked bodies, accurate header/index. menu-lib.sh read in full: guard rc0-iff-tty/stderr-pointer/rc1 · menu_run render→stderr, index-only stdout, EOF/q→rc1, ""→redraw · pick case-insensitive filter, full-list index, EOF/b→rc1 · ask_value EOF rc1 / empty-no-default rc1 / value→stdout. Byte-equality to pre-T1 bodies = STRONG INFERENCE (no baseline; structure+arithmetic+contracts support).

## Step D: Automation doors [DONE] — PASS
Diff-completeness proves byte-stability (all hunks accounted; dispatch regions below final hunks); entertainment-send + listeners absent from modified list; all four tools already INTERACTIVE_CMDS members at HEAD — designer rule "don't grow the list" respected.

## Step E: Non-tty/scriptability [DONE] — PASS (static)
Front doors intercept only `$1=menu` or `$#=0 && [ -t 0 ]`; `menu </dev/null` → guard pointer rc1 on all four; EOF-safe reads throughout; set -u hazards cleared (EFF_ROOTS backup:14; MP3/MP4/DRY_RUN/SRC media-sync:18–22).

## Step F: Destructive safety [DONE] — PASS
`confirm … n` (common.sh:120) passes only on explicit Y/y — Enter-deny, EOF-fail-closed. All five destructive paths abort BEFORE mutation: compose down/restart/update (prompts name stack/$SERVICES_BASE+".env preserved"), schedule run-now (names job → same sched_run timers use), backup ×3 (names folder+mode before tar/gpg). media-sync sync-now unconfirmed by design (add/update-only; disclosed deviation).

## Step G: Conventions & docs [DONE] — PASS
Strict mode everywhere; SUBCMDS `menu` appended last (smb-server precedent); deps guards preserved; all 15 backing functions verified to exist; load_global_config usage mirrors existing pattern; POS.md item lists match implementations verbatim; SCRIPTS lib list == install.sh:143; GEN rows == wc -l.

## Findings
1. SUGGESTED — AGENT_TODO.md lacks Phase-1 Done entries (owner: Orchestrator, at commit).
2. SUGGESTED — Run `make gen && make check && make lint` once pre-commit (reviewer sandbox-blocked).
3. NOTE (other track) — `bin/pos-share-usb-server:4` puts bare `menu` in `# POS_FLAGS:` → completions list it as a flag; owning track should move it to `# POS_SUBCMDS:`.
4. NOTE (pre-existing) — needs_copy can overwrite newer USB copies with older source (mtime rule); verbatim extraction, not a regression.
5. NOTE — hard-failing backing cmd exits tool via err() instead of redraw (= CLI semantics, disclosed by T3).
6. NOTE — `opencode_helper/` unclaimed untracked dir; exclude from commits.

## Verdict block
Status: ACCEPT_WITH_NOTES · Reviewed: T1+T2+T3 changeset · Contract: explorer survey + designer suitability rules 1–9 · Verified: scope fence, shims, door stability, fail-closed guards, destructive confirms, conventions, doc/gen sync, bash -n ×7 · Unverified: make gen/check/lint re-run, pty probes (sandbox) · Next agent: **Orchestrator** (accept; run gates; AGENT_TODO updates; commit) · Changes made by Reviewer: none.

REPORT_PATH: ./reportAgents/2026-08-23-reviewer-phase1-menu.md
