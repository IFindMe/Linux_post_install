# Reviewer Report — Re-review of Builder fixes F1–F6 + llamacpp wiring + maintainer doc corrections

Date: 2026-09-06
Reviewer: independent (read-only) reviewer
Reviewed refs: working tree over HEAD `0856b25` (diff above) + untracked `bin/pos-ai-llamacpp`
Inputs read: my previous review (`2026-09-06_pos_ai_full_review.md`), Builder fix report (`2026-09-06_review-fixes.md`), Maintainer sweep (`2026-09-06_convention-sweep.md`), AGENTS.md, `DOC/DEV.md` via lint/check scripts, `lib/ai-providers/llamacpp.sh`, `lib/common.sh`, `scripts/lint-conventions.sh`, `scripts/check-sync.sh`.

## TL;DR

- **Status:** REQUEST_CHANGES (this is a re-review of in-progress work before commit — not final acceptance)
- **Verdict:** F1, F3, F5, F6 are FIXED; F2 is PARTIAL (core BLOCKING unit defect fixed, but ExecStart does not quote the model path — paths with spaces still break); F4's failure handling is FIXED but a new REQUIRED honesty defect (misleading summary/`.hf-meta` after partial failure, exit 0) must be fixed. llamacpp wiring and maintainer doc corrections PASS.
- **Defect counts this pass:** 2 REQUIRED, 2 SUGGESTED, 2 NOTE. No BLOCKING findings remain.
- **Gates:** `bash -n`, `make gen` idempotency, `make check`, `make lint`, `systemd-analyze verify` — **UNVERIFIED** (sandbox denies bash/make; denial quoted in Step 8). Static reading of lint/check rules shows no violation in the touched files.
- **Next agent:** Builder (two small, understood, in-scope fixes), then Orchestrator to run gates + live probes and re-hand for final sign-off.

---

## Step 1: Contract scope re-check

Named review inputs: previous review findings F1–F6; Builder's fix report; Maintainer convention sweep; AGENTS.md/DEV.md conventions; the FULL pending diff (`git diff HEAD` = working tree over baseline `0856b25`).

- Diff touches exactly: `AGENT_TODO.md`, `DOC/AGENT_Context_Project.md`, `DOC/POS.md`, `DOC/howto/ai.md`, `bin/pos`, `bin/pos-ai`, `bin/pos-ai-hf`, `bin/pos-ai-server`, `completions/pos.bash` + untracked `bin/pos-ai-llamacpp` and plan/report files (Orchestrator decision, out of review scope). No out-of-scope source changes found.
- Builder scope claim ("no changes to bin/pos-ai, bin/pos-ai-llamacpp, bin/pos, README, AGENT_TODO") — **contradicted by the actual diff**: `bin/pos`, `bin/pos-ai`, `AGENT_TODO.md` ARE modified. These are the Maintainer's corrections (usage provider lists, INTERACTIVE_CMDS, AGENT_TODO ledger) rather than Builder changes, so the *combined* tree is consistent — but the Builder report's "did not touch" list is stale. NOTE (report accuracy, not code).

[PASS]

## Step 2: F1 — include/exclude glob filtering (pos-ai-hf)

Verified by reading `bin/pos-ai-hf` + grep:

- (a) **Array shape end-to-end**: `hf_apply_patterns` (`bin/pos-ai-hf:422-447`) consumes the input via `jq -c '.[]'` (array iteration), accumulates entries, and yields `[]` on no match or `jq -c -s '.'` (array) on matches. Downstream consumers all see an array again: `file_count` via `jq 'length'` (593), `total_size` via `[.[].size // 0]` (618), parallel/sequential iterators via `jq -c '.[]'` (674/713), `.hf-meta` via `[.[] | .rfilename]` (721). The old object-stream breakage is gone.
- (b) **Composition order**: gguf/filename filter runs first (`bin/pos-ai-hf:566-584`), then the pattern block `gguf/filename → include → exclude` (588-590), matching usage/POS.md wording. The `--gguf + --include/--exclude` pre-check error was removed (541-544 now only guards filename+both-patterns), so patterns compose with `--gguf`.
- (c) **No-match error**: count-0 branch errors cleanly `No files match include/exclude patterns in <repo> (branch: <branch>)` (599-600); `err()` exits 1 (`lib/common.sh:24`).
- (d) **Quote safety**: patterns never enter a jq program — `hf_apply_patterns` passes them as positional args into bash `case "$fname" in $include)` glob matching (429-439); no `match(`/interpolation remains (grep: no `match(`/`include_filter`/`exclude_filter` in pos-ai-hf). `hf_apply_patterns` defaults `include="${2:-}" exclude="${3:-}"` → no unbound vars under `set -u`; `INCLUDE_PATTERN`/`EXCLUDE_PATTERN` initialized at top (120-121).
- (e) **Dead code**: `err_with_context`, `hf_download_file`, `run_parallel_download` — grep across `bin/` finds zero occurrences.

Carried-over SUGGESTED (from S7, unchanged): `--list` mode (553-563) returns before the pattern block, so `--list --include "*.gguf"` lists everything although POS.md:108 promises "shows exactly what download would fetch". Also new behavior note: bash `case` glob is case-sensitive (old broken regex used `"i"`); docs don't promise case-insensitivity, and the gguf filter itself is case-insensitive — flagging for doc consistency only.

[PASS]

## Step 3: F2 — systemd unit generation (pos-ai-server)

- ExecStart is ONE line with the full resolved command: `exec_cmd` built at `bin/pos-ai-server:431-477`; unit heredoc writes `ExecStart=$exec_cmd` (495) with no `echo >>` appends anywhere (git diff confirms removal of the entire append block); unit structure `[Unit]/[Service]/[Install]` valid (488-504).
- Dry-run prints the same string (`(dry-run) ExecStart: $exec_cmd`, 481).
- **NOT FIXED — model path with spaces**: `exec_cmd="$llamacpp_full -m $model --port $PORT --host $HOST"` (432) concatenates the raw path, and the heredoc writes it unquoted. systemd.service(5) splits ExecStart arguments on unquoted whitespace; `resolve_model` (163-197) accepts space-containing paths (`[ -f "$explicit" ]`), so a model under a spaced dir (or `HF_DOWNLOAD_DIR` with a space) produces a unit whose args are split (`-m /home/user/My` + `Models/model.gguf`), and the server silently fails to load the model. The brief's check item "systemd quoting of model path with spaces is correct (quote the ExecStart value properly)" is **not** satisfied. → REQUIRED R1.
- `systemd-analyze verify` claim: plausible from the unit text (all keys valid, ExecStart absolute path), but **UNVERIFIED** here — sandbox denies execution. Note: `systemd-analyze verify` would not catch the space issue anyway (it validates syntax/literal paths, not runtime arg semantics).

[FAIL → flagged as REQUIRED R1]

## Step 4: F3 — --branch/--revision alias (pos-ai-hf)

- `BRANCH` variable removed (grep: no `BRANCH` reference anywhere in pos-ai-hf); both `--branch` (127-129) and `--revision` (146-148) set the same `REVISION`, last-arg-wins by loop overwrite.
- Both consumers use `REVISION`: `bin/pos-ai-hf:547` (cmd_download) and `871` (cmd_files).
- usage() documents the alias (67, 77-79); `# POS_FLAGS:` line 4 lists both; `DOC/POS.md:108` documents "alias `--revision`, when both are given the later one wins".

[PASS]

## Step 5: F4 — parallel download failure handling (pos-ai-hf)

- Per-pid reap: `if ! wait "${job_pids[0]}"` batch reap (666-668) and drain loop `if ! wait "${job_pids[$i]}"` (677-683) — a failed job is recorded, never fatal to the batch (checked: no unguarded `wait` remains).
- Failure collection + reporting after the batch (667, 679, 687-689) — same `warn` style as the sequential path.
- No orphaned jobs: drain loop waits for every started pid; temp dir cleaned by `trap 'rm -rf "$temp_dir"' EXIT` (641) + explicit `rm -rf` + `trap - EXIT` (691-692).
- Dead machinery removed (see Step 2e).
- **NEW REQUIRED — misleading success reporting**: on partial failure the script continues and: (i) summary prints `Downloaded: <repo> (<file_count> files, <total_size>)` (745) counting **attempted** files; (ii) `.hf-meta` "files" records ALL filtered files (721) even failed ones; (iii) exit status is 0. The builder disclosed this ("summary line counts attempted files — pre-existing, noted not in review scope"), but the re-review brief says "summary counts are honest (flag anything misleading)" and the parallel failure path is exactly this rewrite's scope. Consequence: a partially-failed model is marked complete in meta and `pos ai server start` can attempt incomplete weights. → REQUIRED R2. Also minor: the progress line prints `Completed: <failed-file>` for failures before the batch-end warning (670/682) — fold into R2.

[PASS for original F4 defect; FAIL on honesty item → REQUIRED R2]

## Step 6: F5 — version/feature validation (pos-ai-server)

- `detect_llama_version` (52-59): `command -v "$bin"` guard **before** the pipeline; pipeline terminated `|| true`; empty → `unknown`. Cannot crash on missing binary.
- `validate_requested_flags` (66-87) validates only `REQUESTED_FLAGS` — populated exclusively in the parse loop when the user explicitly passes the flag (288-359); config/env-derived defaults are never validated.
- Error message names flag + version (84): `installed llama.cpp <version> does not expose <flag> — remove it or upgrade llama.cpp`.
- Warn-and-proceed on unreadable `--help` (72-74) is deliberate and documented in `DOC/POS.md:125` ("if `--help` cannot be read the tool warns and proceeds").
- `cmd_status` errors cleanly before the version probe (549-551) and probes the *resolved* binary (604-605).

[PASS]

## Step 7: F6 — hf cache + /dev/tty deviation (pos-ai-hf)

- `cmd_cache {status|clear}` real implementation (`bin/pos-ai-hf:887-964`): default `status`, bad action → usage error; indent fixed (no more 4-space top-level).
- `status`: cache dir + model count + on-disk size via existing `hf_human_size` (926), empty → `Models: 0 (nothing downloaded yet)` rc 0; discovery identical to `list` via `hf_cache_models` (897-905).
- `clear`: lists models, confirmation prompt, fail-closed — only `[Yy]` proceeds; EOF/invalid → `Aborted — nothing removed` rc 0 (948-953).
- **/dev/tty deviation assessment — acceptable**:
  - Convention (AGENTS.md) covers tools that read **stdin**; `cache clear` reads `/dev/tty`, not stdin, so the `pos` logging-tee cannot hang or swallow the prompt.
  - Lint rule `uses_stdin` (scripts/lint-conventions.sh:59-80) explicitly skips lines containing `/dev/tty` (74) — `pos-ai-hf` is statically lint-clean and correctly NOT in INTERACTIVE_CMDS.
  - Precedent: `pos-ai-server` `pick_model` reads `/dev/tty` (157) and is likewise not in INTERACTIVE_CMDS — the deviation matches an established pattern.
  - No controlling terminal: `IFS= read -r yn 2>/dev/null </dev/tty || yn=""` fails closed (deny) instead of hanging — consistent with the builder's setsid probe claim.

[PASS]

## Step 8: llamacpp wiring + maintainer corrections + gates

- `bin/pos-ai-llamacpp` (7 lines) is a byte-for-byte mirror of `bin/pos-ai-gemini` except the provider name; `# POS_SUBCMDS: ask chat models sessions capture` matches `lib/ai-providers/llamacpp.sh` capabilities (`provider_generate` drives ask/chat/sessions/capture; `provider_models_list` drives models).
- `bin/pos-ai:701-704` `llamacpp)` case routes `exec "$0" --provider llamacpp "${args[@]}"` like the gemini/openrouter forwarders; usage() provider lists corrected (42, 59).
- `bin/pos:269` INTERACTIVE_CMDS includes `ai-llamacpp` — required (chat reads stdin) and the reverse lint rule (entry ⇒ matching executable) is satisfied by the untracked forwarder (exec bit claimed 100755 by Maintainer `stat`; **UNVERIFIED** here — sandbox denies `stat`, file is untracked so `git ls-files -s` cannot confirm).
- `DOC/POS.md` (58-59, 72, 82, 90, 108, 111, 125) and `DOC/howto/ai.md` (5, 19-20, 29-31, 134-137) llamacpp edits are factual — verified against `lib/ai-providers/llamacpp.sh` (OpenAI-compatible `/v1/chat/completions` line 31; default model from `/v1/models` lines 11-16; `LLAMACPP_MODEL` line 7).
- Generated blocks (AGENT_Context tree rows 66-70, dispatch 286-289, selfcontained 374, filetable 618-621) internally consistent with headers; filetable line counts match `wc -l` exactly (pos-ai-hf 976, pos-ai-server 646, pos-ai 706, pos-ai-llamacpp 7, completions 313, pos 302). Regen idempotency itself UNVERIFIED.
- AGENT_TODO.md: both 2026-09-06 entries (convention sweep; llamacpp forwarder) dated and consistent with the file's loose "readable summary" convention (convention sweep entry is newest-at-top, forwarder entry predates it — pre-existing placement, not this pass's defect).
- **Gates UNVERIFIED — denial quoted**: sandbox permission rules allow only `git status/log/diff/show/blame/reflog/merge-base/rev-parse/branch --list/branch -a/branch -r/ls-files/ls-tree/head/tail/wc/sort/grep/rg`; `bash -n`, `make gen`, `make check`, `make lint`, `systemd-analyze` are denied (`{"permission":"bash","pattern":"*","action":"deny"}`). Static cross-checks against `scripts/lint-conventions.sh`/`scripts/check-sync.sh` show no obvious gate violation in the touched files (shebang, strict-mode, POS header + em-dash, exec-bit claims, `-h|--help` after deps guards, `uses_stdin`/INTERACTIVE_CMDS consistency, no top-level `local`, docs referenced in POS.md).

[BLOCKED: gates require execution — must be run by Orchestrator/Builder outside this sandbox]

---

## Findings

### R1 — REQUIRED — ExecStart does not quote the model/binary path; paths with spaces produce a broken unit

- Severity: REQUIRED
- Evidence: `bin/pos-ai-server:432` `exec_cmd="$llamacpp_full -m $model --port $PORT --host $HOST"` and 495 `ExecStart=$exec_cmd` (raw heredoc). systemd.service(5) splits ExecStart on unquoted whitespace; `resolve_model` (163-197) accepts spaced paths (`[ -f "$explicit" ]`), and `HF_DOWNLOAD_DIR` (18) becomes the relative-model base. A model like `--model "/home/me/My Models/m.gguf"` yields `ExecStart=/usr/bin/llama-server -m /home/me/My Models/m.gguf …` → args split, model load fails silently.
- Relevant files/lines: `bin/pos-ai-server:432, 495` (+ `18`, `163-197`).
- Approved scope reference: re-review brief F2 item "systemd quoting of model path with spaces is correct (quote the ExecStart value properly)".
- Why it matters: exactly the F2 failure class this fix was meant to eliminate — a valid input produces a unit that doesn't do what the user asked, without any error. Fix is understood: emit quoted systemd tokens (`ExecStart="$llamacpp_full" -m "$model" …`) inside the unquoted heredoc, escaping embedded quotes as needed.

### R2 — REQUIRED — partial-failure reporting overstates success: summary counts attempted files, `.hf-meta` lists failed files, exit code is 0

- Severity: REQUIRED
- Evidence: `bin/pos-ai-hf:745` `printf '📥 Downloaded: %s (%d files, %s)'` uses `file_count` (= all filtered files) even after `failed_files` is non-empty; 721 writes `.hf-meta` "files" = all filtered files; no code path exits non-zero when `failed_files` is non-empty (parallel 638-692 and summary 716-747 both run to completion; dispatch exits 0). Progress lines 670/682 also print `Completed:` for failed files before the batch-end warning.
- Relevant files/lines: `bin/pos-ai-hf:687-689, 716-747` (esp. 721, 745).
- Approved scope reference: re-review brief F4 item "summary counts are honest (flag anything misleading)". Builder disclosed the limitation in their report (Step 4 "Known limit (pre-existing…)") — disclosed is not fixed; the failure path is this rewrite's scope.
- Why it matters: a partially-downloaded model is reported as fully downloaded, recorded complete in `.hf-meta`, and can then be handed to `pos ai server start` (incomplete weights) — an operational hazard from exactly the failure mode F4 was meant to handle. Fix is understood: count successes for the summary, exclude failed files from `.hf-meta` (or record per-file status), and exit non-zero when any file failed.

### S3 — SUGGESTED — `--list` mode ignores `--include/--exclude` (carried from S7)

- Severity: SUGGESTED
- Evidence: `bin/pos-ai-hf:553-563` returns before the pattern block at 588-590; `DOC/POS.md:108` and usage (line 74) promise `--list` "shows exactly what download would fetch".
- Why it matters: doc-vs-behavior inconsistency for the flagship documented example; small fix (apply patterns inside the `--list` branch or move the early return after the pattern block).

### S4 — SUGGESTED — pattern glob is case-sensitive; docs silent, gguf filter is case-insensitive

- Severity: SUGGESTED
- Evidence: `hf_apply_patterns` bash `case` glob (429-439) is case-sensitive; `HF_GGUF_FILTER` uses `ascii_downcase` (181). `--include "*.GGUF"` won't match `.gguf` files.
- Why it matters: consistency note only; no working behavior regressed (old regex path was broken), but one line of docs ("supports glob") would remove ambiguity.

### N5 — NOTE — approval gates and systemd-analyze verification could not be run in this sandbox

- Severity: NOTE
- Evidence: permission rules deny all bash except the git/read allow-list (quoted in Step 8). Builder/Maintainer claim `bash -n` OK, `make gen` idempotent, `make check` green, `make lint` 0 FAIL / 0 WARN, `systemd-analyze verify` RC=0 — plausible but not observed here. Also NOTE: `systemd-analyze verify` success does not cover R1 (it cannot see the runtime space-splitting).
- Why it matters: merge-blocker status (gen drift / gate failure) cannot be confirmed until the Orchestrator/Builder re-runs the gates on this exact tree.

### N6 — NOTE — Builder report's "files not touched" list is stale

- Severity: NOTE
- Evidence: Builder report (lines 10, 99) claims `bin/pos`, `bin/pos-ai`, `AGENT_TODO.md` untouched; actual diff shows all three modified — by the Maintainer's sweep, not the Builder, so combined work is consistent. Report-accuracy nit only.

---

## Per-finding status vs original list

| Finding | Status | Evidence |
|---------|--------|----------|
| F1 (BLOCKING — include/exclude never completes) | **FIXED** | bash-case glob, array shape, composition order, no-match rc 1, no jq interpolation, dead helpers removed |
| F2 (BLOCKING — malformed unit) | **PARTIAL** | Single-line ExecStart + dry-run parity + no echo>> appends: FIXED. Path-with-spaces quoting: NOT FIXED → R1 |
| F3 (REQUIRED — dead --branch) | **FIXED** | Single `REVISION` var, both aliases, last-wins, docs/headers updated, both consumers use REVISION |
| F4 (REQUIRED — parallel failure path) | **FIXED** (primary) + **R2** | Per-pid reap, failure collection, drain, EXIT-trap cleanup, dead machinery removed — FIXED. Misleading counts/meta/exit on partial failure — new REQUIRED R2 |
| F5 (REQUIRED — version/validation) | **FIXED** | Guard before pipe, unknown-safe, explicit-flags-only validation, flag+version error, documented warn-and-proceed, clean status error |
| F6 (REQUIRED — cache stub) | **FIXED** | Real status/clear, sizes via hf_human_size, fail-closed confirm; /dev/tty deviation acceptable (lint-exempt, precedent, fail-closed) |
| llamacpp wiring (brief) | **PASS** | Forwarder mirror, dispatch case, INTERACTIVE_CMDS, docs factual, AGENT_TODO dated |
| Maintainer llamacpp doc corrections | **PASS** | 7 provider-list fixes factual vs adapter; no drift introduced |
| Gates | **UNVERIFIED** | Sandbox denial; static lint/check analysis clean |

## Gate outcomes

- `bash -n` all in-scope scripts — UNVERIFIED (denied).
- `make gen` idempotency (x2) — UNVERIFIED (denied); filetable line counts independently match `wc -l`; GEN blocks internally consistent with headers.
- `make check` / `make lint` — UNVERIFIED (denied); static reading of `scripts/lint-conventions.sh` (shebang/strict-mode/POS headers/`-h|--help` position/`uses_stdin` tty exemption/INTERACTIVE_CMDS reverse rule/`local`-at-top warning) and of `check-sync.sh` shows no violation in the touched files.
- `systemd-analyze verify` — UNVERIFIED (denied); unit text (pos-ai-server:488-504) is plausible: valid keys, absolute ExecStart, `EnvironmentFile=-%h/...` accepted syntax.
- Denial quote: `{"permission":"bash","pattern":"*","action":"deny"}` with an allow-list of git read commands, `head/tail/wc/sort/grep/rg` only.

## Verification verified

- F1 array/composition/no-match/quote-safety/dead-code by direct code read + grep (FACT).
- F2 single-line ExecStart + dry-run parity + no append writes by code read + diff (FACT); space-quoting gap by systemd.service(5) semantics + code read (FACT).
- F3 aliasing by grep + code read (FACT).
- F4 failure handling by code read (FACT); misleading summary/meta/exit by code read (FACT).
- F5 guards and validation scope by code read (FACT).
- F6 cache behavior + /dev/tty fail-closed by code read + lint rule read (FACT).
- llamacpp wiring: forwarder byte-mirror (read), dispatch (read), INTERACTIVE_CMDS (read), docs vs adapter facts (read), line counts (wc).
- Git baseline HEAD = `0856b25`; tree diff matches the combined Builder+Maintainer reports.

## Verification unverified

- `bash -n`, `make gen` idempotency, `make check` (incl. `gen-docs --check`), `make lint`, `systemd-analyze verify` — sandbox denies execution; must be run by Orchestrator/Builder on this exact tree.
- Exec bit of untracked `bin/pos-ai-llamacpp` (claimed 100755 via `stat` by Maintainer; untracked so not confirmable via git).
- Live probes (a real include/exclude download, one forced-failure parallel download, a real `server start` with a spaced model path, `status` without llama-server) — empirical confirmation pending.

## Scope compliance

- In-scope, correctly implemented: F1, F3, F5, F6; F4 failure handling; llamacpp forwarder + dispatch + docs + completions; maintainer doc corrections.
- In-scope, defective: F2 space-quoting (R1); F4 summary/meta honesty (R2).
- Out-of-scope changes: none in source; untracked plan docs/reports remain for the Orchestrator's commit decision.

## Remaining uncertainty

- Gate results on the exact tree (Builder/Maintainer claims unverified here).
- Whether `R1` (space quoting) and `R2` (honest failure reporting) are fixed per the recommendations — requires a Builder pass and another review round, plus one live spaced-path probe and one forced-failure probe by the Orchestrator.

## Recommended next agent

**Builder**

**Reason:** Two REQUIRED defects with understood, in-scope fixes: (1) quote the ExecStart tokens (`"$llamacpp_full"`/`"$model"`) so spaced paths survive systemd's argument splitting (pos-ai-server:432/495); (2) make the failure path honest — count successes in the summary, exclude failed files from `.hf-meta` (or record status), and exit non-zero when any file failed (pos-ai-hf:687-747). After fixes: re-run `bash -n`, `make gen` x2, `make check`, `make lint`; then Orchestrator runs the live probes (include/exclude download, forced-failure parallel download, `server start` with a spaced model path + `systemd-analyze verify`, `server status` without llama-server) and re-hands to Reviewer for final acceptance. S3/S4 can ride along in the same pass.

## Changes made by Reviewer

none