# Reviewer Report — Phase-2 Menu Changeset (T4: vbox + download · T5: firewall)

> Provenance note: written by Orchestrator on behalf of Reviewer, whose sandbox denied all file writes. Content is the Reviewer's inline delivery, verbatim.

## TL;DR
- Verdict: **ACCEPT-WITH-NITS** — zero blocking, zero required defects; 2 suggested (report-prose accuracy only), 5 notes.
- T4 vbox: menu_self self-invocation is safe (quoted `"$@"`, absolute `$0`, verbs ≠ `menu` → no recursion); enter handover provably returns to loop (child-process `exec`); rm/create confirm-gated BEFORE any mutating docker call.
- T4 download: all 13 items map onto verified existing `cmd_*`/`overview` defs; dead-RPC cannot hang or kill the menu (probe-first `-m 3`; `cmd_status` inherently safe); **INTERACTIVE_CMDS deviation is CORRECT**, not merely tolerated — designer rule 5 + survey E-002 mandate staying out; lint pass traced honest through `uses_stdin`.
- T5 firewall: all four mechanics intents verified hunk-by-hunk; menu heredoc body byte-preserved (appears solely as diff context); every interactive read converted (actual count **38**, reports say 22 — prose miscount only); EOF paths always exit the tool (cannot loop); RESET/confirm/pager/root-gate/help untouched.
- Sandbox disclosure: bash restricted to read-only git → **no pty probes run, no make re-runs** (Orchestrator's post-T5 results accepted as claims; static cross-checks found zero contradictions). Probe checklist item closed [BLOCKED-sandbox], compensated statically.

## Step 1: Baseline & scope fence [DONE] — PASS
- Pre-T4 state == HEAD `010e067` for all three files: prior tracks never touched them. Diff stats vs HEAD match builder claims exactly: vbox +104/−1 · download +154/−1 · firewall +59/−42 (308→325). [FACT]
- Contamination audit of the shared uncommitted tree: `bin/pos` has exactly ONE hunk = share-track's nfs entries added to INTERACTIVE_CMDS (:262) — zero T4/T5 edits. DOC/POS.md hunks attributable to this changeset: exactly the two `**…menu**` paragraphs; all other row edits are prior tracks' disclosed WIP. GEN blocks carry multi-track regen drift as disclosed. No out-of-scope change BY this changeset. [FACT]

## Step 2: T4 `bin/pos-docker-vbox` [DONE] — PASS
- **menu_self** (vbox:47–49): child invocation with individually quoted args (no split/glob injection), `$0` resolved absolute at call time. Recursion impossible: every call site passes a concrete verb (`ls|create|enter|start|stop|rm`), never `menu`/zero-args → children can never re-enter `run_menu`. [FACT]
- **enter handover**: verb ends in `exec docker exec -it …` (:230–232) — exec replaces the *menu_self child*; on shell exit the child terminates and the parent loop re-renders. Structure + builder V4 agree. [FACT + corroborated claim]
- **rm safety**: pick → `confirm "Permanently remove VM '$vm' …" n || Cancelled` → `menu_self rm`; only read-only docker calls before the gate; common.sh:120–128 confirm(default n) passes only on explicit Y/y — Enter-deny, EOF-fail-closed; message accurately reflects `docker rm -f` + folder kept. [FACT]
- Doors precede `-h|--help`; sole deletion = rewritten `# POS_SUBCMDS:` line; everything below byte-stable. No deps guard at HEAD either — pre-existing. [FACT]

## Step 3: T4 `bin/pos-network-download` [DONE] — PASS
- **Mapping completeness** — all 13 targets exist: cmd_status:212, overview:1066, cmd_list:711, cmd_add:260, cmd_info:730, cmd_pause:774, cmd_resume:775, cmd_remove:777, cmd_restart:431, cmd_purge:788, cmd_watch:846, cmd_start:148, cmd_stop:197. Dispatch case untouched (purely additive diff). [FACT]
- **Confirms**: remove names name+short gid via `menu_ask_yn` (y-only; Enter/EOF cancel) BEFORE `cmd_remove`; purge requires literal typed `purge`; stop confirms naming `$SERVICE`; start unconfirmed = CLI parity per brief. Aborts all precede mutation. [FACT]
- **RPC-dead path**: `menu_gate_daemon` = non-fatal `aria2.getVersion` probe, `-m 3`, warn + stay alive; applied to items 2/3/11 and inside gid-action/remove/purge helpers. Item 1 needs no gate — `cmd_status` keeps all rpc() behind `daemon_active` (:222–226); dead daemon prints "not running", no exit. Stop works daemonless by design. Probe→action race (rpc() err-exit) disclosed = CLI semantics. No hang possible anywhere. [FACT]
- **INTERACTIVE_CMDS deviation — CORRECT**: brief premise wrong (download not a member at HEAD); designer rule 5: *"Do NOT add tools to INTERACTIVE_CMDS — stderr+/dev/tty is sufficient and keeps logging for all non-menu paths (E-002)"*, E-002 classified FACT. Builder followed the binding contract. Wrinkle: menu-lib reads fd0 behind `menu_guard`'s `[ -t 0 ]` proof rather than literally `/dev/tty` — equivalent fail-closed guarantee. [FACT]
- **Lint honesty trace**: `scripts/lint-conventions.sh:59–80` flags literal `read `/`select `/`confirm `/`confirm(` unless comment / contains `/dev/tty` / `while|until … read` / uses `< `. Download's new lines contain none of those tokens (the `menu_ask_yn` naming dodge verified against the patterns); pre-existing reads (:240, :417) are while-loop exempt; :937 is a comment ⇒ `uses_stdin`=0, membership check never applies. vbox keeps raw `confirm()` legitimately (member, :262). Pass is genuine. [FACT]

## Step 4: T5 `bin/pos-system-firewall` [DONE] — PASS
- Four intents hunk-by-hunk: (1) `tty_read()` :43–56 — EOF *and* `/dev/tty` open-failure both land in `if !` → pointer ×2 → exit 1. (2) Menu heredoc `{ … } >&2` — body lines appear ONLY as context ⇒ byte-preservation proven structurally. (3) ALL reads converted — actual **38** pairs (run_cmd 1, prompt_ipver 1, add_rule 27, delete_rule 3, status 1, main loop 6); grep confirms zero raw `read` outside the seam. (4) `prompt_ipver` assigns caller-scoped `ipver` (`local ipver` retained in caller) — EOF now exits the whole tool gracefully; value semantics identical. [FACT]
- EOF cannot loop: every tty_read failure terminates the process. Non-tty fails closed rc1 (builder probe (e) consistent with code). [FACT]
- Preserved (context lines): root gate, help, header, preview+confirm+dry-run+notify flow, unquoted `$ruletext`, HISTORY/goodbye/clear, dispatch; pager explicit `REPLY` = same implicit target; color gating genuinely N/A; DOC/POS.md row correctly untouched. Behavior deltas exactly the two mandated ones. [FACT]

## Step 5: Cross-tool consistency & docs [DONE] — PASS
- Completions `_pos_subcmds[docker-vbox]`/`[network-download]` end in `menu` matching headers; firewall correctly none. GEN filetable rows == wc -l (261/1104/325); dispatch rows unchanged; POS.md paragraphs accurate detail-for-detail; Context_Project "vbox Details" still true. [FACT + make-gen-idempotence accepted on Orchestrator evidence]

## Step 6: Bounded pty probes [BLOCKED-sandbox]
Only read-only git commands permitted (enforced mid-review). Compensations: full-diff structural proofs + independent re-derivation of the linter outcome. Gate trio + builders' probes = UNVERIFIED-but-uncontradicted.

## Findings
1. SUGGESTED — Read-count prose error: brief + T5 report say "22 interactive reads"; diff converts **38**. Mechanics complete regardless.
2. SUGGESTED — Misattributed precedent: T4 cites vbox's "own tmux_watch `$self watch $gid`"; that code lives in pos-network-download:922–924 — vbox has no tmux/self code. Pattern sound; attribution wrong.
3. NOTE — Backing-verb failure ends the whole menu via errexit (disclosed phase-1 NOTE #5 class, consistent across all six menu tools).
4. NOTE — EOF at `confirm()` dies on set-u unbound `yn` (common.sh:120–129) — fail-closed, pre-existing repo-wide, affects phase-1 menus identically.
5. NOTE — vbox create: EOF at dir prompt degrades to documented default then hits y/N gate (name/image prompts abort instead) — cosmetic inconsistency, fail-closed maintained.
6. NOTE — `menu_rpc_ok` `-m 3` vs rpc()'s `-m 60`: slow-but-alive daemon reported unreachable — deliberate trade-off.
7. NOTE — Gates/probes UNVERIFIED (sandbox), zero static contradictions.

## Verdict block
Status: ACCEPT-WITH-NITS · Reviewed: T4 + T5 files + DOC/GEN rows vs HEAD baseline · Verified: scope fence, recursion/injection analysis, 13/13 mapping, confirm-before-mutate, hang-freedom, lint honesty trace, four T5 intents, byte preservation (structural), SUBCMDS/filetable/POS.md sync · Unverified: make-trio re-run, pty probes · Remaining uncertainty: runtime rendering byte-equality rests on builder harness evidence · Recommended next agent: **Orchestrator** (accept; AGENT_TODO Done entries for T4/T5 at commit) · Changes made by Reviewer: none.

REPORT_PATH: ./reportAgents/2026-08-23-reviewer-phase2-menu.md
