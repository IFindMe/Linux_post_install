# Reviewer Report — POS AI tooling (hf / server enhancement + llamacpp forwarder)

Date: 2026-09-06
Reviewer: independent (read-only) reviewer
Reviewed refs: working tree `0856b25` (HEAD = master baseline `0856b25`) + uncommitted maintainer changes

## TL;DR

- **Status:** CHANGES_REQUIRED
- **Verdict:** The `llamacpp` forwarder + dispatch + docs + completions work is APPROVABLE. The enhanced `pos-ai-hf` and `pos-ai-server` contain two BLOCKING correctness failures and several REQUIRED defects. The approval gates (`make gen` / `make check` / `make lint`) were NOT RUN in this review (see Step 6 — sandbox blocked, UNVERIFIED).
- **Defect counts:** 2 BLOCKING, 5 REQUIRED, 4 SUGGESTED, 2 NOTE.
- Primary defects: (1) `pos ai hf download --include/--exclude` can never complete a download (jq stream-vs-array + glob-vs-regex + raw interpolation); (2) `pos ai server start` generates a malformed systemd unit (flags appended as non-continued lines) — `enable --now` cannot work; regression vs the pre-enhancement inline heredoc.
- **Next agent:** Builder (fixes understood, in-scope), then Orchestrator to run gates + live verification.

---

## Step 1: Contract & scope

Read and cross-checked against the named inputs: `AUDIT.md`, `AUDIT_TABLE.md`, `IMPLEMENTATION_PLAN.md`, `FINAL_SUMMARY.md`, `AgentsReport/builder/2026-09-05_enhanced_pos_ai_tools.md`, `AgentsReport/builder/2026-09-06_llamacpp-forwarder.md`, `AgentsReport/maintainer/2026-09-06_restore-cleanup.md`, `AgentsReport/maintainer/2026-09-06_convention-sweep.md`.

- Every hunk in the tree diff traces to an approved plan item (hf patterns, parallel download, cache, info/files, server GPU/flags/version-awareness, llamacpp forwarder, docs/completions regen).
- FINAL_SUMMARY honestly discloses `cache` and version-feature-validation as stubs.
- No invented out-of-scope files: the tree diff touches exactly `bin/pos`, `bin/pos-ai`, `bin/pos-ai-hf`, `bin/pos-ai-llamacpp` (new), `DOC/*`, `completions/pos.bash`, `AGENT_TODO.md`.

[PASS]

## Step 2: Work tree & git history

- `git status --short`: modified `AGENT_TODO.md`, `DOC/AGENT_Context_Project.md`, `DOC/POS.md`, `DOC/howto/ai.md`, `bin/pos`, `bin/pos-ai`, `bin/pos-ai-hf`, `completions/pos.bash`; untracked `AUDIT{,.md,_TABLE.md}`, `FINAL_SUMMARY.md`, `IMPLEMENTATION_PLAN.md`, `AgentsReport/*`, `bin/pos-ai-llamacpp`. Matches the maintainer/builder reports; `bin/pos-ai-server` unchanged in tree (committed in `0856b25`).
- `git log --oneline -15`: `0856b25` enhance pos-ai-server/hf, `387f23f` parallel download, `2794122` server flags, `99c033c` base hf, `5e312b3` base server.
- `git diff 0856b25~1..0856b25` (ablated) and `git diff 2794122 387f23f`:
  - Confirmed regression: pre-enhancement `branch="$(hf_resolve_branch "$repo_id" "$BRANCH")"` was changed to `"$REVISION"` (now dead `--branch` flag, see F3).
  - Confirmed include/exclude block, parallel block, cache stub, dead `err_with_context`/`run_parallel_download`, and the duplicate `# POS_EXAMPLES:` lines (3) later removed by the maintainer.
  - Confirmed server-side: `5e312b3` had a correct **single-line** `ExecStart=… --n-gpu-layers $gpu_layers --ctx-size $CTX_SIZE --threads $THREADS` inside the heredoc; the enhancement replaced it with a truncated heredoc + line-by-line `echo >>` flag appends (F2).

[PASS]

## Step 3: llamacpp forwarder, dispatch, completions, docs sync

- `bin/pos-ai-llamacpp` (7 lines) matches `bin/pos-ai-gemini` byte-for-byte except provider name; `-h|--help` → `exec pos ai --provider llamacpp --help`; exec fallthrough. `# POS_SUBCMDS: ask chat models sessions capture` exactly matches `lib/ai-providers/llamacpp.sh` capabilities (provider_generate ask/chat/sessions/capture; provider_models_list models).
- `bin/pos-ai:701-704` adds the `llamacpp)` shorthand case → `exec "$0" --provider llamacpp "${args[@]}"`; usage lines 42/59/81 mention `llamacpp`; POS_CONFIG lists `AI_PROVIDER` incl. `llamacpp` + `LLAMACPP_*` vars (line 6).
- `bin/pos:269` INTERACTIVE_CMDS includes `ai-llamacpp` (stdin/tee gotcha respected; dispatcher longest-prefix resolution picks `pos-ai-llamacpp` length 12 > `pos-ai` length 2).
- `completions/pos.bash:33` `_pos_subcmds[ai-llamacpp]="ask chat models sessions capture"`, line 51 `[ai]` includes `llamacpp` — matches the forwarder header.
- `DOC/AGENT_Context_Project.md`: tree row 68, dispatch row 287, selfcontained row 374, filetable row 619 all consistent; hf dispatch row 286 lists exactly 11 examples matching the 11 `# POS_EXAMPLES:` lines in `bin/pos-ai-hf`; filetable rows 618/619/621 (hf 912 / llamacpp 7 / server 613) match `wc -l`; docmap + line-count rows updated.
- `DOC/POS.md:58-59,72,82,90` and `DOC/howto/ai.md:5,19,30-31,139` include llamacpp consistently.

[PASS]

## Step 4: pos-ai-hf correctness

Read the full file (912 lines). Verified working paths: search API/retry, explicit filename (`--arg fn`), GGUF filter + quant gate + pagination, list/remove/info/files, `.hf-meta`. FAILURES listed in Findings F1, F3, F4 (and S7/S8).

[FAIL]

## Step 5: pos-ai-server correctness

Read the full file (613 lines). Verified working logic: GPU precedence is correct (`--gpu-layers` flag > env/config > auto, lines 376-379; `resolve_gpu_layers` 72-85), health-check, model picker (reads `/dev/tty`, not stdin). FAILURES listed in Findings F2, F5 (S8).

[FAIL]

## Step 6: Conventions, gates, maintainability

Static convention checks (by reading `scripts/lint-conventions.sh`, `scripts/check-sync.sh`, `make gen` inputs):

- Shebang, `set -euo pipefail`, `# POS:` headers with `—`, exec-bit (100755), `-h|--help` after deps guards: all present in the touched files; `DOC/POS.md` references all four scripts; `ai-llamacpp` in INTERACTIVE_CMDS; no stdin readers missing; no `local` at top level; heredoc delimiters balanced; no secret literals; no raw `/etc/`/`/usr/local` writes found statically.
- Generated blocks (`tree`, `dispatch`, `selfcontained`, `filetable`, `docmap`, `completions`) are internally consistent with headers — no hand-edit evidence.
- **BLOCKED:** `bash -n`, `make gen --check`, `make check`, `make lint` CANNOT be run in this sandbox (bash tool permission denies every command outside the git/head/tail/wc/sort/grep/rg allow-list). Claims of green gates are UNVERIFIED.
- Maintainability: F4 dead code (`run_parallel_download`, `hf_download_file`, `err_with_context`, `temp_dir`) is avoidable complexity introduced by the change.

[BLOCKED: sandbox denies `bash`/`make` execution — required verification must be run by Orchestrator/Builder outside this review]

## Step 7: Documentation accuracy

- llamacpp/ai docs: accurate (see Step 3).
- hf docs: `DOC/POS.md:108` documents `--branch <rev>` as a working option — **false**, the flag is dead (F3). `DOC/POS.md` omits `--include/--exclude/--revision`; `DOC/AGENT_Context_Project.md:286` showcases `--include "*.gguf" --exclude "*Q4_*"` — the showcased example cannot work (F1).

[FAIL]

## Step 8: Verdict synthesis

The approved scope is only partially met: the llamacpp forwarder work is complete and correct; the hf/server enhancements carry BLOCKING correctness defects and shortfalls in the plan's own matrix (cache stub, version-feature-validation stub). Both BLOCKING items are in-scope implementation defects with understood fixes → Builder.

[FAIL]

---

## Findings

### F1 — BLOCKING — `pos ai hf download --include/--exclude` can never complete a download

- Severity: BLOCKING
- Evidence: `bin/pos-ai-hf:600-614` builds filters as jq **streams**: `include_filter=".[] | select(.rfilename | match(\"$INCLUDE_PATTERN\"; \"i\") | length > 0)"` (line 606) and the exclude analog (612). A stream of objects is then consumed by array-expecting code:
  - Line 621 `file_count="$(… | jq 'length')"` — `length` applied per input object → key count ("2\n2" for ≥ 2 matches) → `[ "$file_count" -eq 0 ]` at 622 errors "integer expression expected" → `set -e` exit; with exactly 1 match `file_count="2"` → line 662 `[ "$file_count" -gt 1 ]` misroutes the single file into the parallel branch.
  - Parallel branch (661-702) reads via `jq -c '.[]'` which, on an object-stream input, yields the object **values** (strings/numbers); `fname="$(… | jq -r '.rfilename')"` then fails ("Cannot index string with .rfilename") → `set -e` exit.
  - `total_size` at 644 also assumes an array (`[.[].size // 0]`).
- Interpolation: patterns are embedded verbatim into the double-quoted jq program (no `--arg`, lines 606/612) — quotes/`$`/backslashes in a pattern corrupt the program.
- Glob-vs-regex: usage/`# POS_FLAGS:`/POS.md/AGENT_Context all advertise glob patterns (`*.gguf`); `match()` applies **regex** semantics, and `*.gguf` is an invalid regex (leading quantifier) under jq's regex engine → jq error even before the stream issue.
- Relevant files/lines: `bin/pos-ai-hf:600-614, 621-622, 644, 661-702`; `DOC/AGENT_Context_Project.md:286`.
- Approved scope reference: IMPLEMENTATION_PLAN "Filtering (include/exclude patterns)"; FINAL_SUMMARY claims "pattern-based filtering".
- Why it matters: the flagship documented example of the enhancement crashes on every invocation; core download feature partially unusable; misleading docs.

### F2 — BLOCKING — `pos ai server start` generates a malformed systemd unit (flags never reach llama-server)

- Severity: BLOCKING
- Evidence: `bin/pos-ai-server:403-411` heredoc writes only `ExecStart=$llamacpp_full -m $model --port $PORT --host $HOST` and closes with `EOF` at line 411. Lines 414-464 then append each flag as its own line with a 2-space indent and **no trailing `\`**: `echo "  --n-gpu-layers $gpu_layers" >> …` (415), `--ctx-size` (418), `--threads` (421), `--gpu-threads` (424), `--tensor-split` (427), `--batch-size` (430), `--ubatch-size` (433), `--temperature` (436), `--top-k` (439), `--top-p` (442), `--repetition-penalty` (445), `--mmap` (448), `--mlock` (451), `--kv-cache` (454), `--metrics` (457), `--health` (460), `--slots` (463). systemd.service(5) requires a trailing `\` for continuation; these lines are invalid unit syntax and are never passed to llama-server. `gpu_layers` is always non-empty (`resolve_gpu_layers` returns a number/layer count; 377-379), so the first broken line is always appended; line 467 `Restart=on-failure` is similarly misplaced outside `[Service]`-continuation.
- Regression: `git show 5e312b3:bin/pos-ai-server` had a single valid inline `ExecStart=… --n-gpu-layers $gpu_layers --ctx-size $CTX_SIZE --threads $THREADS` inside the heredoc; the enhancement (0856b25, confirmed in its diff) replaced it with this broken scheme.
- Dry-run output (line 396) shows the *intended* single-line command, masking the defect.
- Relevant files/lines: `bin/pos-ai-server:403-467`.
- Approved scope reference: IMPLEMENTATION_PLAN "systemd unit generation with new flags".
- Why it matters: `systemctl --user enable --now` fails or starts a flagless server; GPU layers/ctx/threads/sampling options silently never apply — the core feature of the enhancement.

### F3 — REQUIRED — `pos ai hf --branch` regressed to a dead flag; docs still claim it works

- Severity: REQUIRED
- Evidence: `bin/pos-ai-hf:112,126` parse `--branch` into `BRANCH`, but the only two consumers use `REVISION`: lines 566 and 881 `branch="$(hf_resolve_branch "$repo_id" "$REVISION")"`. `git diff 0856b25~1..0856b25` shows the regression (`$BRANCH` → `$REVISION`). `DOC/POS.md:108` documents `--branch <rev>` as functional.
- Related guard quirk: the parse-loop guard errors only when **both** `--include` and `--exclude` are set with `--gguf`; `--gguf --include "pat"` (include only) silently drops filtering (code at ~107-110 guard; GGUF branch 595-599 runs, include ignored) — include-only and exclude-only are each valid intents.
- Relevant files/lines: `bin/pos-ai-hf:112,126,566,881`; `DOC/POS.md:108`.
- Approved scope reference: existing documented option; convention "no stale flags".
- Why it matters: doc-vs-code contradiction; users passing `--branch` silently get the default branch; violates stale-flag convention.

### F4 — REQUIRED — parallel download aborts the entire batch on the first failed file and orphans remaining jobs; dead machinery shipped

- Severity: REQUIRED
- Evidence: `bin/pos-ai-hf:686` `wait "${job_pids[0]}"` (and 696 `wait "$pid"`) return the background job's exit status; under `set -euo pipefail` a single failed download (404 shard, network blip) terminates the whole command at 686, leaving the remaining background jobs running detached and `.hf-meta` unwritten. Helpers `run_parallel_download` (509-517), `hf_download_file` (449-470), `err_with_context` (400-409), and `temp_dir` (663-664, 702) are dead code; progress text (688-690 area) prints the just-started `$fname`, not the completed job.
- Relevant files/lines: `bin/pos-ai-hf:661-702, 400-409, 449-470, 509-517`.
- Approved scope reference: IMPLEMENTATION_PLAN "parallel downloads with failure handling".
- Why it matters: failure path is exactly what a downloader must survive; misleading progress; avoidable complexity (lint/maintainability).

### F5 — REQUIRED — `pos ai server status` crashes when `llama-server` isn't installed (or isn't named literally); version-feature validation is a print-only stub

- Severity: REQUIRED
- Evidence: `detect_llama_version` (50-54) is `version="$(llama-server --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"`; under `set -euo pipefail` a missing binary (127) or non-matching output (1) makes the substitution fail and, via the caller `version="$(detect_llama_version)"` at 568 (cmd_status) and 363 (cmd_start), the script exits instead of printing `version: unknown` (569-573 intended). `find_llamacpp` (40-47) can resolve to `server`/`llama.cpp/server`/`llama-server-cuda`, but the version probe still hardcodes `llama-server` → `start` too can crash even when a server binary exists. `validate_server_features` (57-61) prints "Feature validation would occur here" — the plan's "reject unsupported flags" behavior is not implemented for any flag.
- Relevant files/lines: `bin/pos-ai-server:40-61, 363-366, 568-573`.
- Approved scope reference: IMPLEMENTATION_PLAN/AUDIT_TABLE "version detection + validate feature support".
- Why it matters: status must never crash (esp. on a fresh box without llama.cpp); claimed safety gate is cosmetic.

### F6 — REQUIRED — approved-scope shortfalls: `hf cache` and server feature-validation are stubs

- Severity: REQUIRED
- Evidence: `bin/pos-ai-hf:897-900` `cmd_cache` prints "not fully implemented yet" (and is indented 4 spaces at top level — style drift that the `local`-depth lint rule tolerates but should not ship); version validation stub (F5). Disclosed honestly in FINAL_SUMMARY/AGENT_TODO, but the plan named both as deliverables.
- Relevant files/lines: `bin/pos-ai-hf:897-900`; `bin/pos-ai-server:57-61`.
- Approved scope reference: IMPLEMENTATION_PLAN (cache management, feature validation).
- Why it matters: scope is incomplete; either implement or record explicit deferral with owner.

### S7 — SUGGESTED — pattern-filter UX gaps and doc incompleteness

- Severity: SUGGESTED
- Evidence: `--list`/`files` modes ignore `--include/--exclude` (573-581, 876-895); single-file mode ignores patterns too (586-594); guard requires both flags (F3); `DOC/POS.md` omits the new flags (only usage + AGENT_Context carry them); `hf_gguf_quant_gate` added an unreachable empty-json guard (333-358).
- Why it matters: feature boundaries are undocumented and inconsistent; does not block acceptance of the happy paths.

### S8 — SUGGESTED — minor code cleanliness in pos-ai-server

- Severity: SUGGESTED
- Evidence: trailing `echo "  "` (466) appends a blank line to the unit; `resolve_gpu_layers` auto-CUDA returns `-1` which the docs describe as "(-1=auto)" — consistent but worth a comment; dry-run log (396) diverges from what the unit contains (already F2-related).
- Why it matters: none blocking; housekeeping.

### N9 — NOTE — approval gates unverified in this review

- Severity: NOTE
- Evidence: sandbox denies `bash`/`make` (Step 6). Claims "check green / lint 0 WARN" come from maintainer reports, not from an observed run here.
- Why it matters: merge-blocker status cannot be confirmed until gates are actually run.

### N10 — NOTE — GPU precedence logic itself is correct

- Severity: NOTE
- Evidence: `bin/pos-ai-server:376-379` + 72-85: flag > env/config > auto, matching docs. Currently unreachable in effect because of F2.
- Why it matters: builder's claim "GPU precedence works" is TRUE as logic; it is the unit file that breaks the outcome.

---

## Verification verified

- Working-tree diff exactly matches maintainer reports (positional, content, line counts).
- `--branch` regression introduced by 0856b25; include/exclude + parallel + cache blocks introduced by 0856b25/387f23f.
- Forwarder = byte-for-byte mirror of gemini pattern; SUBCMDS consistent with `lib/ai-providers/llamacpp.sh`; dispatch case; INTERACTIVE_CMDS entry; completions; AGENT_Context tree/dispatch/selfcontained/filetable/docmap; POS.md/howto ai-llamacpp rows.
- `bin/pos``/bin/pos-ai` llamacpp wiring (lines 269, 701-704) verified by direct read.
- Static lint-relevant conventions (headers, guards, `-h|--help` position, heredocs, no stdin gaps, no secret literals) hold for the touched files.

## Verification unverified

- `bash -n` on `bin/pos-ai`, `bin/pos-ai-hf`, `bin/pos-ai-server`, `bin/pos-ai-llamacpp` (sandbox denies bash).
- `make gen` idempotency (`git diff --exit-code` after regen).
- `make check` (check-sync: bash -n + exec-bit + doc-sync + dispatch smoke).
- `make lint` (0 FAIL / 0 WARN claim).
- Live behavior of F1/F2/F4/F5 (jq stream/glob semantics, systemd unit parse, `wait`+errexit) — my certainty levels: F1 stream/array and F2 unit syntax are FACT by code reading and bash/jq/systemd semantics; F4 `wait` semantics FACT per bash manual; F5 errexit-in-substitution STRONG INFERENCE. All four can be empirically confirmed via the gates + one `pos ai hf download --include "*.gguf"` and one `pos ai server start` probe.

## Scope compliance

- In-scope, correctly implemented: llamacpp forwarder + dispatch + docs/table/completions; hf search/explicit-file/GGUF/list/remove/info/files happy paths; server GPU precedence logic, autostart/model-picker helpers.
- In-scope, defective: hf include/exclude (F1), hf parallel failure path (F4), server unit generation (F2), server version handling (F5).
- In-scope, not delivered: cache command, server feature-validation (F6).
- Out-of-scope changes: none found.

## Remaining uncertainty

- Gate results (Step 6) — pending Orchestrator/CI run.
- Whether pattern matching should be glob or regex going forward — decision for Architect/Builder; current code contradicts its own docs either way.
- Exact `wait`/errexit or `match()` behavior under the machine's jq/bash version — empirical confirmations pending.

## Recommended next agent

**Builder**

**Reason:** Two BLOCKING defects (F1, F2) are clear in-scope implementation bugs with understood fixes (array-preserving jq filters + `--arg` + glob-vs-regex decision; single-line heredoc ExecStart with `\` continuations as in the 5e312b3 baseline). F3/F4/F5 are fixable in the same pass. After fixes, re-run `make gen`/`make check`/`make lint`, then Orchestrator performs the live probes (include/exclude download, `server start` unit parse + `--user` enable, one forced-failure parallel download, `server status` without llama-server) and re-hands to Reviewer for final sign-off.

## Changes made by Reviewer

none