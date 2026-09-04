# Reviewer Report — `pos media ytsync` acceptance review

Date: 2026-08-23 · Agent: Reviewer · Status: **ACCEPT_WITH_NITS**

> Note (orchestrator): the Reviewer session could not write files (sandbox denied);
> this report was delivered verbatim and persisted on its behalf.

Read-only adversarial review of uncommitted working-tree work. Verified against the binding contracts `reportAgents/2026-08-22-architect-ytsync.md` (D1–D9 + approved implementation scope) and `reportAgents/2026-08-22-designer-ytsync.md` (§2–§3 UX copy), plus Builder's handoff claims. Sandbox note: this session could execute only read-only git commands — conclusions are static code reading + git evidence + gate/battery results accepted as reported (empirical residue listed as UNVERIFIED).

## Step 1: Working-tree attribution & scope conformance [PASS]

`git status` shows share-suite dirt (pre-existing) + this task's files. Diffed every modified tracked file:

- **Attributable to ytsync (matches Builder's claim exactly):** new `bin/pos-media-ytsync` + `tools-docs/ytsync.md`; `DOC/POS.md` (media row :213 + notes :215-223), `DOC/HOWTO.md` (:15 wording line), `DOC/howto/media.md` (section + troubleshooting), `DOC/AGENT_Context_Project.md` (tree/dispatch/filetable GEN rows + §14 row :661), `AGENT_TODO.md` (Done entry 2026-08-22), `bin/pos` (**EXAMPLES line only**, :156), `completions/pos.bash` (GEN blocks only).
- **Share-suite dirt, NOT this task:** `AGENTS.md` (hotspot bullet), `DOC/DEV.md` (lib row + EXPORTS_FILE seam), `install.sh` (+share-lib.sh), `preinstall.sh` (+smbclient), `DOC/SCRIPTS.md`, `DOC/howto/share.md`, five `bin/pos-share-*`, untracked `lib/share-lib.sh`, INTERACTIVE_CMDS += share-nfs-client/share-nfs-server, AGENT_TODO 2026-08-21 entry. None reference ytsync.
- **No tracked `lib/*` file modified** by this work ✓. `INTERACTIVE_CMDS` (bin/pos:262): `media-ytsync` absent ✓ (D5). Headers :3-6 match D2/D3 verbatim; `# POS_CONFIG` conforms to lib/config-ui.sh:7-15 grammar → `pos config ytsync` functional. Filetable row 1180 lines = actual file length ✓.

## Step 2: Contract spot-checks [PASS]

- **Exit codes:** rc1 sites are exactly the fatal set — deps guards (:22-25; `err`=exit1 per lib/common.sh:24), invalid explicit URL (:861-864), probe/probe-parse fail at explicit add (:865-874), unknown name (:947,:1020), ambiguous (:950,:1023), parser errors (:1151,:1158,:1169,:1179). Wholesale failure ⇒ rc1 via G_WHOLEFAIL (:931-934); bare `sync` requests all sources, matching D2's scheduler-observability intent. Per-video failures continue at rc0 (:659-664). Cancels/EOF/guard/nothing-tracked/already-tracked rc0.
- **Non-tty guard:** require_tty :781-787 prints Designer's verbatim copy to stderr; callers exit 0 (:857, :1109); every `/dev/tty` read sits behind the guard or in-menu.
- **Deps guards before `-h|--help`:** :20-26 precede dispatch :1147+; yt-dlp+jq active under --dry-run, ffmpeg skipped (:24-26) = D7 exactly, incl. the accurate install copy.
- **Atomic registry writes:** mktemp-in-state-dir + mv both directions (:226-236, :238-250).
- **\x1f separators:** build :762-763; parse `IFS=$'\x1f' read` :895/:912/:971/:999/:1056; jq pairs `\u001f` :370. No tabs.
- **ERR-trap armed ONLY around download loops:** sole arm pass_execute:623, disarm :666; probe failures notify via digest wholefail branch instead (single owner).
- **Dry-run zero-writes traced on every path:** registration gated (:747-764), dry-run plan branch print-only (:599-605), history-failed gated (:918-920), send_digest early-return (:510), remove preview (:1001-1004), fresh `list` writes nothing. Claim holds by construction.
- **Designer copy verbatim-conformant:** menu (:1031-1043), prompts (:750,:803,:805,:1063,:1079), summary grammar (:669), digest shape + cap/"…and M more" (:513-525), warn vocabulary (:651,:656,:660,:569/:609).

## Step 3: Builder deviations 1–5 [PASS — all justified, none silent]

1. Custom run_probe() vs spawn() — **JUSTIFIED, actually necessary**: common.sh:114 exits process on failure (kills re-prompt ×3 / multi-source sync) and common.sh:96-97 emits `\r` unconditionally; run_probe mirrors UX, TTY-gates frames (:313), returns rc. Documented in tools-docs.
2. Collision folded into "already present" — **JUSTIFIED**: keeps D5's three-bucket grammar truthful; resolves D5-vs-D6 spec tension; documented tools-docs:104-107.
3. `FAILED (probe)` history variant — **JUSTIFIED**: fake zeros would hide wholesale failures from grep; tools-docs:95-97.
4. Post-verb flag positions — **JUSTIFIED**: no new verbs/flags; required by Designer's own usage() example `sync --dry-run` (designer report :239). (Builder's citation of "§6 case 5" is imprecise; requirement itself genuine.)
5. finish_add counter fix — **JUSTIFIED**: in-scope correctness fix mirroring pass_prepare (:739-744), suite-covered.

## Step 4: Docs accuracy spot-checks [PASS]

v=+list= ⇒ video (POS.md:215-216 ⇔ :157-166+:446) · NNN numbering (howto:173 ⇔ %03d literal injection :633-634, preview :579) · history FAILED (probe) (tools-docs:95-97 ⇔ :274-277) · dry-run plan copy + zero-writes (howto:212-214 ⇔ :574 + Step 2 trace) · non-tty-guard-rc0 & remove-keeps-archive & schedule recipe & config table (POS.md:213,:218-220; howto:195-210,:224-227 ⇔ code). All MATCH.

## Step 5: Gates & dynamic verification [PASS as reported; residue UNVERIFIED]

Orchestrator-stated make gen/check/lint green taken as input (not re-run, per E). Bash restricted to read-only git → could not execute the stub battery; Builder's 71-case PASS, real-$HOME md5 snapshot, dispatcher-integration accepted as reported evidence. Static review found nothing contradicting them.

## Findings

1. **[MINOR]** `youtu.be/<id>?list=<PL>` classifies as playlist despite naming one video — classify_url inspects only query substrings (`*v=*`/`*list=*`, bin/pos-media-ytsync:157-166); youtu.be carries the id in the path, so `&list=` wins — precisely the paste-from-playlist-view scenario D2-amendment-2 targeted (architect :103-107). Outcome still sane (tracked playlist source, incremental, removable) hence not major. STRONG INFERENCE from glob logic; live impact HYPOTHESIS. Fix or document in tools-docs/help.
2. **[NIT]** tools-docs invocation block omits `--convert-thumbnails jpg` (code :439, declared in handoff); mechanics doc slightly out of sync; flag addition beyond literal D4 skeleton but benign/declared.
3. **[NIT]** Builder report says 1179 lines; file is 1180 (generated filetable row correct at 1180). Report-only inaccuracy.
4. **[NOTE]** YTSYNC_EXTRA_ARGS word-splitting (:449-453): space-containing values can't form one argv token; same class as sibling tools.
5. **[NOTE]** Probe has no timeout (run_probe :316-320); exposure equals existing tools' spawn; out of approved scope.
6. **[NOTE]** UNVERIFIED-by-reviewer: stub battery execution, PTY menu flows, live smoke, notify delivery — Tester/Orchestrator territory.

## Scope-conformance checklist

| Item | Result |
|---|---|
| A Surface/seams/INTERACTIVE_CMDS/lib | PASS |
| B Contract spot-checks (exit codes, guards, atomicity, \x1f, ERR-trap, dry-run) | PASS |
| C Deviations 1–5 | PASS |
| D Docs accuracy | PASS |
| E Gates green | PASS as reported |

## Recommended next agent

**Orchestrator** — accept as Done (commit pending, incl. AGENT_TODO same-commit rule). Optionally route Finding 1 + NIT 2 to Builder/Maintainer as a tiny follow-up; Builder's suggested adversarial Tester pass remains valid but non-blocking.

Changes made by Reviewer: none.
