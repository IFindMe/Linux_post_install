# Maintainer Report — 2026-09-06 — restore-cleanup (README + pos-ai-hf dedupe + ledger)

## TL;DR

- Drift 1: working-tree `README.md` was overwritten with an internal optimization-plan document; must be restored to the committed user-facing README.
- Drift 2: `bin/pos-ai-hf` has duplicated `# POS_EXAMPLES:` header lines (3 repeats of the last 3 examples) → duplicated rows in the generated dispatch table (`DOC/AGENT_Context_Project.md`).
- Corrections: `git checkout -- README.md`; removed exactly 3 duplicate `# POS_EXAMPLES:` lines; regenerated + verified.
- Validation: `make gen` idempotent, `make check` OK, `make lint` 0 FAIL / 0 WARN.
- Ledger: added 3 dated Done entries to `AGENT_TODO.md` (09-05 hf parallel+advanced, 09-05 server advanced options, 09-06 llamacpp forwarder).
- Scope compliance: README + `bin/pos-ai-hf` (3 lines) + `AGENT_TODO.md` + generated files touched; no behavior changes; no commit (per brief).

## Step 1: Restore `README.md`

- Finding: working-tree `README.md` was an internal optimization-plan document ("Linux_post_install - AI Hugging Face Tool Optimization"), not the committed user-facing README.
- Evidence: `git diff README.md` showed the entire file replaced (committed 53 lines → plan doc).
- Correction: `git checkout -- README.md`; verified `git diff --exit-code -- README.md` rc 0 and `git status --short` no longer lists README.md. First line restored: `# Linux_post_install — Personal Bootstrap & Homelab Toolkit`.

Status: [DONE]

## Step 2: Dedupe `bin/pos-ai-hf` `# POS_EXAMPLES:` headers

- Finding: lines 18–20 duplicated lines 15–17 verbatim (info / files / download-include-exclude), so the generated dispatch table showed each example twice.
- Correction: removed exactly the 3 duplicate lines. `git diff bin/pos-ai-hf` shows only that deletion (3 lines, nothing else touched). 11 unique `# POS_EXAMPLES:` lines remain (7–17), order unchanged, `uniq -d` across them = 0.
- Body (source `…`, deps guards, subcommands, usage) untouched.

Status: [DONE]

## Step 3: Regenerate + gate verification (`make gen` / `make check` / `make lint`)

- `make gen` → `gen-docs: write OK`.
- `make check` → `check-sync: OK`.
- `make lint` → **0 FAIL, 0 WARN (convention lint)**, rc 0.
- Idempotency: second `make gen` run produced byte-identical `completions/pos.bash` + `DOC/AGENT_Context_Project.md` (md5sum compare OK) → no drift.

Status: [DONE]

## Step 4: Confirm dispatch table no longer duplicates examples

- `DOC/AGENT_Context_Project.md:286` (ai | hf dispatch row) now lists exactly 11 `pos ai hf` example bullets, each once.
- Previously-duplicated rows counted across the generated doc: `Show repository information` = 1, `List repository files` = 1, `Download with include/exclude patterns` = 1 (were 2 each).

Status: [DONE]

## Step 5: Update `AGENT_TODO.md` Done ledger

- Added exactly 3 dated Done entries at the top of the `## Done` section (same placement practice as commit 2794122), ordered oldest→newest with the newest last per brief:
  1. **2026-09-05** — `pos ai hf` parallel downloads (`PARALLEL_DOWNLOADS=4`) + advanced features (`info`/`files`, `--include`/`--exclude`, `--revision`, refactored quant gate, cache stub) from commits 387f23f + 0856b25, with verification.
  2. **2026-09-05** — `pos ai server` advanced options from commit 0856b25 (GPU offload / batch / sampling / endpoints / memory flags, version awareness), with verification.
  3. **2026-09-06** — `pos ai llamacpp` forwarder + provider shorthand (`bin/pos-ai-llamacpp`, `bin/pos-ai` dispatch case, INTERACTIVE_CMDS, POS.md hand-edits), with verification.
- No existing ledger lines deleted or rewritten. `git diff AGENT_TODO.md` = 6 insertions only.

Status: [DONE]

## Deferred / notes

- Pre-existing working-tree modifications from other agents (`bin/pos`, `bin/pos-ai`, `DOC/POS.md`, `completions/pos.bash`, `DOC/AGENT_Context_Project.md`, untracked `bin/pos-ai-llamacpp` + plan docs) were present before this task; untouched by this maintenance pass (Builder's scope, already green).
- `AUDIT.md` / `AUDIT_TABLE.md` / `FINAL_SUMMARY.md` / `IMPLEMENTATION_PLAN.md` in the working tree look like the leftover optimization-plan documents; noted only (out of scope — could be removed by Orchestrator decision, not by this brief).
- No commit made (per brief — Orchestrator integrates and commits after verification).

## Completion handoff

Status: MAINTENANCE_COMPLETE

Maintenance objective:
- Restore the committed user-facing `README.md`; dedupe the repeated `# POS_EXAMPLES:` header lines in `bin/pos-ai-hf`; regenerate + verify all gates; ledger the completed AI-tool work in `AGENT_TODO.md`.

Findings addressed:
- README.md overwritten in working tree → restored via `git checkout -- README.md`; `git diff --exit-code -- README.md` empty (rc 0).
- `bin/pos-ai-hf` 3 duplicated `# POS_EXAMPLES:` lines (18–20 = repeats of 15–17) → removed exactly those 3; 11 unique examples remain, order unchanged.
- Generated dispatch table `DOC/AGENT_Context_Project.md:286` now lists each example once (previously 2× for info/files/include-exclude rows).

Standard enforced:
- Committed HEAD is authoritative for `README.md`; `# POS_EXAMPLES:` header rule (one line per example, no verbatim repeats) feeds `make gen` tables.

Files changed:
- `README.md` (restored to HEAD, no diff)
- `bin/pos-ai-hf` (−3 duplicate `# POS_EXAMPLES:` lines only)
- `DOC/AGENT_Context_Project.md`, `completions/pos.bash` (regenerated via `make gen`)
- `AGENT_TODO.md` (+3 Done entries)
- `AgentsReport/maintainer/2026-09-06_restore-cleanup.md` (this report)

Verification performed:
- `make gen` → write OK; second run byte-identical (md5sum match) → idempotent, no drift.
- `make check` → `check-sync: OK`.
- `make lint` → **0 FAIL, 0 WARN (convention lint)**, rc 0.
- Dispatch table counts: `Show repository information` = 1, `List repository files` = 1, `Download with include/exclude patterns` = 1; total `pos ai hf` example bullets = 11.

Records updated:
- `AGENT_TODO.md` Done section (3 dated entries, newest last within the batch; 6 insertions, no deletions).
- Maintainer report (this file).

Scope compliance:
- In-scope corrections only (`README.md`, 3 header lines in `bin/pos-ai-hf`, generated files, ledger, report). Out-of-scope changes: none. `bin/pos-ai`, `bin/pos-ai-llamacpp`, `bin/pos-ai-server` untouched per constraint.

Remaining / deferred items:
- Plan-document files in the working tree (`AUDIT.md`, `AUDIT_TABLE.md`, `FINAL_SUMMARY.md`, `IMPLEMENTATION_PLAN.md`) — not part of this brief; Orchestrator may delete or commit them.
- None from this maintenance objective.

Recommended next agent:
- Orchestrator

Reason:
- All corrections verified and gates green; per the brief no commit was made — the Orchestrator integrates and commits these changes.

Changes made by Maintainer:
- `git checkout -- README.md` (restore committed standard).
- Deleted 3 duplicate `# POS_EXAMPLES:` lines in `bin/pos-ai-hf`.
- `make gen` regeneration (idempotent) of generated docs/completions.
- 3 dated entries appended to `AGENT_TODO.md` Done section.
- Report written to `AgentsReport/maintainer/2026-09-06_restore-cleanup.md`.