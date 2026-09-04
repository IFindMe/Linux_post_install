# Detective Report — `pos-ai-hf` GGUF/jq bug (2026-09-04)

## TL;DR
- **Status:** ROOT_CAUSE_ESTABLISHED
- **Symptom:** `pos ai hf download Qwen/Qwen2.5-3B-Instruct-GGUF --gguf --output ~/.models` crashes with `jq: error (at <stdin>:0): endswith() requires string inputs` (jq exit 5, after `[!] No HF_TOKEN set` warning).
- **Root cause (FACT):** `hf_repo_files()` primary path (`bin/pos-ai-hf:199-204`) returns the **raw HF tree API response**, whose entries have keys `oid, path, size, type` — **no `rfilename`**. Every consumer of `files_json` reads `.rfilename` → gets `null`. Line 336 (`endswith(".gguf")` on null) is the crash site. **The user's null-guard alone is insufficient**: with the guard, `--gguf` would silently filter everything out → `err "No files to download"` (exit 1) instead of downloading the 10 GGUF files. All other modes are also silently broken for every tree-served repo: single-file mode matches nothing, all-files mode writes `null` into the download URL (404), metadata, and summary.
- **Fix:** normalize the tree response in `hf_repo_files()` to `[.[] | select(.type == "file") | {rfilename: .path, size: (.size // 0)}]` (same shape the fallback already emits), plus a defense-in-depth string guard on the `--gguf` filter and mode-aware empty-result messages. Verified: 13 files normalize, `--gguf` selects the 10 `.gguf` files, single-file/all-files/meta/summary all work unchanged. Live API validation passed (10/10, 0 non-gguf, 0 nulls).
- Expected net change: raw tree result transformed upstream; no semantics change for already-working repos.
- Artifacts: this report; fixtures/harness spec → `/tmp/opencode/hf-test2/` (Builder builds it; harness spec in Step 5). No changes made by Detective (read-only).

## Step 1: Confirm + quantify the crash and every `.rfilename` read — [DONE]

Fixture `/tmp/opencode/qwen-tree.json` (live capture of `GET /api/models/Qwen/Qwen2.5-3B-Instruct-GGUF/tree/main`): 13 entries, **all `type:"file"`**, keys per entry `oid, path, size, type`, **no `rfilename`**; 10 entries carry `lfs`. `.path` column: `.gitattributes, LICENSE, README.md, qwen2.5-3b-instruct-{fp16-00001-of-00002,fp16-00002-of-00002,q2_k,q3_k_m,q4_0,q4_k_m,q5_0,q5_k_m,q6_k,q8_0}.gguf`.

Exact reproduction (the exact code, same exit code as the tool — jq exit 5):
```
$ jq -c '[.[] | select(.rfilename | endswith(".gguf"))]' /tmp/opencode/qwen-tree.json
jq: error (at qwen-tree.json:0): endswith() requires string inputs   # exit=5
```

Every downstream `.rfilename` read, observed (not inferred):

| Line | Code | Observed with qwen tree | Verdict |
|---|---|---|---|
| 333 | single-file `select(.rfilename == $fn)` | `[]` for any fn (`null == "README.md"` → false; exit 0) | silent no-match → `err "No files to download"` |
| 336 | `--gguf` `select(.rfilename \| endswith(".gguf"))` | **jq error exit 5** (the reported crash) | the crash |
| 339 | all-files `jq -c '.'` | passes all 13 (no filter) | nothing filtered, but downstream 372 breaks |
| 372 | loop `jq -r '.rfilename'` | `null` ×13 | URL `…/resolve/main/null` → 404; `curl -o` left an empty `null` file; loop `warn`ed |
| 398 | meta `[.[] \| .rfilename]` | `[null,null,…13]` | `.hf-meta` `files` list all null |
| 412 | one-file summary `.[0].rfilename` | `null` | `Downloaded: …/null` |

`jq empty` (line 181), `.size // 0` (lines 373, 414), `[.[].size // 0] \| add // 0` (line 353): unaffected — size handling is already null-safe.

**Fallback shape verified live** (`GET /api/models/Qwen/Qwen2.5-3B-Instruct-GGUF` → `jq '[.siblings[] | {rfilename: .rfilename, size: (.size // 0)}]'`): 13 entries, 0 null rfilename, all `size: 0` (metadata API has no per-sibling sizes). Shape `{rfilename, size}` — exactly what the normalization produces for the tree path. **Fallback path needs no change.**

## Step 2: Unsafe-jq sweep (whole file `bin/pos-ai-human`) — [DONE]

All jq expressions in `bin/pos-ai-hf`, with assessment (only c/p rfilename-related ones are the bug family):

| Line | Expression | Assessment |
|---|---|---|
| 181 | `jq empty` on API body | validation only; safe |
| 210 | `[.siblings[]\|{rfilename:.rfilename, size:(.size//0)}]` | correct shape; null-safe; **leave as is** |
| 217 | `jq -sRr @uri` (query encode) | safe |
| 254 | `.defaultBranch // empty` | null-safe; safe |
| 298 | `jq 'length'` (search) | safe |
| 302 | `.[] \| "…\(.id)…\(.downloads // 0)…\(.likes // 0)"` | search API provides these; `// 0` guards; safe |
| **333** | `select(.rfilename == $fn)` | **AFFECTED**: null vs string → silently `[]`. Fixed by normalization (works after); no other string-op risk. |
| **336** | `select(.rfilename \| endswith(".gguf"))` | **THE CRASH**. Category (a): string function on possibly-null field. |
| 339 | `jq -c '.'` | passthrough; safe |
| 343 | `jq 'length'` | safe |
| 353 | `[.[].size // 0] \| add // 0` | null-safe on size; safe |
| **372** | `jq -r '.rfilename'` | **Affected**: prints literal `null` → bad URL/404 + empty `null` target file |
| 373 | `jq -r '.size // 0'` | null-safe; safe |
| **398** | `jq -c '[.[] \| .rfilename]'` | **Affected**: meta list all nulls |
| **412** | `jq -r '.[0].rfilename'` | **Affected**: summary prints `null` |
| 414 | `jq -r '.[0].size // 0'` | null-safe; safe |
| 447 | `jq -r '.downloaded_at // "unknown"'` (meta file) | safe; meta file is JSON |

Category (a) string-function-on-null type: only line 336 in this file (no `startswith`/`contains`/`test` in `pos-ai-hf` at all — grep confirmed; the other matches above are in other tools/service files, out of scope). Category (b) assumes-field-primary-API-returns: only the rfilename family above (lines 333/336/372/398/412). Category (c) covered in Step 1. Category (d) silent no-match on null: line 333 (only one). **No other crash-class bugs found; the rfilename family is the whole story.**

Related-but-out-of-scope notes (observations, not part of this fix):
- `hf_api` uses `curl -sS` without `-L`; HF redirects some aliases (verified: `runwayml/stable-diffusion-v1-5/tree/main` → 307 → `stable-diffusion-v1-5/stable-diffusion-v1-5`). Such repos fail on BOTH tree and fallback (`API request failed (HTTP 307)`). Pre-existing; unrelated to this bug; would need `-L` or canonical-resolution; flag to Builder/Architect, don't fold in.
- Tree endpoint is non-recursive; repos with subdirectories (e.g. SD-v1-5: `feature_extractor/`, …) only list top-level entries + `type:"directory"` markers. Fix filters out directories → all-files mode skips subdir files (same as pre-bug behavior; tree path never listed them). Optional follow-up: `?recursive=true` — requires `# POS_FLAGS`/docs change, NOT part of this minimal fix.
- `hf_download_file` URL building concatenates raw `path` into URL; files with spaces would need URL-encoding (`@uri`). Pre-existing; rare for models; not this bug.
- Names that are `-`, `.` etc. unaffected.

## 3. `hf_download_file` / `hf_api` related to THIS bug — [DONE]

- `hf_download_file` (264-286): no field assumptions of its own; takes URL+target. It is a victim: with raw-tree null rfilename, URL `…/resolve/main/null` returns 404, curl fails → `warn "Download interrupted for null (resume…)"`, and an empty `null` file remains in the model dir (then `cmd_list` counts it as size 0). After normalization the function works as designed (has `-L` for HF's 302→CDN; `-C -` resume; empty-file guard). **No change needed.**
- `hf_api` (134-186): 200/401/403/404/429 handling + `jq empty` validation — nothing rfilename-related. **No change needed** (the 307 note in Step 2 is separate).
- `hf_resolve_branch` (241-261): live-verified defaultBranch "main" resolves fine; unaffected.

## 4. Fix spec — Builder-executable — [DONE]

**Objective:** make the primary tree path emit the same `{rfilename, size}` shape the rest of the file (and the fallback path) already assume. Minimal, CLI semantics preserved (all options, filters, messages keep their meaning; only multi-mode empty-result messages get mode-specific text).

Where: `hf_repo_files()` body, primary branch, current lines 198-204.

**Change 1 — normalize tree response (the fix).** Replace:
```bash
    local endpoint="/models/${ns}/${repo}/tree/${branch}"
    local result
    if result="$(hf_api "$endpoint" 2>/dev/null)"; then
        printf '%s' "$result"
        return 0
    fi
```
with (exact code for Builder):
```bash
    local endpoint="/models/${ns}/${repo}/tree/${branch}"
    local result
    if result="$(hf_api "$endpoint" 2>/dev/null)"; then
        # Tree API returns {type,path,size,oid[,lfs]} per entry — normalize to the
        # {rfilename,size} shape the rest of the pipeline expects (same as fallback).
        # Skip "directory" entries: they have no resolvable file URL.
        printf '%s' "$result" | jq '[.[] | select(.type == "file") | {rfilename: .path, size: (.size // 0)}]'
        return 0
    fi
```
- This reuses the exact jq via one pipe; `set -euo pipefail` semantics: if the transform ever fails, `result` was already valid JSON so it fails before the pipe — fine (same failure mode as a jq typo elsewhere).
- `.size // 0` covers entries lacking `size` (dirs carry size 0; all observed files carry real size incl. LFS files, whose top-level `size` is the true byte size).
- Do NOT change the fallback (lines 210-211) — it already emits `{rfilename, size}` (had the same shape requirement; verified live).
- Edge: tree returning a non-array (code-200 error object) — `[.[] | select… | {…}]` yields `[{rfilename:null}]`-style or `[]`; `--gguf` guard + Step-3 messages convert that to a graceful error. Acceptable; no extra guard required.

**Change 2 — defense-in-depth guard in the `--gguf` filter (line 336).** Recommended, type-check form (strictly safe even if `rfilename` were a non-string non-null):
```bash
        filtered_files="$(printf '%s' "$files_json" | jq -c '[.[] | select((.rfilename | type) == "string" and (.rfilename | endswith(".gguf")))]')"
```
Equivalent accepted: `select(((.rfilename // "") | endswith(".gguf")))}`  — both are purely defensive here (normalized data always strings); must NOT become a replacement for Change-2-Normalization: with normalization, guard-or-not both select the 10 gguf. Verified equivalent on fixture: guarded 10, unguarded 10.

**Change 3 — mode-aware "no files" message (replaces line 344, `[ "$file_count" -gt 0 ] || err "No files to download"`).** Keep exit-1 semantics, distinct messages per mode:
```bash
    local file_count
    file_count="$(printf '%s' "$filtered_files" | jq 'length')"
    if [ "$file_count" -eq 0 ]; then
        if [ -n "$filename" ]; then
            err "File not found: $filename in $repo_id (branch: ${branch})"
        elif [ "$GGUF_ONLY" -eq 1 ]; then
            err "No .gguf files found in $repo_id${branch:+ (branch: $branch)} — try without --gguf"
        else
            err "No files to download"
        fi
    fi
```
Not required for the crash fix; required by edge-case spec (no-gguf repo → graceful, distinct message, not crash), and fixes the misleading "No files to download" in single-file mode.

**Line content checks after Changes 1-3 (verified by fixture/live):**
- single-file line 333: fits; `select(.rfilename == $fn)` on normalized → 1 for exact `README.md` / `qwen2.5-3b-instruct-q4_k_m.gguf`.
- all-files line 339: fits; loop line 372 pulls real rfilename; size line 373 real; meta line 398 real list; summary 412 real.
- **Lines 372/373/376/377/398/412 need NO change** once normalized (checked on fixture).

## 5. Edge cases — [DONE]

| Case | Behavior before fix | After fix |
|---|---|---|
| Repo w/ only `type:"directory"` (tree) | null → crash/downstream; e.g. gguf mode crashes, all-files nulls | `select(.type=="file")` → `[]` → mode-aware graceful error |
| Empty array / empty siblings tree | crash / silent | `[]` → graceful error |
| `--gguf` on repo w/o .gguf | crash | `err "No .gguf files found in …"` (exit 1, no crash) |
| File entry missing `size` / size:0 | `.size // 0` everywhere → ok | unchanged; normalization also `// 0` |
| LFS files (`.gguf` 2GB+) | n/a (never reached) | sizes real (`2104932768`); disk pre-check works |
| Repo w/ subdirs (non-recursive tree) | null loop | dirs filtered; subtree files not listed — pre-existing semantics (flag in Step 2, decision boundary for follow-up only) |
| `--branch` non-main | field absent regardless | branch is only URL+tree-parameter; normalized same way |

## 6. Test plan (harness spec for Builder) — [DONE]

**Location:** `/tmp/opencode/hf-test2/` (workspace must NOT gain test files; repo has no harness for pos-ai-hf; user requirement = new fixture-based harness).

**Key constraint — DO NOT `source` bin/pos-ai-hf in the harness**: the tool executes flag parsing + `usage`/`cmd_download` at top level (`set -euo pipefail`; no-args → `usage` → `exit 0` is a NAK). The harness must test the **jq transforms in isolation** (option b of the brief). Extraction of the functions via `sed -n` is __not__ recommended (fragile); fix the documented transforms — the transforms ARE the bug.

**Fixture files (create in harness setup, static content):**
- `fixtures/tree-files.json` — copy of `/tmp/opencode/qwen-tree.json` (13 files, rfilename ABSENT; 10 .gguf).
- `fixtures/tree-with-dirs.json` — copy of `/tmp/opencode/sd-tree.json` (8 files + 7 `type:"directory"`).
- `fixtures/tree-empty.json` — `[]`.
- `fixtures/tree-nogguf.json` — e.g. `[{"type":"file","path":"README.md","size":100}]`.
- Set at top: `NORM='[.[] | select(.type == "file") | {rfilename: .path, size: (.size // 0)}]'` and `GGUF_FILTER='[.[] | select((.rfilename | type) == "string" and (.rfilename | endswith(".gguf")))]' FN_FILTER='[.[] | select(.rfilename == $fn)]'` — **duplicated strings; if either diverges from the file, tests catch drift when `grep -F` checks below run.**

**Assertions (each a small `t_<name>` function; count PASS/FAIL; exit non-zero on any fail):**
1. `t_tree_normalize`: `jq -c "$NORM" tree-001.json` → length 13; every `.size` is number; no entry has `rfilename == null`.
2. `t_gguf_on_normalized`: pipe NORM(tree-001) → GGUF_FILTER → length 10; contains `qwen2.5-3b-instruct-q4_k_m.gguf`; NOT contains `README.md`/`LICENSE`/`.gitattributes`.
3. `t_single_file`: `jq -c --arg fn "qwen2.5-3b-instruct-q4_k_m.gguf" "$FN_FILTER"` on NORM(tree-001) → length 1; on `--arg fn "no-such-file"` → 0 (no crash).
4. `t_all_files_passthrough`: `jq -c '.'` → 13; loop pipe `.[]` → 13 rows, each with string rfilename (no `null`).
5. `t_empty`: NORM on tree-empty.json → `[]` | run the mode-0 guard → error message path (grep the code); i.e. assert `printf '[]' | jq "$NORM"` outputs `[]` and file_count logic (replicate `[ "$(…|jq 'length')" -eq 0 ]`) succeeds.
6. `t_nogguf`: NORM(tree-nogguf.json) → GGUF_FILTER → length 0, no crash; assert the code contains the "No .gguf files" branch (grep).
7. `t_defense_guard`: pipe **raw** qwen-tree.json (unnormalized) through GGUF_FILTER → length 0, exit 0 (proves guard null-proof and non-weakening: the sole difference 10→0 is caused by normalization, guard itself no-op).
8. `t_dirs_excluded`: NORM(tree-with-dirs.json) → length 8 (files only; 7 dirs dropped).
9. `t_code_sync` (drift check): `grep -Fq 'select(.type == "file")' <repo>/bin/pos-ai-hf` and `grep -Fq 'endswith(".gguf")'` present — catches D it if Builder changed jq inline, test stays honest.

**Live smoke (optional; fast, no download):** `curl` tree for Qwen → NORM → GGUF_FILTER → assert 10 rfilenames, 0 README. (This exact pipe was executed in Step 1; pass.)

## 7. Verification commands for Builder (after implementing)

- `bash -n bin/pos-ai-hf` (repo copy — the installed /usr/local/bin copy is byte-identical; contract must be fixed in the repo copy).
- `bash /tmp/opencode/hf-test2/run-tests.sh` → all PASS.
- `make gen && make check && make lint` → doc tables/registry unchanged; expect green, `0 FAIL, 0 WARN`, and `git diff` limited to `bin/pos-ai-hf` (+ any doc touch required by CONVENTION pointers; no GEN:START/END blocks change).
- Live no-download validation (already demonstrated passing):
```bash
curl -sS "https://huggingface.co/api/models/Qwen/Qwen2.5-3B-Instruct-GGUF/tree/main" \
  | jq '[.[] | select(.type=="file") | {rfilename:.path,size:(.size//0)}]' \
  | jq '[.[] | select(.rfilename|endswith(".gguf"))]' | jq 'length'   # expect 10, no README/LICENSE
```
- Optional tiny-download proof: `pos ai hf download Qwen/Qwen2.5-3B-Instruct-GGUF LICENSE --output /tmp/hf-small` → expect `.hf-meta` listing `LICENSE` and 1-file summary with real size; deletes nothing else.
- Full ~2GB download verified: OUT OF SCOPE (explicit).

## Handoff

Status: **ROOT_CAUSE_ESTABLISHED**
- Symptom: crash `jq: endswith() requires string inputs` (line 336) on --gguf; silent no-match single-file; `null` URLs/meta/summary in all-files.
- Expected vs actual: primary tree response should look like the siblings metadata (`rfilename`-keyed) but arrives free-`.rfilename` keys; first divergence = `hf_repo_files` returns raw tree (line 201-204).
- Root cause: missing shape normalization of `/tree` response in `hf_repo_files()` — user's endswith guard insufficient (guarded --gguf would download 0 files / "No files to download").
- Classification: FACT (crash & downstream effects reproduced on live fixture; normalization + guard live-validated elsewhere).
- Alternatives eliminated: (a) network/API failure — endpoints live 200 & JSON; (b) `rfilename` present but null — keys are absent (but `oid,path,size,type`), confirmed on fetch; (c) fallback path defect — live-verified correct shape; (d) curl/URL issue in hf_download_file — reached only if loop got a non-null name; function itself defect-free.
- Affected components: `bin/pos-ai-hf` — `hf_repo_files()` (primary branch), `cmd_download()` lines 333/336/341-344 (message branch), and downstream read sites 372/398/412 (no change needed once normalized).
- Recommended next agent: **Builder** — fix is exactly scoped: one transform in `hf_repo_files()`, one defense-in-depth guard line, one message branch; implement per spec Step 4 and run Step 7 verification. **Tester** (after Builder) — no committed harness; new /tmp/opencode/hf-test2 harness + optional repeat live tests; recommend adding to repo test suite if project adopts (decision boundary: Architect).
- Remaining uncertainty: none material on the bug; only flagged out-of-scope items (hf_api `-L`/307 for alias repos; non-recursive tree semantics) for maintainers.
- Changes made by Detective: none (read-only).