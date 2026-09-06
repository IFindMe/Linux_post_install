# Reviewer Report — Acceptance review of Builder R1/R2 fixes + whole pending diff

Date: 2026-09-06
Reviewer: independent (read-only) reviewer — final acceptance gate
Reviewed refs: working tree over HEAD `0856b25` + untracked `bin/pos-ai-llamacpp`
Inputs read: Builder R1/R2 fix report (`AgentsReport/builder/2026-09-06_r1r2-fixes.md`), prior reviews (rereview + full review), the full `git diff HEAD`, `bin/pos-ai-server`, `bin/pos-ai-hf` (full reads), `bin/pos-ai-llamacpp`, `bin/pos`, `bin/pos-ai`, `completions/pos.bash`, `AGENT_TODO.md`, doc diffs (`DOC/POS.md`, `DOC/howto/ai.md`, `DOC/AGENT_Context_Project.md`), AGENTS.md / `DOC/DEV.md` conventions.

## TL;DR

- **Status:** APPROVE_WITH_NOTES
- **Verdict:** Both REQUIRED findings from the prior re-review are **FIXED with supporting evidence**. R1 (systemd ExecStart quoting) and R2 (partial-failure honesty) both PASS by direct code read + diff. The whole pending diff (wire-up, docs, hygiene, completions) is internally consistent and committable. No BLOCKING or REQUIRED findings remain.
- **Defect counts this pass:** 0 BLOCKING, 0 REQUIRED, 0 SUGGESTED, 3 NOTE (1 carryover-scope item recorded, 2 low-risk observations).
- **Read-only constraint:** gates (`bash -n`, `make gen`/`check`/`lint`) and the live probes were executed by the Builder/Orchestrator, not independently reproduced here (sandbox denies execution). Accepted per the Orchestrator's instruction not to re-run make; the live evidence (real `systemd-analyze verify` rc 0 + 16-token word-split assertion; 2-file forced-failure probe) is consistent with the code as read.

---

## Step 1: R1 — systemd ExecStart quoting (`bin/pos-ai-server`)

- `systemd_quote()` (`bin/pos-ai-server:388-392`): `value="${value//\"/\\\"}"` then `printf '"%s"'` — wraps in systemd double quotes and escapes any embedded `"` as `\"`. This matches systemd.service(5) double-quote rules (double quotes preserve whitespace; `\"` escapes a quote).
- Use (`bin/pos-ai-server:445`): `exec_cmd="$(systemd_quote "$llamacpp_full") -m $(systemd_quote "$model") --port $PORT --host $HOST"`. Quoting applies **only** to the executable and the model path — the two tokens that may legally contain spaces. Plain flag/number tokens are appended unquoted (`--n-gpu-layers`, `--ctx-size`, `--threads`, and conditionally `--gpu-threads`, `--tensor-split`, `--batch-size`, `--ubatch-size`, `--temperature`, `--top-k`, `--top-p`, `--repetition-penalty`, `--kv-cache`, `--slots`, and bare `--mmap`/`--mlock`/`--metrics`/`--health`). No over-quoting.
- Dry-run parity: `log "(dry-run) ExecStart: $exec_cmd"` (`bin/pos-ai-server:494`) uses the exact same `$exec_cmd` string later written to the unit (`ExecStart=$exec_cmd`, `bin/pos-ai-server:508`). Byte-identical by construction.
- Unit validity: `ExecStart="/usr/bin/llama-server" -m "/home/me/My Models/m.gguf" --port 8088 --host 127.0.0.1 ...` is a single valid systemd ExecStart line. systemd splits on unquoted whitespace and honors the double-quoted tokens as single args, so a model path with spaces survives. This is the precise failure class R1 targeted — now resolved.
- Sanity check on OTHER user-provided values appended raw: `$PORT`, `$HOST`, `$gpu_layers`, `$GPU_THREADS`, `$TENSOR_SPLIT`, `$BATCH_SIZE`, `$UBATCH_SIZE`, `$TEMPERATURE`, `$TOP_K`, `$TOP_P`, `$REPETITION_PENALTY`, `$KV_CACHE_SIZE`, `$SLOTS`. Each is a numeric or address/split token where a space is not a legal value (host = IP/hostname; tensor-split = comma/semicolon GPU list; the rest numeric). The only tokens where spaces are legitimate (filesystem paths) are the two that ARE quoted. No realistic spaced-value breakage remains. (Defense-in-depth could quote all of them, but that is not required and would not change behavior for legal inputs — NOTE 2.)
- `systemd-analyze verify`: Builder reports rc 0 on a spaced-path unit and an asserted word-split of 16 tokens. Not re-run here (execution denied); the unit text as read is plausible and valid.

[PASS]

## Step 2: R2 — partial-failure honesty (`bin/pos-ai-hf`)

- **`failed_files` scoping**: `local failed_files=()` declared at `bin/pos-ai-hf:632` inside `cmd_download` (function scope). Populated ONLY in the parallel branch (`:671`, `:685`). The sequential branch never touches it, so it stays empty there.
- **`.hf-meta` gated on zero failures**: `if [ "${#failed_files[@]}" -eq 0 ]; then` (`:727`) writes meta; `else` (`:742-744`) `warn "Not writing .hf-meta — ${repo_id} is incomplete (N file(s) failed)"`. No complete-meta is written after partial failure. Confirmed.
- **Summary honesty**: failure branch (`:757-761`) `success_count=$((file_count - ${#failed_files[@]}))` and prints `📥 Downloaded: %s (%d of %d files, %d failed: %s)`. The success-only summary `(%d files, %s)` (`:762-766`) is in the `else`, so it cannot appear when any file failed. No misleading "Downloaded:" success line on partial failure. Confirmed.
- **Exit rc 1**: `if [ "${#failed_files[@]}" -gt 0 ]; then return 1; fi` (`:773-775`). Reachable only from the parallel path (sequential never populates the array). Confirmed.
- **Sequential path unchanged**: the `else` sequential single-file branch (`:700-721`) is not among the diff's changed lines — `if ! hf_download_with_progress ...; then warn "Failed to download $fname"; continue; fi` retains its warn-and-continue, rc-0 semantics. The Builder's "byte-for-byte unchanged" claim is consistent with the diff. Confirmed.
- Builder's live probe output (`[2/2] Failed: model-fail.bin`; `Not writing .hf-meta`; `1 of 2 files, 1 failed: model-fail.bin`; `rc=1`; dir lacks `.hf-meta`; `list` empty; single-file sequential success/failure unchanged) matches all of the above by code read.

[PASS]

## Step 3: Whole pending diff — wire-up

- `bin/pos-ai-llamacpp` (7 lines) is a byte-for-byte mirror of `bin/pos-ai-gemini` (`bin/pos-ai-gemini:1-7`) with only the provider name changed (`gemini`→`llamacpp`); `# POS_SUBCMDS: ask chat models sessions capture` matches the gemini forwarder and `lib/ai-providers/llamacpp.sh` capabilities.
- `bin/pos-ai:701-704` `llamacpp)` case → `exec "$0" --provider llamacpp "${args[@]}"`, mirroring the gemini/openrouter forwarder cases. usage() provider lists updated (`bin/pos-ai:42`, `:59`).
- `bin/pos:269` INTERACTIVE_CMDS adds `ai-llamacpp` (chat reads stdin → tee-pipe guard) — required and consistent with the reverse lint rule.
- `completions/pos.bash`: `_pos_subcmds[ai-llamacpp]="ask chat models sessions capture"` and `[ai]` list includes `llamacpp`; `_pos_flags[ai-hf]`/`[ai-server]` expanded to match the headers. All consistent.

[PASS]

## Step 4: Whole pending diff — docs & completions

- `DOC/POS.md`: ai section references the three forwarders incl. llamacpp (`:55`); `--provider` row `(gemini\|openrouter\|llamacpp)` (`:69`); backward-compat sentence (`:82`); AI_PROVIDER config row (`:87`); hf download row documents `--branch`/`--revision` alias + `--include`/`--exclude` glob (`:105`); hf `cache [status|clear]` row added (`:108`); server flags row expanded + version-aware validation note (`:122`). All factual vs the code.
- `DOC/howto/ai.md`: adapter list, `--provider` backend list, backward-compat shorthand, and "Available providers" table row (llamacpp, `LLAMACPP_MODEL`) — factual vs `lib/ai-providers/llamacpp.sh`.
- `DOC/AGENT_Context_Project.md`: generated blocks (docmap line shifts, tree row, dispatch row, selfcontained, filetable) internally consistent with headers. Filetable line counts match `wc -l` exactly: `pos-ai-hf` 1004, `pos-ai-server` 659, `pos-ai` 706, `pos-ai-llamacpp` 7, `completions/pos.bash` 313, `bin/pos` 302.
- `AGENT_TODO.md`: all Done entries dated (2026-09-06 / 2026-09-05). No un-dated entries introduced.

[PASS]

## Step 5: Hygiene / secrets / exec bits

- No `/tmp/opencode` references in any source file (grep clean).
- No stray debugging/temporary code: grep for `DEBUG|print_r|console.log|TODO|FIXME|HACK|probe|stub` hits only comment words ("version probe", "probe the resolved binary") and a pre-existing unrelated alias tmpfile — no debug blocks or commented-out code in the changed files.
- No secret literals: `HF_TOKEN` is read at runtime from env/config (`bin/pos-ai-hf:27,187`) — no embedded key/token. The `# POS_CONFIG: ... HF_TOKEN=secret:...` header is the declared masking classification, not a value. No `sk-`/`AIza`/`gh*_` style literals in the changed files.
- Tracked exec bits confirmed 100755 via `git ls-files -s` for `bin/pos`, `bin/pos-ai-hf`, `bin/pos-ai-server`; `bin/pos-ai`, `bin/pos`, `completions` tracked normally. The untracked `bin/pos-ai-llamacpp` exec bit **cannot be confirmed via git** (untracked; `stat` denied by sandbox) — see NOTE 1.

[PASS]

---

## Findings

1. **NOTE** — untracked `bin/pos-ai-llamacpp` exec bit is UNVERIFIED via git (untracked file; `stat` denied by sandbox). It is a byte-for-byte mirror of `bin/pos-ai-gemini` (a tracked 100755 forwarder), and both the Maintainer's earlier `stat` claim and the Builder report assert 100755. LOW RISK; the dispatcher's `make gen`/check gates (already green per Orchestrator) would catch a missing exec bit. No action required if `git add` preserves exec-bit from the on-disk mode.
2. **NOTE** — additional user-provided flag tokens (`--host`, `--tensor-split`, numeric flags) are appended unquoted. Each is a token type where a space is not legal, so no realistic breakage; this matches the brief's intended scope (quote only path-capable tokens). Optional hardening, not required.
3. **NOTE** — the two SUGGESTED items carried from the prior re-review (`--list` ignores `--include/--exclude`; bash glob case-sensitivity) remain outstanding. They were NOT REQUIRED findings in either the re-review or this acceptance brief, and the R1/R2 scope was intentionally constrained to the two REQUIRED defects. Recorded for a future pass, not a blocker.

---

## Per-item status

| Item | Status | Evidence |
|------|--------|----------|
| R1 — systemd ExecStart quoting | **PASS** | `systemd_quote` (:388-392) escapes+quotes; binary+model only (:445); dry-run shares exact `$exec_cmd` (:494); unit writes same (:508); other tokens space-legal-check (NOTE 2) |
| R2 — partial-failure honesty | **PASS** | `failed_files` function-scoped (:632); meta gated (:727-744); honest summary (:757-761); rc 1 (:773-775); sequential path untouched |
| Wire-up (llamacpp) | **PASS** | Byte mirror of gemini forwarder; dispatch case; INTERACTIVE_CMDS; completions |
| Docs & completions | **PASS** | POS.md / howto/ai.md / AGENT_Context factual; filetable line counts all match `wc -l` |
| Hygiene / secrets | **PASS** | No `/tmp/opencode`, no stray debug, no embedded secrets; tracked exec bits 100755 (NOTE 1 for untracked exec bit) |
| Gates | **Verified via Orchestrator handoff** | bash -n OK, make gen idempotent, make check `check-sync: OK`, make lint `0 FAIL, 0 WARN` (not re-run here per instruction) |

---

## Verification verified

- R1 `systemd_quote` implementation, use-site, dry-run/unit byte-parity, and systemd-valid ExecStart form — FACT by code read + diff (all in-scope lines cited above).
- R2 failed_files scoping, meta gating, honest summary, rc-1 exit, and unchanged sequential path — FACT by code read + diff.
- Wire-up (forwarder mirror, dispatch case, INTERACTIVE_CMDS, completions) — FACT by read.
- Docs factual vs code + adapters; filetable line counts match `wc -l` exactly — FACT.
- No `/tmp/opencode`, no stray debug, no secret literals in changed files — FACT by grep.
- Tracked exec bits 100755 — FACT via `git ls-files -s`.
- FINAL_SUMMARY/IMPLEMENTATION_PLAN + audit files remain untracked (Orchestrator commit decision, out of review scope) — consistent with prior passes.

## Verification unverified

- Gate commands (`bash -n`, `make gen` x2, `make check`, `make lint`, `systemd-analyze verify`) and the live probes — NOT independently reproduced in this sandbox (execution denied). Accepted as Orchestrator-handoff evidence: claims are internally consistent, match the code as read, and the probe outputs match the expected post-fix behavior exactly.
- Exec bit of untracked `bin/pos-ai-llamacpp` — UNVERIFIED via git (stat denied); asserted 100755 by Maintainer/Builder, healthy risk.

## Scope compliance

- In-scope, delivered: R1 (ExecStart quoting) and R2 (partial-failure honesty) — both confirmed.
- In-scope, unchanged/documented: sequential single-file failure behavior preserved per the "don't touch" constraint.
- Out-of-scope changes: none found in source. The two carried SUGGESTED items are recorded as NOTE 3 (outside R1/R2 scope).
- No new flags/subcommands/config keys introduced by the R1/R2 pass (docs/completions refreshed only by `make gen`).

## Remaining uncertainty

- Gate/probe results rest on the Builder/Orchestrator's reported runs rather than an observed run in this review sandbox. The code-level evidence independently confirms each claim to the extent a static read allows; the only residue is empirical (a real `systemd-analyze verify` on this tree, a real forced-failure parallel download, a real spaced-path `server start`), which the Builder reports green.
- Untracked `bin/pos-ai-llamacpp` exec bit.

## Recommended next agent

**Orchestrator**

**Reason:** The verdict is final — APPROVE_WITH_NOTES. R1 and R2 are fixed and verified at the code level; the pending diff is committable. The Orchestrator should commit the reviewed source set (decision on untracked plan/report files as previously), then close the workflow. The two carried SUGGESTED items (NOTE 3) can be scheduled as a future builder pass; neither blocks this commit.

## Changes made by Reviewer

none
