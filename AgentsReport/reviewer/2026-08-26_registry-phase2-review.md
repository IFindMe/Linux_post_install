# Reviewer Report — Registry Phase 2 (dispatcher migration + metadata headers)

**Date:** 2026-08-26
**Status:** ACCEPT_WITH_NOTES (gates pending Orchestrator execution)

---

## TL;DR

- **Status:** ACCEPT_WITH_NOTES — Phase 2 delta is correct, faithful to the contract, and free of regressions by code inspection; 0 CRITICAL/HIGH defects.
- **Defects:** 1 MEDIUM (stale hand-maintained 4-column table header left above the now self-headed dispatch GEN block, AGENT_Context_Project.md:275–276), 2 LOW (latent `//`-joiner URL ambiguity; pipe-substitution covers only spaced pipes), 4 NOTE/NIT.
- **Gates:** ALL execution gates UNVERIFIED — sandbox deny-list blocks `bash -n`, `make *`, and running `bin/pos`. Static analysis supports every Builder claim; Orchestrator MUST run the gate battery before commit.
- **Adversarial result on B:** the two gen-docs fixes are genuinely correct in their current form; however the "old paste bug" never existed at HEAD — Builder fixed its own uncommitted intermediate, not a pre-existing repo defect.
- Maintainer overlap safe; Phase 1 leftovers cleanly attributed; no out-of-scope edits found.

---

## Review Inputs

- Contract: `AgentsReport/architect/2026-08-26_registry-architecture.md` (Decisions 2–6; Phase 2 = `_pos_category_help()` migration, `pos help` enrichment, representative headers)
- Handoff under review: `AgentsReport/builder/2026-08-26_registry-phase2.md`
- Prior accepted state: `AgentsReport/reviewer/2026-08-26_registry-review.md` (Phase 1, ACCEPT_WITH_NOTES); `AgentsReport/maintainer/2026-08-26_pos-ai-alias-registration.md`
- Sandbox constraint: bash restricted to read-only git/grep-class commands — **execution gates cannot be re-run by this reviewer**; marked UNVERIFIED where applicable.

## Step 1: Diff attribution & scope compliance

Working tree = cumulative uncommitted Phase 1 + Maintainer + Phase 2 deltas (HEAD `4fd3c37`). Every entry attributed:

| git status entry | Attribution | Evidence |
|------|-------------|----------|
| M `bin/pos` | Phase 2 (dispatcher fn) + Maintainer (INTERACTIVE_CMDS line, uncommitted) | diff has exactly 2 hunks: `_pos_category_help()` rewrite; line 269 adds only `ai-alias` |
| M `bin/pos-network-download` (+4), `bin/pos-media-sync` (+3), `bin/pos-system-backup` (+1), `bin/pos-docker-ps` (+1) | Phase 2 headers only | diff shows header lines only |
| M `scripts/gen-docs.sh` (58±) | Phase 1 extension + Phase 2 fixes (single uncommitted delta) | HEAD has no examples field at all; see Step 3 |
| M `DOC/AGENT_Context_Project.md` (124±) | Phase 2 gen output | tree/dispatch/filetable/docmap GEN blocks |
| M `bin/pos-tree` (18±) | **Phase 1 leftover** — matches Phase 1 review items 5–6 byte-for-byte (source line 7, collection loop → reg_*) | `git diff` inspected |
| M `install.sh` (2±) | **Phase 1 leftover** — lib_names += registry.sh (Phase 1 review item 10) | `git diff` inspected |
| M `templates/pos-tool.sh` (+3) | **Phase 1 leftover** — template header docs (Phase 1 review item 9) | `git diff` inspected |
| ?? `lib/registry.sh` | Phase 1 deliverable (199 lines; content matches Phase-1-reviewed landmarks: reg_scan:48, LC_ALL:51, restore:121–125, key=name:70) → **STRONG INFERENCE** unchanged since Phase 1 acceptance | read + compared to Phase 1 review citations |
| ?? `AgentsReport/` | expected reports | — |

Constraint compliance (Architect Decision 5 + brief §E): `lib/config-ui.sh` ✅ untouched · `completions/pos.bash` ✅ untouched (absent from status) · `INTERACTIVE_CMDS` ✅ only the Maintainer's `ai-alias` token · `lib/registry.sh` ✅ no evidence of post-review change · `bin/pos-tree` ✅ not touched in Phase 2 · `usage()` EXAMPLES in bin/pos ✅ untouched. [STEP PASS]

## Step 2: Dispatcher migration correctness (`_pos_category_help()`)

**Verified by code inspection (bin/pos:68–130 new vs `git show HEAD:bin/pos` old):**

- Lazy load: `source "$self/../lib/registry.sh" 2>/dev/null || source "$self/registry.sh"` + `reg_scan "$self"` at bin/pos:71–72 — INSIDE the function only. [FACT]
- Fast path clean: dispatch order is usage → `pos help` (exec redirect) → `_pos_category_exists` (glob-based, no registry) → registry touched ONLY when `n==1` or `n==2 && -h/--help` (bin/pos:254–258). `pos network download status` never sources registry. [FACT]
- Key mapping: registry keys are full names (`network-download`, lib/registry.sh:70); display shortening via `files+=("${t#"$cat"-}")` (bin/pos:78). Cat derivation `${name%%-*}` / `""` (registry.sh:71–75) matches old glob-strip semantics for every shape incl. nested `share-usb-server` → `usb-server`, `docker-compose-yml` → `compose-yml`. Category-less tools (`config`, `tree`) have `cat=""` and can't reach the function (`_pos_category_exists` requires a `pos-<cat>-*` executable match, bin/pos:59–66). [FACT]
- Desc equivalence: old inline `${d#*— }` ≡ registry-side strip at lib/registry.sh:83 (`_reg_desc[key]="${pos_line#*— }"`). Same em-dash-missing fallback behavior. [FACT]
- Nested enrichment loop (bin/pos:92–105), `is_nested` skip (113–120), `printf '  %-28s%s\n'` layout: byte-identical to pre-migration. Only addition: deps line bin/pos:122. No double-listing path: nested tools still hidden via is_nested; dedupe via `sort -u` retained (bin/pos:80). Ordering: within a category all keys share the `<cat>-` prefix, so LC_ALL=C full-key sort order ≡ old short-name sort order (remainders compared over [a-z0-9-]). [FACT]
- Empty-category robustness: unchanged guard chain; both old glob and new filter yield empty list identically; `mapfile` on empty input identical to before (pre-existing pattern). [FACT]
- Maintainer overlap: INTERACTIVE_CMDS (bin/pos:269) retains `ai-openrouter ai-alias system-schedule` exactly as the Maintainer placed it. [FACT]

Notes: (a) category-help now hard-depends on lib/registry.sh existing (ugly failure if absent post-install — mitigated by install.sh lib_names incl. registry.sh, verified in Phase 1); (b) Builder reports reg_scan ≈1.3 s on this box — help-path latency cost, not a fast-path regression. [STEP PASS]

## Step 3: gen-docs.sh defect fixes (adversarial)

**Fix (a) — pipe→arrow in examples cells** (`sed 's/ | / → /g'` applied to the Examples cell only, rich branch of `gen_dispatch`):
- Rendered output verified in the generated block: AGENT_Context:300 and :303 show valid 6-column rows with arrows; URLs keep their `//`. [FACT]
- Column integrity today: grep over all 41 `# POS:` headers shows **no description contains a raw `|`**, and all current examples use spaced ` | ` per the grammar → no column breaks possible with present data. [FACT]
- Field-splitting safety: `IFS='|' read -r … deps examples` puts remainder-pipes into the LAST var verbatim (bash read semantics) → multi-example strings survive re-parse. [FACT]
- Latent gaps: (i) an example written `cmd|desc` without spaces bypasses the substitution and would break the table; (ii) descriptions are entirely unguarded. No live instance — LOW.
- Cosmetic ambiguity: descriptions already contain literal `→` (`media sync — Incremental Music → USB sync`, matrix-listener `/command → bash`) — indistinguishable from substituted arrows. NOTE.

**Fix (b) — awk joiner replacing paste:**
- Join logic correct: for L1..Ln emits `L1//L2//…//Ln`; single-example case emits L1 unprefixed; empty input yields "" because command substitution strips awk's `END{print ""}` trailing newline — critically this also prevents `_has_deps_examples` false positives on the 39 tools without POS_EXAMPLES. [FACT]
- **Adversarial correction of the narrative:** HEAD's gen-docs.sh has NO paste joiner and NO examples field at all (5-field tools array). The `paste -sd'//'` bug existed only inside Builder's own uncommitted Phase 2 intermediate — it was never a repo defect. The fix itself is sound; the framing slightly inflates its provenance. [FACT via `git show HEAD:scripts/gen-docs.sh`]
- New wart introduced by the chosen separator: example content itself contains `//` (`https://example.com/file.zip`, rendered at AGENT_Context:303), so the join delimiter is lossy/ambiguous for any future consumer splitting on `//`. Non-breaking today. LOW.
- Side benefit: rich mode now emits a proper markdown header+separator row inside the block (resolves Phase 1 review Finding 3 for this state); the `_has_deps_examples=0` else-branch remains header-less (state-dependent format, deterministic either way). NOTE.
- Determinism: pure functions of header text; `sort` runs under exported LC_ALL=C (gen-docs.sh:24). Idempotence logically guaranteed (same inputs → same bytes; docmap convergence loop pre-existing). Empirical double-run NOT executed — UNVERIFIED. [STEP PASS with findings]

## Step 4: Header accuracy vs reality (4 tools)

| Tool | Header | Actual guards (evidence) | Verdict |
|------|--------|--------------------------|---------|
| pos-network-download | `aria2c jq curl` + 3 EXAMPLES | Hard `err` guards lines 14–16 = aria2c, jq, curl; tmux conditional behind `--tmux` flag only (lines 282/312/351/451/483/587) → correctly excluded | ✅ ACCURATE |
| pos-media-sync | `lsblk jq` + 2 EXAMPLES | Hard `err` guards lines 18–19 = lsblk, jq | ✅ ACCURATE |
| pos-system-backup | `tar` only | tar hard `err` line 61; lsblk/jq warn-only "USB copy skipped" + `return 0` lines 73–74; gpg conditional `err` line 180 inside encryption branch (`--no-encrypt` bypasses) → minimal hard-dep declaration is defensible per deps=hard-requirement | ✅ ACCURATE |
| pos-docker-ps | `docker` | Single hard guard line 17 | ✅ ACCURATE |

Examples cross-checked against each tool's usage(): network-download add/status/watch match usage lines 60/59/73; media-sync's two examples are verbatim its own usage() examples (lines 49–50), flags --mp3/--mp4/--dry-run all parsed at lines 207–209. No invented flags/subcommands. [FACT]

Header placement: all inserted after existing POS_* lines, before first code line (architect constraint satisfied). [FACT] [STEP PASS]

## Step 5: Maintainer overlap safety

- `INTERACTIVE_CMDS` (bin/pos:269): `ai-alias` present between `ai-openrouter` and `system-schedule`, exactly as Maintainer placed it; no other token changed (diff hunk = single-line insertion). [FACT]
- `DOC/POS.md`: alias table rows + storage paragraph intact at lines 73–80 (committed at HEAD via `6566c83`; working tree does not touch POS.md). [FACT]
- Builder's claim "Maintainer's fixes untouched" is supported. [STEP PASS]

## Step 6: Gates

| Gate | Builder claim | Reviewer verification |
|------|---------------|----------------------|
| `bash -n bin/pos` / `bash -n scripts/gen-docs.sh` | ✅ | UNVERIFIED — execution denied. Code inspection: no visible syntax hazards; new constructs (`while … done < <(…)`, herestrings, `%*s` with empty width) are valid bash. |
| `make gen && git diff --exit-code` (idempotence) | ✅ | UNVERIFIED empirically. Logically sound: rendering is a pure function of headers under LC_ALL=C; docmap converges via existing loop. |
| `make check` | ✅ OK | UNVERIFIED — execution denied. |
| `make lint` | ✅ 0 FAIL, 0 WARN | UNVERIFIED — execution denied. |
| `bin/pos --help` renders | ✅ | UNVERIFIED; usage()/_pos_category_list() unchanged from accepted state. |
| `bin/pos network --help` shows `[deps: aria2c jq curl]` | ✅ | UNVERIFIED runtime; static trace supports it (deps populated bin/pos:88–89, printed :122 only when non-empty). |
| `bin/pos-tree` annotations + shape | ✅ | UNVERIFIED runtime; pos-tree unchanged this phase (Phase 1 accepted). |
| Fast-path timing ~26 ms unchanged | ✅ | UNVERIFIED. Static proof that fast path never sources registry: dispatch gate at bin/pos:254–258 admits only n==1 or n==2(-h/--help) into `_pos_category_help`; `pos network download status` (n=3) falls straight through to the exec loop. |

**Orchestrator must run the full battery in F before commit.** [STEP BLOCKED: sandbox]

## Findings

### Finding 1 — Stale hand-maintained table header above the dispatch GEN block
**Severity:** MEDIUM · **Certainty:** FACT
**Evidence:** DOC/AGENT_Context_Project.md:275–276 (outside markers) still carry the old hand-written 4-column header `| Category | Command | Script | Description |` + separator; the generator now emits its own 6-column header inside the block (:278–279). The section renders as a dangling empty 4-column header immediately followed by a duplicate complete table.
**Files:** DOC/AGENT_Context_Project.md:275–276; introduced by gen-docs.sh rich-branch header emission.
**Scope ref:** Phase 2 changed gen_dispatch output format; the hand-maintained section around it was not synced (AGENTS.md: drift in hand-maintained doc areas is a doc bug).
**Why it matters:** visible malformed doc structure for every agent/consumer reading §4; `make check` cannot catch it because the stale lines sit outside GEN markers — exactly the drift class this project's gates are blind to.
**Fix:** delete lines 275–276 (2-line hand edit, then `make gen` no-op).

### Finding 2 — `//` join delimiter collides with URLs inside examples
**Severity:** LOW · **Certainty:** FACT (collision), HYPOTHESIS (future impact)
**Evidence:** awk joiner uses literal `//`; network-download example contains `https://example.com/file.zip` — both survive into the cell at AGENT_Context:303. No consumer splits on `//` today.
**Why it matters:** any future parser that splits the Examples cell on `//` will mis-split URLs; a rarer sentinel or newline storage would be lossless.

### Finding 3 — Pipe protection only covers spaced pipes; descriptions unguarded
**Severity:** LOW · **Certainty:** FACT (mechanism), no live instance
**Evidence:** `sed 's/ | / → /g'` (gen-docs.sh, rich branch) converts only space-delimited pipes; a future `# POS_EXAMPLES: cmd|desc` or any description containing `|` emits a raw pipe into a markdown cell and shifts columns. All 41 current descriptions/examples are clean.
**Why it matters:** silent table corruption on first offender; a lint WARN (architect Decision 4 envisioned one) would close it.

### Finding 4 — Arrow substitution cosmetically ambiguous
**Severity:** NOTE · **Certainty:** FACT
Descriptions legitimately contain `→` (`media sync`, matrix-listener) — indistinguishable from substituted example pipes. No structural impact.

### Finding 5 — "Defect fix" provenance: paste bug was Builder's own intermediate
**Severity:** NOTE · **Certainty:** FACT
HEAD's gen-docs.sh never contained the `paste -sd'//'` joiner (no examples field at all until the uncommitted delta). The fixes improve Builder's own in-flight code, which is fine — but the report reads as if pre-existing repo defects were repaired. Trust-calibration note only.

### Finding 6 — Stray untracked files in repo root
**Severity:** NIT · **Certainty:** FACT
`To`, `tmp_request.md`, `reportAgents/`, `opencode_helper/`, `Design-and-implement-a-self-describing-command-registry-for-POS.md` are untracked and unattributed by any report — likely Orchestrator/brief artifacts. Not Builder scope violations ("no new files except report" holds for its own output) but must be cleaned/ignored before commit.

### Finding 7 — Help-path latency + new lib dependency
**Severity:** NOTE · **Certainty:** UNVERIFIED (measurement), FACT (dependency)
Builder reports reg_scan ≈1.3 s on this box (vs architect's ~5 ms estimate) — borne only by `pos <cat> [--help]`. Also, category-help now hard-requires lib/registry.sh at runtime; installed layout is covered (install.sh lib_names includes registry.sh).

## Verdict

**ACCEPT_WITH_NOTES**

The Phase 2 delta does what the contract says: the dispatcher migration is provably behavior-preserving except for the intended `[deps: …]` lines; all four header annotations are accurate against actual guards with real-subcommand examples; the two gen-docs fixes render correctly on current data; Maintainer/Phase 1 work is untouched; scope is clean. Findings 1–3 are small follow-ups (Finding 1 should land before commit); none blocks acceptance of the code. Final acceptance is conditional on the Orchestrator running the gate battery this sandbox could not execute.

**Defect count:** CRITICAL 0 · HIGH 0 · MEDIUM 1 · LOW 2 · NOTE/NIT 4

---

## Handoff

**Status:** ACCEPT_WITH_NOTES
**Objective/problem:** verify Phase 2 (dispatcher migration, metadata headers, gen-docs fixes) against Architect Decisions 2–6 and the review brief.
**Evidence/completed work:** Steps 1–6 above; every git-status entry attributed; static equivalence proof for `_pos_category_help()`; adversarial validation of both gen-docs fixes.
**Affected areas:** bin/pos, scripts/gen-docs.sh, 4 tool headers, generated DOC blocks (+ pre-existing Phase 1/Maintainer working-tree deltas).
**Scope/decision boundary:** all changes within approved Phase 2 scope; no out-of-scope edits found; Reviewer made no changes.
**Verification performed:** full static analysis incl. HEAD-vs-worktree diffs, registry semantic checks, guard/header cross-checks, rendered-output inspection.
**Remaining uncertainty:** all execution gates (bash -n, make gen/check/lint idempotence round-trip, runtime outputs, timing) UNVERIFIED — sandbox deny-list.
**Recommended next agent:** Builder (2-line Finding 1 fix + optionally address Finding 2/3 hardening), then **Orchestrator** runs gates F and commits.
**Reason:** defects found are within approved scope and mechanically trivial; nothing requires redesign or investigation.

Changes made by Reviewer: none (this report file only).
