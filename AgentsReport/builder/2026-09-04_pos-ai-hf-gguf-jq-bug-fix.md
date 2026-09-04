# Builder Report — `pos-ai-hf` GGUF/jq bug fix (2026-09-04)

## TL;DR

- **Status:** IMPLEMENTED
- **Scope:** fix `jq: endswith() requires string inputs` crash in `pos ai hf download … --gguf` per Detective spec (AgentsReport/detective/2026-09-04_pos-ai-hf-gguf-jq-bug.md, Step 4); Changes 1-3 implemented exactly; harness at `/tmp/opencode/hf-test2/`; no commit/push.
- **Files changed (repo):** `bin/pos-ai-hf` (+17/-4); `DOC/AGENT_Context_Project.md` (2-line auto-gen filetable row, only the `pos-ai-hf` line count 495→506 — `make gen` output; no GEN block content changed).
- **Verification:** `bash -n` OK; harness 9/9 PASS; `make gen/check/lint` green (`0 FAIL, 0 WARN`); live API: normalize→13 records (0 nulls, 0 bad sizes), --gguf→exactly 10, README/LICENSE/.gitattributes excluded; real tool path: single-file `LICENSE` download OK (7.2 KB, `.hf-meta` correct); mode-aware empty messages verified live (exit 1 unchanged).
- **NOT committed.** Working-tree changes: `bin/pos-ai-hf`, `DOC/AGENT_Context_Project.md` (+1/-1 line-count row), untracked Detective report (pre-existing).

## Step 1: Read Detective report + confirm scope — [DONE]

Read full report (fix spec Step 4, edge cases Step 5, harness spec Step 6, verification Step 7). Confirmed fixtures exist: `/tmp/opencode/qwen-tree.json` (13 files, no rfilename), `/tmp/opencode/sd-tree.json` (8 files + 7 dirs).

## Step 2: Implement Change 1 — normalize tree response in `hf_repo_files()` — [DONE]

`bin/pos-ai-hf:201-207` — primary `/tree` path now pipes through the normalize jq instead of echoing raw:

```bash
# Tree API returns {type,path,size,oid[,lfs]} per entry — normalize to the
# {rfilename,size} shape the rest of the pipeline expects (same as fallback).
# Skip "directory" entries: they have no resolvable file URL.
printf '%s' "$result" | jq '[.[] | select(.type == "file") | {rfilename: .path, size: (.size // 0)}]'
```

Fallback sibling path (line ~213) untouched — already emits `{rfilename, size}`.

## Step 3: Implement Change 2 — defense-in-depth guard in `--gguf` filter — [DONE]

`bin/pos-ai-hf:339`:

```bash
filtered_files="$(printf '%s' "$files_json" | jq -c '[.[] | select((.rfilename | type) == "string" and (.rfilename | endswith(".gguf")))]')"
```

## Step 4: Implement Change 3 — mode-aware empty results — [DONE]

`bin/pos-ai-hf:347-356` — replaced `[ "$file_count" -gt 0 ] || err "No files to download"` with `if [ "$file_count" -eq 0 ]` branch:
- single-file mode: `err "File not found: $filename in $repo_id (branch: ${branch})"`
- `--gguf` mode: `err "No .gguf files found in $repo_id${branch:+ (branch: $branch)} — try without --gguf"`
- generic: `err "No files to download"` (unchanged text)

Exit semantics unchanged (same `err` path, exit 1).

## Step 5: Build harness `/tmp/opencode/hf-test2/` — [DONE]

- `fixtures/tree-files.json` = copy of `/tmp/opencode/qwen-tree.json` (13 files, rfilename ABSENT, 10 .gguf)
- `fixtures/tree-with-dirs.json` = copy of `/tmp/opencode/sd-tree.json` (8 files + 7 `type:"directory"`)
- `fixtures/tree-empty.json` = `[]`
- `fixtures/tree-nogguf.json` = `[{"type":"file","path":"README.md","size":100}]`
- `run-tests.sh`: 9 assertions per report Step 6 (t_tree_normalize, t_gguf_on_normalized, t_single_file, t_all_files_passthrough, t_empty, t_nogguf, t_defense_guard, t_dirs_excluded, t_code_sync). Deliberately does NOT `source` bin/pos-ai-hf (top-level dispatch executes; no-args → usage → exit 0). NORM/GGUF_FILTER/FN_FILTER duplicated verbatim; `grep -F` drift-guards catch divergence from the file.

## Step 6: Verification budget — [DONE]

1. `bash -n bin/pos-ai-hf` → OK
2. `bash /tmp/opencode/hf-test2/run-tests.sh` → **9 passed, 0 failed** (output captured in Step 5 run)
3. `make gen && make check && make lint` → gen OK, check-sync OK, lint **0 FAIL, 0 WARN**; regenerated: `DOC/AGENT_Context_Project.md` line-count row only (495→506); no GEN:START/END block changes
4. LIVE validation (no download): fetched `https://huggingface.co/api/models/Qwen/Qwen2.5-3B-Instruct-GGUF/tree/main`; normalize jq → `{count:13, nulls:0, badsizes:0}`; --gguf filter → length 10; paths = 10 `qwen2.5-3b-instruct-*.gguf` (fp16×2 + q2_k..q8_0); README/LICENSE/.gitattributes excluded; pre-fix crash `endswith() requires string inputs` reproduced for contrast on raw tree
5. Real tool-path proof (no multi-GB download):
   - `pos ai hf download Qwen/Qwen2.5-3B-Instruct-GGUF LICENSE --output /tmp/hf-small` → exit 0, `📥 Downloaded: Qwen/Qwen2.5-3B-Instruct-GGUF/LICENSE (7.2 KB)`, `.hf-meta` `"files": ["LICENSE"]`, real 7388-byte file present. NOTE: first attempt via `bin/pos` hit the stale **installed** `/usr/local/bin/pos-ai-hf` (PATH precedence) which silently no-matched → reproduced the pre-fix bug; installed copy is now byte-identical to repo and the same command succeeds. Environment detail, not a code issue.
   - `--gguf` no-gguf repo: `… distilbert/distilbert-base-uncased --gguf` → `ERROR: No .gguf files found in distilbert/distilbert-base-uncased (branch: main) — try without --gguf`, exit 1 (no crash, no download)
   - single-file not-found: `… totally-missing-file` → `ERROR: File not found: totally-missing-file in Qwen/Qwen2.5-3B-Instruct-GGUF (branch: main)`, exit 1

## Step 7: Final diff review + handoff — [DONE]

`git diff --stat`: `bin/pos-ai-hf | 17 ++++-----` (only the 3 sanctioned hunks), `DOC/AGENT_Context_Project.md | 2 +-` (gen line-count row). `git status`: no staged/committed changes; NOT committed or pushed.

## Handoff

Status: **IMPLEMENTED**

Approved scope: the 3 changes in Detective fix spec Step 4; harness at `/tmp/opencode/hf-test2/`; verification per Step 7. Only `bin/pos-ai-hf` changed in repo (+ `make gen` line-count row in DOC/AGENT_Context_Project.md).

Remaining risks / follow-ups (out of scope, flagged by Detective):
- `hf_api` lacks `curl -L` → 307-redirect alias repos (e.g. runwayml) still fail (pre-existing).
- Tree endpoint non-recursive → subdirectory files not listed (pre-existing semantics).
- `/usr/local/bin` installed copy was stale at run time (auto-synced later); real deployers should reinstall.

Recommended next agent: **Tester** — the /tmp/opencode/hf-test2 harness is fixture-based and ready for adoption into the repo test suite if the project chooses (decision: Architect); otherwise Reviewer for acceptance of the 3-hunk fix.

Changes made by Builder: as listed above; nothing else touched.

## Harden+verification — error-object hardening (2026-09-04, Orchestrator follow-up) — [DONE]

Previous implementation APPROVED. Orchestrator/Reviewer found an additional crash class: `printf '%s' '{"error":"x"}' | jq '[.[] | select(.type == "file") | …]'` → `jq: error: Cannot index string with string "type"` rc 5 — `.[]` on an object iterates its VALUES; the string `"x"` then gets indexed with `.type`. Verified present on BOTH normalize paths pre-change (primary: `Cannot index string…`; fallback: `Cannot iterate over null (null)` on `.siblings`).

### Change 4 — object-safe normalize (primary), object-safe fallback (new)

`bin/pos-ai-hf:205` (primary, now object-guarded; jq `and` short-circuits so `.type` is never evaluated on non-objects):

```bash
printf '%s' "$result" | jq '[.[] | select(type == "object" and .type == "file") | {rfilename: .path, size: (.size // 0)}]'
```

`bin/pos-ai-hf:213` (fallback, previously unguarded — same crash class; now `[]?` suppresses null iteration + `select(type == "object")` skips junk elements + `(rfilename // "")` keeps the shape contract string-safe for nulls):

```bash
printf '%s' "$fallback" | jq '[.siblings[]? | select(type == "object") | {rfilename: (.rfilename // ""), size: (.size // 0)}]'
```

- On `{"error":"x"}`: primary → `[]` rc 0; fallback → `[]` rc 0 (both were rc 5 before).
- On real fixtures: 13-file tree → 13 records, 0 nulls (identical to pre-hardening); dirs fixture → 8 (dirs dropped); real metadata qwen-meta.json → 13 records, string rfilename, numeric size.
- Pathological `{"rfilename":42}` in siblings passes `// ""` unchanged (42 is truthy → kept) — non-null non-string rfilename still possible in the fallback shape; the `--gguf` filter's `type == "string"` guard prevents the crash class there, and single-file select simply won't match. Flagged as accepted residual risk (suggested-form semantics per Orchestrator).
- Line count unchanged (506) → `make gen` produced no further DOC change beyond the already-tracked 495→506 line-count row.

### Harness update

`/tmp/opencode/hf-test2/run-tests.sh`:
- `NORM` updated to hardened primary form; new `FB_NORM` duplicated verbatim.
- New fixture `fixtures/meta-siblings.json` = copy of `/tmp/opencode/qwen-meta.json` (13 siblings, real metadata shape).
- New assertions: `t_error_object_normalize` (`{"error":"x"}` → `[]` rc 0), `t_fallback_normalize` (real metadata → 13 records, string rfilename, numeric size), `t_error_object_fallback` (`{"error":"x"}` → `[]` rc 0).
- `t_code_sync` drift-guards updated: greps `select(type == "object" and .type == "file")` (primary) and `select(type == "object")` (fallback) in addition to the GGUF guard + fn filter.

### Harden verification results

1. `bash -n bin/pos-ai-hf` → OK
2. `bash /tmp/opencode/hf-test2/run-tests.sh` → **12 passed, 0 failed** (was 9; +3 new assertions)
3. `make gen && make check && make lint` → gen OK, check-sync OK, **0 FAIL, 0 WARN**; `git diff --stat`: `bin/pos-ai-hf | 19 ++++---` (4 sanctioned hunks: normalize + fallback + gguf guard + message branch + comment), `DOC/AGENT_Context_Project.md | 2 +-` (line-count row from prior gen; unchanged by this pass)
4. LIVE (real API, no download): Qwen tree → hardened normalize `{"count":13,"nulls":0}`; hardened `--gguf` filter → 10; README/LICENSE/.gitattributes excluded → `OK`
5. Still NOT committed; only intended files modified (bin/pos-ai-hf, DOC line-count row) + untracked reports.