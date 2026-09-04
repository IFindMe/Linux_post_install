# Review Report — `pos-ai-hf` GGUF/jq bug fix (2026-09-04)

## TL;DR
- **Verdict:** APPROVE_WITH_NOTES — no BLOCKING or REQUIRED findings. The 3-hunk fix matches the Detective spec exactly; diff is scoped; doc diff is a clean single gen line-count change; harness design is sound; user acceptance evidence confirms the real flow.
- **Findings:** 1 SUGGESTED (harness lacks an error-object/non-array shape test for the very adversarial case this review probed), plus NOTES on AGENT_TODO.md and harness message-checks being code-presence greps.
- **UNVERIFIED (sandbox):** cannot execute bash beyond read-only git/grep — harness 9/9 and `bash -n`/`make check`/`make lint` claims NOT re-run by me; Orchestrator must run them (prior-review convention).
- **Diff verdict:** PASS (3 sanctioned hunks, byte-for-byte per spec; doc = gen row only 495→506).
- **Harness verdict:** PASS on design/structure/fixture integrity; execution UNVERIFIED here.

## Step 1: Inputs & scope — [DONE]
- Spec of record: `AgentsReport/detective/2026-09-04_pos-ai-hf-gguf-jq-bug.md` (Changes 1–3 at Step 4, lines 80–126).
- Builder report: `AgentsReport/builder/2026-09-04_pos-ai-hf-gguf-jq-bug-fix.md`.
- Diff (`git diff bin/pos-ai-hf`): exactly 3 hunks:
  - `bin/pos-ai-hf:201-207` — normalization + comments in `hf_repo_files` primary path.
  - `bin/pos-ai-hf:339` — guarded `--gguf` filter.
  - `bin/pos-ai-hf:346-355` — mode-aware empty-message branch, replaces the old `-gt 0 || err` one-liner.
- Doc diff (`git diff DOC/AGENT_Context_Project.md`): single line, `bin/pos-ai-hf` filetable row 495→506 (`:613`); row sits inside `GEN:START filetable` (612)–`GEN:END` (659) → legitimate `make gen` output; 506 matches actual file length (read: file ends at line 506). No other DOC/GEN changes. Full file integrity further confirmed via `git diff --stat`: only `bin/pos-ai-hf` (15 ins/3 del) + doc (1/1) modified; no other working-tree files.
- POS headers (lines 1–12) untouched; exec bit `100755` (git ls-files -s).

**Step 1 verdict:** [PASS]

## 2: Change 1 — normalization in hf_repo_files — [DONE]
`bin/pos-ai-hf:205`:
`printf '%s' "$result" | jq '[.[] | select(.type == "file") | {rfilename: .path, size: (.size // 0)}]'`
- Literally matches spec line 97 (including comment lines 202-204). Dirs dropped via `select(.type == "file")`; `size` defaulted via `.size // 0`; output shape `{rfilename, size}` per entry.
- Adversarial probe — non-array (HTTP 200 error object `{"error":"x"}`): reasoned (cannot run jq): `.[]` on an object iterates its **values**; each value (string/object) fails `select(.type == "file")` → result `[]`, no jq error → file_count 0 → mode-aware `err` (exit 1). Only a top-level **number/boolean** 200-body would make `.[]` error ("Cannot iterate over number"); the HF tree endpoint never returns that, and `hf_api` (`:172-183`) errs on non-200 and validates JSON. This is exactly the residual accepted in spec line 104 ("graceful error"). No crash path for realistic inputs.
- `set -euo pipefail` interaction: pipe failure would abort the script (spec line 101 explicitly accepts this) — an impossible failure here since `result` passed `jq empty` validation in `hf_api` (`:181`).
- Verified on fixture data (counts, read-only): `fixtures/tree-files.json` = 13 `type:"file"` / 0 dirs / 10 `.gguf` entries; `fixtures/tree-with-dirs.json` = 8 files + 7 dirs — matches spec claims; dirs have `size: 0`, files carry real sizes (incl. LFS 3.98 GB fp16). Schema keys `oid/path/size/type`, no `rfilename` — confirms the bug's premise in the fixture.

**Step 2 verdict**: [PASS] (error-object behavior: STRONG INFERENCE from jq semantics; empirical jq run UNVERIFIED — Orchestrator to run `printf '%s' '{"error":"x"}' | jq '[.[] | select(.type == "file") | {rfilename: .path, size: (.size // 0)}]'` — expected `[]`, rc 0.)

## 3: Change 2 — guarded --gguf filter — [DONE]
`bin/pos-ai-hf:339` matches spec line 108 verbatim. Non-weakening — FACT by construction: `(type)=="string" and endswith(...)` is true-passthrough for every valid-domain input the old `endswith` accepted (strings), and converts the former crash (null/number) into a no-match. With normalized data both guard-on and guard-off select the same 10 — guard is purely defense-in-depth, verified conceptually on the fixture (10 gguf paths present).

**Step 3 verdict:** [PASS]

## 4: Change 3 — mode-aware empty messages — [DONE]
`bin/pos-ai-hf:347-355` matches spec lines 115–125 exactly:
- single-file: `err "File not found: $filename in $repo_id (branch: ${branch})"` — `$filename` only referenced under `-n "$filename"` guard (line 348), no unset risk (`local filename="${SUBCMD_ARGS[1]:-}"` at line 324 keeps it set/empty). Em-dash/text per spec.
- `--gguf`: `err "No .gguf files found in $repo_id${branch:+ (branch: $branch)} — try without --gguf"` — does NOT reference `$filename` (safe in --gguf mode); `${branch:+...}` defensive on empty branch.
- generic: `err "No files to download"` (unchanged).
- Exit semantics preserved: `err` in `lib/common.sh:24` → `exit 1` (verified read-only). No double-printing; single `err` call per branch.

**Step 4 verdict:** [PASS]

## 5: Regression surface — [DONE]
- `git diff` shows hunks only at 201-207, 339, 346-356 — search/list/remove, `hf_search` (216-223), `hf_api` (134-186), `hf_resolve_branch` (244-264), `hf_download_file` (267-289), URL building (387), `--branch` (326), `--output` (114-116) — all byte-identical.
- Only consumer of `files_json`/`hf_repo_files`: `cmd_download` line 330 (`grep hf_repo_files` → definition :188, call :330 — no other caller repo-wide).
- Downstream read sites now receive `{rfilename,size}`: loop (`:383-387`), size `// 0` (`:384`, `:364), meta `[.[]|.rfilename]` (`:409`), summary `.[0].rfilename` (`:423,:425`) — all fit the normalized shape; no downstream edit needed. Shape parity with fallback (`:213` `[.siblings[] | {rfilename, size:(.size//0))}]`) — identical keys `{rfilename, size}`, both numeric sizes. Fallback sizes are 0 (HF metadata API has no sizes — detective Step 1 verified); that's a data, not a shape, difference.
- No `INTERACTIVE_CMDS` impact (pos-ai-hf doesn't read stdin; not in the stdin family).

**Step 5 verdict:** [PASS]

## 6: Harness quality — [DONE]
`/tmp/opencode/hf-test2/run-tests.sh` (read in full; counting/verification of fixtures via wc/grep — I could not *execute* anything, sandbox policy):
- 9 assertions (lines 132-140), all behavioral jq-on-fixture checks except the intent-documented message-branch greps (t_empty:83-95, t_nogguf:98-105 — code-presence because sourcing the tool is a NAK per spec line 149; replicated `file_count` logic; design accepted).
- Not tautological: each asserts a numeric/string result (13/0-nulls sizes, 10 gguf, 1/0 single-file, 13 rows no nulls, `[]`, count 0 rc 0 raw-guard, 8 files 0-`/` paths).
- Drift-guards t_code_sync (124-129) pin all four jq expressions with `grep -F` — they pin presence, not location; divergence from the file breaks the test. Adequate per spec.
- t_defense_guard (108-112) correctly demonstrates non-weakening AND null-proofing on the raw unnormalized fixture (`exit 0`, `[]`).
- Fixture integrity: verified on-disk (13/0/10 and 8+7; `[]`; `[{"type":"file","path":"README.md","size":100}]`).
- **Gap:** no assertion for the adversarial non-array shape (`{"error": "x"}` → normalize → `[]` rc 0, and `--gguf` guard on it → `[]`); also no static fixture for it. Recommend adding (a good SUGGESTED).
- Note: `REPO` hard-coded to the home checkout path (line 10) — fine in place, would need param if the harness is ever committed for CI (out of today's decision boundary).

**Step 6 verdict:** [PASS] (execution UNVERIFIED; design/FACT-checks passed)

## 7: Style / conventions — [DONE]
- `set -euo pipefail` line 2 intact; `# POS:`/POS_FLAGS/DEPS/CONFIG/EXAMPLES headers lines 3-12 unchanged; exec bit 100755 (ls-files -s, pre-commit gate intact by chmod).
- No new dependencies; no unrelated files (add/modify status = only the two expected paths + 2 report artifacts).
- Doc-sync: single gen line-count row, in-GEN-block, actual-sync (506 = line count) — no hand-edit violation.
- **`AGENT_TODO.md` not touched — no task entry was created/moved for this multi-agent task; AGENTS.md asks to move finished tasks to Done. Minor; the Orchestrator can fold a dated Done line into the fix commit. (NOTE)**
- Not runnable here (bash restricted): `bash-nn`, `make gen/check/lint` claimed green by Builder (0 FAIL, 0 WARN) — UNVERIFIED; prior-review convention: Orchestrator runs these.

**Step 7 verdict:** [PASS] with 2 NOTES

## 8: Panic-check the user-visible flows — [DONE] (read-verified; user evidence)
| Flow | Expected after fix | Evidence |
|---|---|---|
| Single-file (`README.md`) | `1` match, real URL | fixture: `select(.rfilename == $fn)` matches a real `path` after NORM; builder live-verified `LICENSE` (7.2 KB, `.hf-meta` correct) |
| All-files | 13 rows, string rfilename | normalized fixture row count 13, 0 nulls in harness; loop `:381-402` safe |
| `--gguf` with gguf repos | 10 files, `[1/10]` progress | user acceptance: `pos ai hf download Qwen/Qwen2.5-3B-Instruct-GGUF --gguf --output ~/.models` → `[1/10] Downloading qwen2.5-3b-instruct-fp16-00001-of-00002.gguf…` (no jq crash) — matches `file_count=10` progress format (`:390-392`) |
| `--gguf` no gguf | `err "No .gguf files found in … — try without --gguf"`, exit 1 | code `:351`; Builder live-verified distilbert |
| Empty repo `[]` | `err "No files to download"` | `:353`; harness t_empty |
| Dirs-only | filtered → `[]` → graceful | NORM `select(.type=="file")`; t_dirs_excluded |

**Step 8 verdict:** [PASS]

## 9: Findings (numbered)
1. **SUGGESTED** — Harness lacks a non-array / error-object shape test (the adversarial probe Section 2). Add a static fixture, e.g. `{"error":"unauthorized"}` (and optionally `null`), with assertions: NORM → `[]`, rc 0; GGUF_FILTER on it → `[]`, rc 0 — the harness would then also pin the graceful-shape property it currently only watches through NORM. Evidence: `run-tests.sh` contains no such case. `Relevant file: /tmp/opencode/hf-test2/run-tests.sh` (lines 36-129). Approved reference: Detective Step 5 ("Tree returning a non-array (code-200 error object) … acceptable; no extra guard"), which the harness should lock in. Why it matters: this review's adversarial probe could only be **reasoned** (cannot run jq), and it is the one untested branch of the new code; low cost to pin.
- **NOTE** — `AGENT_TODO.md` has no entry for this task (head shows empty Now); per AGENTS.md convention a Done-line should be folded into the fix commit. Not defect-scope (the fix commit doesn't exist yet); Orchestrator to fold in at commit.
- **NOTE** — the follow-up `AGENT_TODO.md` / message-branch tests in the harness are grep-presence checks rather than full command runs by design (sourcing is top-level-NAK); behavioral side is covered by Builder+user live evidence.
- **UNVERIFIED** — harness 9/9, `bash -n`, `make gen/check/lint` (green) — this sandbox denies non-git bash execution; couldn't re-run. Builder's claims are internally consistent with the diff and fixtures; user's live run independently corroborates the core fix. Orchestrator runs: `bash /tmp/opencode/hf-test2/run-tests.sh`, `bash -n bin/pos-ai-hf`, `make gen && make check && make lint`, and the error-object jq one-liner from Step 2.

## Verification verified
- Statements contract: Change 1/2/3 match spec line-for-line (verified to file content).
- Shape parity primary↔fallback (identical `{rfilename, size}` keys).
- Scope containment: 15/3 lines in `bin/pos-ai-hf` + 1 DOC row; 3 hunks; no out-of-scope code.
- Exec bit, headers, deps, convention surface unchanged.
- Fixture integrity on disk: 13 (0 dirs, 10 gguf) + 8 files/7 dirs + `[]` + no-gguf; schema proofs the bug premise.
- Exit-1 semantics through `err` (`lib/common.sh:24`).

## Verification unverified
- jq behavior on `{"error":"x"}` (reasoned only: `[]`, rc 0).
- Harness 9/9 run + `make check` and `make lint` (needs Orchestrator).
- Installed `/usr/local/bin` copy byte-identity (user-run success implies fixed code; path check not assessable here).

## Scope compliance
- In-scope: the 3 Changes 1-3 from Detective Step 4 + harness per Step 6. **All present, nothing extra.**
- Out-of-scope found: none (docs/out-of-scope flags — `hf_api` NO `-L` 307 alias handling, non-recursive tree — correctly not touched, deferred following spec Step 2).

## Remaining uncertainty
- Empirical jq semantics on the error-object case judged safe but not executed by me (read-only boundary); one-liner for Orchestrator.
- Orchestrator-significant matters: harness/make execution results as acceptance evidence.

## Recommended next agent
**Orchestrator** — approve-and-commit: stage `bin/pos-ai-hf` + `DOC/AGENT_Context_Project.md` + the two reports; fold a dated AGENT_TODO Done line per convention (NOTE 2); run the 3 harness/gates; optionally attach the error-object jq one-liner (Step 2) to close uncertainty. If any gate candidate genuinely fails, return to Builder within this exact scope (defects would be mechanical, not design).

## Changes made by Reviewer
none (read-only; no repo file modified; only this report written)