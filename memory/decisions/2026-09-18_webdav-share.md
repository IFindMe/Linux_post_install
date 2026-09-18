# Breakdown report — webdav-share (2026-09-18)

`TL;DR` — Goal: 3-part large goal (fix stale DEV.md passage + WebDAV research to `.opencode/resources/` + new `pos share` WebDAV tool with tests/docs/gates). Tasks: 7 (01 docs fix, 02 research, 03 design, 04 build, 05 tests, 06 docs, 07 gates). Structure: linear chain 02→03→04→(05,06)→07 with 01 independent. Next executable: 01 or 02 (no deps). Open items: server-choice decision deferred to 03 (Architect); exact tool filename (`bin/pos-share-webdav` vs server/client split) deferred to 03.

## Decision 1: goal slug + tree location

Chose `<goal-name>` = `webdav-share` (short kebab-case; covers the main deliverable; README records the full 3-part goal). Tree at `.tasks/webdav-share/` (project-local, gitignored per `.gitignore`). [DONE]

## Decision 2: goal is large enough for a breakdown

Measured against the MUST-dispatch rules: new tool file + research docs + tests + 2 doc updates = likely files ≥ 3; chain research→design→build→test/docs→gates gives dependency depth; roles span Explorer/Architect/Builder/Tester/Writer + gates. Not trivial → breakdown warranted, no `[BLOCKED]` self-serve return. [DONE]

## Decision 3: task granularity (7 tasks)

Alternatives considered: (a) 3 tasks mirroring the goal's 3 numbered items — rejected, item 3 alone spans design+build+test+docs+gates and would force role drift in one file; (b) 10+ micro-tasks (e.g. split server vs client tools, split POS.md vs howto) — rejected, over-splitting before the server-choice design exists. Chosen: 7 tasks, each one coherent unit for one specialist. Build/test/docs/gates kept separate so Tester never implements and Writer never gates. [DONE]

## Decision 4: dependency graph

02→03→04→{05,06}→07; 01 independent (docs-only, feeds 04 as input, gated by 07). Next executable after CREATE: 01 and 02 (both `pending`, no `depends-on`). [DONE]

## Decision 5: evidence base (lean reads only)

Cited files, not quoted: `DOC/DEV.md:205` (stale passage), `DOC/DEV.md:408` (second stale ref), `DOC/DEV.md:79-199` (adding-tool checklist + seams), `AGENTS.md` (definition of done + tool rules), `.opencode/skills/linux-post-install/SKILL.md` (tool model + test conventions), `templates/pos-tool.sh`, `bin/pos-share-nfs-server:1-90`, `lib/share-lib.sh:42-277`, `bin/pos:277` (INTERACTIVE_CMDS), `tests/README.md`, `Makefile`, `DOC/howto/share.md` (309 lines), `DOC/POS.md:344-358` (share section). No broad exploration. [DONE]

## Decision 6: validation invariant

Ran all six checks against `.tasks/webdav-share/` (first script pass miscounted `00-overview.md` as a numbered file — script bug, not a tree defect; corrected run): 1) README+overview+flag exist; 2) flag keys exactly {goal,status,tasks}; 3) goal=`webdav-share`, values valid; 4) flag keys {01..07} == numbered files; 5) overview lists all 7; 6) zero-padded ascending, no gaps. INVARIANT: PASSES (6/6). [DONE]
