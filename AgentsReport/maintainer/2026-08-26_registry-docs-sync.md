# 2026-08-26 — registry-docs sync (Maintainer)

## TL;DR

- **Drift:** command-registry feature (`lib/registry.sh`, optional `# POS_DEPS:`/`# POS_EXAMPLES:` headers) landed without syncing 3 agent/convention docs — confirmed: AGENTS.md (header enumeration + `pos tree` description), DOC/SCRIPTS.md (Phase-2 lib list, no lib section, stale TOC), MAINTENANCE.md (no record of the convention change).
- **Corrections:** all three synced to implemented reality (code + `# POS_*` headers as ground truth); docs-only, nothing else touched.
- **Sweep findings (reported):** 2 out-of-fence staleness spots in DOC/AGENT_Context_Project.md (:548 header enumeration, :598 wrongly lists gen-docs.sh as a registry consumer); 1 minor incomplete phrasing in DOC/POS.md:498. In-fence extra fixed: SCRIPTS.md TOC was missing 5 pre-existing lib sections.
- **MAINTENANCE.md decision:** no phase-log/conventions-summary section exists → did NOT invent one; used the file's own sanctioned mechanism instead (one appended ticket, M-024, dated Fix line).
- **Validation:** `make gen` zero new drift beyond pre-existing uncommitted feature work · `make check` OK · `make lint` **0 FAIL, 0 WARN** · `grep -n "POS_DEPS"` present in AGENTS.md / DEV.md / SCRIPTS.md.

## Standard established (evidence)

Ground truth verified before editing:

- `templates/pos-tool.sh:13-14` documents optional `# POS_DEPS:` / `# POS_EXAMPLES:`.
- `DOC/DEV.md:126-134` already documents both headers + semantics; `DOC/DEV.md:34` already lists `registry.sh` → only AGENTS.md / DOC/SCRIPTS.md / MAINTENANCE.md drifted.
- `install.sh:143` `lib_names`: registry.sh is LAST (`… usb-lib.sh share-lib.sh menu-lib.sh registry.sh`) — SCRIPTS.md Phase-2 row must append it after `menu-lib.sh`.
- Consumers: `bin/pos-tree:7` sources `lib/registry.sh`; `bin/pos:68-90` `_pos_category_help()` lazy-sources it (`reg_scan`/`reg_tools_in`/`reg_lookup`, incl. deps).
- `scripts/gen-docs.sh:47-48` parses the same headers independently (predates registry) — must NOT be listed as a registry consumer.
- `lib/registry.sh` (199 lines): no shebang, not executable, installed 644; guarded `log/warn/err` fallbacks ("mirrors lib/config-ui.sh", :18-21); key = filename after `pos-`, category split at first dash (empty when category-less, :66-78); fields cat/desc/flags/subcmds/deps/examples (:11); config scope helpers (:171-186); `reg_each` callback contract cb(cat, key, desc) (:189-194); sorts under `LC_ALL=C` inside `reg_scan` (:50-51,120-125).

## Step 1: AGENTS.md — Tool model bullet (+POS_DEPS/+POS_EXAMPLES/+registry API)

AGENTS.md:17 — extended the header sentence with both optional headers (deps = space-separated runtime binaries hard-required via `command -v` guards; examples = one per line, `<command> | <description>`) and one clause naming `lib/registry.sh` as the shared query API over all `POS_*` headers (`reg_scan` + `reg_list`/`reg_lookup`/…), new consumers to prefer it. Kept the original terse single-bullet style; nothing else in the bullet touched.

[DONE]

## Step 2: AGENTS.md — Categories bullet (`pos tree` metadata source)

AGENTS.md:18 — minimal extension: hierarchy still derives from filenames + `# POS:`/`# POS_SUBCMDS:` headers; now also states it reads metadata through `lib/registry.sh` and annotates declared `# POS_DEPS:`. Matches observable behavior of bin/pos-tree (sources registry.sh:7; `[deps: …]` annotations visible in the generated tree block).

[DONE]

## Step 3: DOC/SCRIPTS.md — Phase 2 lib list + registry section + TOC

a) Phase-2 row — appended `+ lib/registry.sh` after `+ lib/menu-lib.sh`, i.e. LAST in the list, matching `install.sh:143` `lib_names` actual order (… usb-lib share-lib menu-lib registry).

b) New section `## lib/registry.sh — tool metadata query API` inserted between `lib/menu-lib.sh` and the features sections (install order), in the neighbors' File/Purpose/Sourced-by dense-paragraph format. Claims grounded: reg_scan LC_ALL=C + lazy (bin/pos:70 comment), key/category convention, six fields, config-scope helpers, reg_each cb(cat,key,desc) contract, reg_tool_exists, guarded log/warn/err "like lib/config-ui.sh" (:18-21 says it verbatim), no shebang/not executable/installed 644. Consumers listed as bin/pos-tree + bin/pos `_pos_category_help()` only; gen-docs.sh explicitly noted as parsing independently (predates registry).

c) TOC — added `- [lib/registry.sh — tool metadata query API](#libregistrysh--tool-metadata-query-api)` in matching format. Sweep-driven extra (unambiguous staleness INSIDE this item file, authorized by sweep clause): TOC was also missing rows for five sections that already existed in the body (entertainment-lib, user-timers-lib, usb-lib, share-lib, menu-lib) — added those five too, anchors derived by the same slug pattern as existing entries.

[DONE]

## Step 4: MAINTENANCE.md — judgment call

Structure read: Phase 0 authority order / Baseline / Checklist matrix / Lint results / Findings tickets (M-001..M-023, all resolved 2026-08-14) / Deep-dive notes / Next-session brief / Checked & clean. **No phase log or conventions-summary section exists**, so per the brief's escape clause a new section was NOT invented.

However the file is not frozen: its own header instructs "Keep the structure below; **append findings as they land**", and its native dated-record mechanism is exactly one ticket entry ending `Fix (date): …`. Docs-category findings belong under `### P2 — doc drift / consistency / style`. → Added ONE entry, ticket M-024, in the established field set, with the required content: template documents the optional headers (pre-existing), registry.sh added as shared query API, consumers migrated (pos-tree, bin/pos category help), lint unchanged. Nothing else in the file touched.

Deliberately NOT changed: the Checklist line enumerating `# POS_FLAGS:`/`# POS_SUBCMDS:`/`# POS_CONFIG:` — it is a historical snapshot of the audit-time convention matrix ("from AGENTS.md … DEV.md" at audit date), and rewriting completed-audit history isn't standard restoration; M-024 records the current state instead.

[DONE]

## Step 5: Sweep check + gates

Sweep (grep over `DOC/*.md`, `AGENTS.md`, `README.md`, `MAINTENANCE.md` for stale header/consumer claims):

**Findings — outside the fence, reported only, NOT touched:**
1. `DOC/AGENT_Context_Project.md:548` ("Adding a New Tool" step 2, hand-maintained row) — header enumeration lists only `# POS_FLAGS:`/`# POS_SUBCMDS:`; missing both new optional headers.
2. `DOC/AGENT_Context_Project.md:598` (hand-maintained registry.sh filetable row) — says "used by `pos-tree` and `gen-docs.sh`"; **false for gen-docs.sh**, which parses the headers itself (`scripts/gen-docs.sh:47-48`) and never sources the lib (its only "registry" hit is a comment naming the `# POS_CONFIG:` concept). Line count 199 is still correct. This is exactly the "each consumer parses headers itself"-class claim the sweep was told to hunt.
3. `DOC/POS.md:498` — minor: describes `pos tree` data as derived from filenames + `# POS_SUBCMDS:` headers annotated with descriptions; incomplete (no deps annotation / registry mention) but not unambiguously false → left.

**Finding inside the fence — deliberately not fixed:** `MAINTENANCE.md:37` checklist matrix enumerates only the three original headers. It is a historical snapshot of the completed 2026-08-14 audit's convention matrix; current state is recorded by M-024 instead of rewriting audit history.

**In-fence staleness fixed under the sweep clause:** SCRIPTS.md TOC missing 5 pre-existing lib sections (done in Step 3c).

Clean: DOC/DEV.md (already fully updated with headers + registry), README.md and DOC/README.md (no lib/header enumerations), howto/*.

## Gates (tails)

```
$ make gen && git diff --stat   → gen-docs: write OK; diff = my 3 docs + AgentsReport +
                                   pre-existing uncommitted registry-feature work
                                   (bin/*, templates/, scripts/gen-docs.sh, install.sh,
                                   AGENT_Context) — zero drift introduced by this session
$ make check                    → check-sync: OK
$ make lint                     → 0 FAIL, 0 WARN (convention lint)
$ grep -n "POS_DEPS" …          → AGENTS.md:17,18 · DOC/DEV.md:131,134 · DOC/SCRIPTS.md:241 ✓
```

---

Status: MAINTENANCE_COMPLETE

Maintenance objective:
Sync the three agent/convention docs that drifted when the command-registry feature landed; code + `# POS:` headers are ground truth.

Findings addressed:
AGENTS.md Tool-model + Categories bullets (fixed); DOC/SCRIPTS.md Phase-2 lib list + new registry section + TOC (fixed, incl. 5 pre-existing TOC omissions); MAINTENANCE.md record (added as ticket M-024 via the file's own append-findings mechanism).

Standard enforced:
Authority order per MAINTENANCE.md Phase 0 — code + `# POS:` headers ground truth; template/DEV.md codified convention; doc drift in SCRIPTS = doc bug.

Files changed:
AGENTS.md · DOC/SCRIPTS.md · MAINTENANCE.md · AgentsReport/maintainer/2026-08-26_registry-docs-sync.md (nothing else)

Verification performed:
make gen (idempotent, no new drift) · make check OK · make lint 0 FAIL / 0 WARN · POS_DEPS grep present where expected · diffs reviewed line-by-line against intended edits.

Records updated:
This report; MAINTENANCE.md M-024.

Scope compliance:
In-scope corrections + one explicitly-reasoned sweep fix (SCRIPTS.md TOC) inside an item file; out-of-scope changes: none (3 sweep findings reported, untouched).

Remaining / deferred items:
AGENT_CONTEXT :548/:598 + POS.md:498 need a follow-up pass (outside this fence); MAINTENANCE.md:37 checklist left historical by design.

Recommended next agent:
Reviewer — independent adversarial review of the three doc edits before commit (per constraints, nothing is committed).

Changes made by Maintainer:
Smallest corrective doc changes only; no code, no templates, no GEN blocks, no completions.
