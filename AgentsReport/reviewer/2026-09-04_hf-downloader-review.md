# Reviewer Report — `pos ai hf` (Hugging Face Model Downloader)

**Date:** 2026-09-04
**Status:** CHANGES_REQUIRED

---

## TL;DR

**Verdict: CHANGES_REQUIRED**

Reviewed: `bin/pos-ai-hf` (470 lines), `DOC/POS.md` updates, generated docs/completions, AGENT_TODO entry.

**1 BLOCKING finding** — `total_size` accumulated inside a pipe subshell is always 0, so multi-file download summaries show incorrect total size. **2 REQUIRED findings** — missing disk space pre-flight check (architect-specified) and missing `hf_repo_files` API fallback (architect-specified). **2 SUGGESTED findings** — rate-limit HEAD request inefficiency and error message format deviation.

| Severity | Count |
|----------|-------|
| BLOCKING | 1 |
| REQUIRED | 2 |
| SUGGESTED | 2 |
| NOTE | 3 |

---

## Checklist Results

### Code Quality

| Item | Status | Evidence |
|------|--------|----------|
| `set -euo pipefail` present | [PASS] | Line 2: `set -euo pipefail` |
| `# POS:` header correct format with em-dash | [PASS] | Line 3: `# POS: ai hf — Download AI models from Hugging Face (search, download, manage)` — em-dash `—` confirmed |
| `# POS_FLAGS:` correct | [PASS] | Line 4: `# POS_FLAGS: --branch --gguf --output` — matches actual flag parsing (lines 88-109) |
| `# POS_DEPS:` correct | [PASS] | Line 5: `# POS_DEPS: curl jq` — matches deps guards on lines 17-18 |
| `# POS_CONFIG:` correct format | [PASS] | Line 6: `# POS_CONFIG: ai \| ai.env \| HF_TOKEN=secret:… \| HF_DOWNLOAD_DIR=:…` — uses `secret:` prefix convention matching other tools (pos-docker-compose, pos-communication-matrix-sender, pos-communication-telegram-sender) |
| `# POS_EXAMPLES:` present | [PASS] | Lines 7-12: 6 example lines covering search, download (repo, gguf, single file), list, remove |
| Sources `lib/common.sh` via standard fallback | [PASS] | Line 14: `source "$(dirname "$0")/../lib/common.sh" 2>/dev/null \|\| source "$(dirname "$0")/common.sh"` — exact template pattern |
| Deps guards BEFORE `-h\|--help` | [PASS] | Lines 17-18 (deps) before line 90 (`-h\|--help` case) |
| `usage()` present and comprehensive | [PASS] | Lines 44-79: all 4 subcommands, download options, examples, config keys, exit codes documented |
| All 4 subcommands implemented | [PASS] | `cmd_search` (line 279), `cmd_download` (line 303), `cmd_list` (line 402), `cmd_remove` (line 438); dispatch at line 464 |
| Config loader reads `ai.env` with env-var precedence | [PASS] | `load_hf_config()` (lines 25-39): reads `CONFIG_FILE`, env-already-set wins (`if [ -z "${!k:-}" ]`), strips quotes, CR, comments |
| Auth header: `Authorization: Bearer $HF_TOKEN` | [PASS] | `hf_auth_header()` (lines 128-132): `printf 'Authorization: Bearer %s' "$HF_TOKEN"` |
| Rate limit handling: 429 → sleep + retry | [PASS] | Lines 150-167: loop with `attempt < 2`, on 429 extracts `Retry-After` or defaults 60, sleeps, retries once |
| Resume: `curl -C -` | [PASS] | Line 259: `curl_args=(-L -C - --progress-bar -o "$target")` |
| `.hf-meta` metadata tracking | [PASS] | Lines 368-382: writes JSON with repo_id, branch, timestamp, files array |
| Output matches contract (emojis, paths, sizes) | [PASS] | Lines 392-398: 📥 and 📁 emojis, repo-id, size, path format matches Architect Decision 6 |
| Error handling: 404 | [PASS] | Line 175: `err "Model not found: ${endpoint#/api/models/}"` |
| Error handling: 401/403 | [PASS] | Line 174: `err "Authentication failed — check HF_TOKEN (pos config ai)"` |
| Error handling: 429 | [PASS] | Line 176: `err "Rate limit exceeded — try again later"` |
| Error handling: timeout | [PASS] | Line 153: `err "Connection timed out — check network"` |
| Error handling: jq parse | [PASS] | Line 182: `err "Failed to parse API response — check network or HF status"` |
| Error handling: no token | [PASS] | Line 121: `warn "No HF_TOKEN set — using anonymous access"` — continues for public repos per spec |
| All file paths seam-guarded | [PASS] | `CONFIG_FILE="${CONFIG_FILE:-$HOME/…}"` (line 21), `HF_TOKEN="${HF_TOKEN:-}"` (line 22), `HF_DOWNLOAD_DIR="${HF_DOWNLOAD_DIR:-$HOME/…}"` (line 23), re-guarded at line 117 after `--output` override |
| No `err "msg" 1` pattern | [PASS] | All 19 `err` calls use `err "message"` with no trailing exit code — confirmed by grep |

### Convention Compliance

| Item | Status | Evidence |
|------|--------|----------|
| `bash -n` passes | [UNVERIFIED] | Cannot execute `bash -n` due to sandbox restrictions. Builder claims pass. |
| `make gen && make check` passes | [UNVERIFIED] | Cannot execute make. Builder claims pass. Generated files (AGENT_Context, completions) contain correct entries. |
| `make lint` passes (0 FAIL, 0 WARN) | [UNVERIFIED] | Cannot execute make. Builder claims 0 FAIL, 0 WARN. |
| Tool is executable (chmod 100755) | [UNVERIFIED] | Cannot check permissions. `git ls-files` shows file is tracked. Builder claims chmod 100755. |
| POS.md has `ai hf` row + detail block | [PASS] | POS.md line 58: `bin/pos-ai-hf` in `**File:**` line. Lines 103-112: command table + auth/rate-limit/resume detail block. |
| No INTERACTIVE_CMDS change needed | [PASS] | `bin/pos` line 269: `pos-ai-hf` NOT in `INTERACTIVE_CMDS` string — tool does not read stdin. |
| No changes to `bin/pos-ai` | [PASS] | Grep for "hf" in `bin/pos-ai` returns 0 matches. |
| No changes to `bin/pos` | [PASS] | `pos-ai-hf` not in `INTERACTIVE_CMDS`. No other modifications visible. |
| No changes to `preinstall.sh` | [PASS] | Not in git diff. |
| No changes to `lib/common.sh` | [PASS] | Not in git diff. |
| Generated docs contain ai-hf | [PASS] | AGENT_Context: tree line 66, dispatch line 283, filetable line 613. Completions line 6: `_pos_flags[ai-hf]="--branch --gguf --output"` |
| AGENT_TODO Done entry added | [PASS] | Git diff shows new entry at top of Done section, dated 2026-09-04. |

### Security

| Item | Status | Evidence |
|------|--------|----------|
| Token never printed in output | [PASS] | `$HF_TOKEN` referenced only at lines 22, 120, 129-130, 138, 257 — none in any `printf`/`echo` output path. Token warning (line 121) only prints the literal string "No HF_TOKEN set". |
| Token passed via header, not URL | [PASS] | Lines 128-132: `hf_auth_header()` constructs `Authorization: Bearer …` header. Lines 144-146, 260-262: added as `-H` arg to curl. Never in URL string. |
| Config file permissions (ai.env chmod 600) | [UNVERIFIED] | Tool reads from `~/.config/linux_post_install/ai.env`. The chmod is set by `postinstall.sh` (not by this tool). The tool does NOT change permissions — correct behavior. |
| No command injection via repo-id | [PASS] | `repo_id` is user input. Used in: API endpoint construction (line 198-199, passed as curl URL arg — safe), `hf_repo_dir()` (line 214: string substitution `${repo_id//\//-}` — safe), jq filter argument (line 322: `--arg fn "$filename"` — safe), `.hf-meta` heredoc (line 375-382: unquoted heredoc — variables expanded but context is JSON file, not shell execution). No `eval`, no `exec` with user-controlled path. |
| No command injection via filenames | [PASS] | Filenames from API response are parsed by `jq -r` and used in path construction (`$target="${target_dir}/${fname}"`). Passed to `mkdir -p` and curl `-o` — no shell interpretation of the filename value itself. |

---

## Step 1: Subshell Variable Loss in Multi-File Downloads

[FAIL — BLOCKING]

**Finding:** In `cmd_download`, the multi-file download loop at lines 345-366 runs inside a pipe (`printf … | jq … | while IFS= read -r file_json; do … done`). In bash, a pipe creates a subshell, so variables modified inside the `while` loop — specifically `$total_size` (line 349) and `$downloaded` (line 355) — are lost when the pipe exits. The summary section at line 396 reads `$total_size` which is still `0` from its initialization at line 340.

**Severity:** BLOCKING
**Certainty:** FACT — provable from bash subshell semantics. `cmd | while read; do var=...; done` runs the while body in a subshell. Variables set inside do not propagate back.
**Evidence:**
- Line 340: `local total_size=0`
- Line 345: `printf … | jq … | while IFS= read -r file_json; do` — pipe creates subshell
- Line 349: `total_size=$((total_size + fsize))` — modified inside subshell, lost
- Line 396: `total_human="$(hf_human_size "$total_size")"` — reads `0`
**Relevant files/lines:** `bin/pos-ai-hf:340-398`
**Approved scope reference:** Architect Decision 6 (Output Contract) specifies multi-file summary as "📥 Downloaded: meta-llama/Llama-3.1-8B-Instruct (7 files, 4.7 GB)" — the size should be the correct total.
**Why it matters:** Every multi-file download (the common case for large models) will print "0 B" as the total size. This is a user-visible incorrect output and directly violates the Architect's output contract.
**Test mask:** The test harness (Test 22, line 151) checks for `[0-9] B)` which matches "0 B)" — the test passes on the bug. The test needs to check the actual expected sum (618 + 8500000000 + 9000000 + 5000 + 200 + 500 = 8509017318 bytes ≈ "8.5 GB").
**Suggested fix:** Replace the pipe with process substitution (`while IFS= read -r file_json; do … done < <(printf '%s' "$filtered_files" | jq -c '.[]')`) to keep the loop in the main shell, or accumulate total_size via a temp file or another jq pass on `$filtered_files` before the loop.

---

## Step 2: Missing Disk Space Pre-Flight Check

[FAIL — REQUIRED]

**Finding:** The architecture (Decision 5, "Key implementation details" table, and Decision 7, "Error matrix" row) specifies a pre-flight disk space check: `df` available space vs estimated total (from `/tree/` endpoint), with a warning when space is critically low. The implementation has no disk space check at all.

**Severity:** REQUIRED
**Certainty:** FACT — no `df` or `stat`-based space check anywhere in the file (confirmed by grep).
**Relevant files/lines:** `bin/pos-ai-hf` — absent between line 333 (file count check) and line 337 (mkdir).
**Approved scope reference:** Architect Decision 5: "Disk space | Pre-flight check: `df` available space vs estimated total (from `/tree/` endpoint)" and Decision 7: "Disk space | `df` pre-flight | `warn "Low disk space: need {N} GB, only {M} GB available"` then continue (user's call)".
**Why it matters:** Downloading a 7-8 GB model on a near-full disk is a waste of time and leaves partial files. The architecture explicitly chose a non-blocking warning (not an error) — the user makes the final call. Without this, users discover the problem only after curl fails mid-file.
**Suggested fix:** Before the download loop, sum the sizes from `$filtered_files` (this also solves the subshell bug if using jq for the sum), compare with `df --output=avail "$target_dir"`, and `warn` if insufficient. This is a ~5 line addition.

---

## Step 3: Missing `hf_repo_files` API Fallback

[FAIL — REQUIRED]

**Finding:** The architecture specifies `hf_repo_files()` should call `/api/models/{ns}/{repo}/tree/{branch}/` for file sizes, and fall back to `/api/models/{ns}/{repo}` for file list if the tree endpoint fails. The implementation only calls the tree endpoint (line 198) with no fallback.

**Severity:** REQUIRED
**Certainty:** FACT — line 198: `local endpoint="/models/${ns}/${repo}/tree/${branch}"` followed by a single `hf_api "$endpoint"` call. No fallback logic.
**Relevant files/lines:** `bin/pos-ai-hf:188-200`
**Approved scope reference:** Architect Decision 5 (`hf_repo_files()` signature): "Calls: GET /api/models/{ns}/{repo}/tree/{branch}/ for sizes, **falls back to /api/models/{ns}/{repo} for file list**"
**Why it matters:** Some HF repositories (e.g., datasets, some model repos) may not respond to the `/tree/` endpoint (404 or empty). The fallback to `/api/models/{ns}/{repo}` provides a file list (without sizes) so the user can still download. Without it, those repos fail entirely with a 404 error.
**Suggested fix:** Wrap the tree call in a conditional; on 404, call `/api/models/{ns}/{repo}` and construct a minimal `[{"rfilename": "<name>", "size": 0}]` array from the `siblings` array. `size` being 0 is acceptable (displays as "0 B") since the primary goal is getting the download list.

---

## Step 4: Rate-Limit Extra HEAD Request

[NOTE — SUGGESTED]

**Finding:** Line 158 makes a second `curl -sI` HEAD request specifically to extract the `Retry-After` header value after receiving a 429. This is an extra HTTP call that could itself be rate-limited, and the `Retry-After` header was already present in the original request's response (line 151 uses `-w '%{http_code}'` but does not capture response headers).

**Severity:** SUGGESTED
**Certainty:** FACT — line 158: `retry_after="$(curl -sI -H "${auth_header:-}" "$url" 2>/dev/null | grep -i 'retry-after:' | tr -d '\r' | awk '{print $2}')"`
**Relevant files/lines:** `bin/pos-ai-hf:156-161`
**Approved scope reference:** Architect Decision 5: "Rate limiting | Sleep 1s between files; on 429, wait `Retry-After` header value or 60s default"
**Why it matters:** Minor inefficiency. When already rate-limited, making another request is suboptimal. Could use `curl -sS -D -` (dump headers to stdout) in the original request to capture `Retry-After` directly, or simply default to 60s without the extra call.
**Suggested fix:** Change the original curl in `hf_api()` to use `-D -` (or a header dump file) so the `Retry-After` header is available from the first response without a second call.

---

## Step 5: Error Message Format Deviation

[NOTE — SUGGESTED]

**Finding:** The error message for invalid repo format at line 195 (`hf_repo_files`) says `"Invalid repo format: use namespace/model-name"` while the Architect specified `"Invalid repo format: use namespace/model-name"` at Decision 7. However, line 308 (`cmd_download`) also says the same message. The Architect's error matrix entry says `err "Invalid repo format: use namespace/model-name"` — which matches. This is consistent.

However, the Architect's error matrix says the model-not-found message should reference the full `repo-id` (e.g., `err "Model not found: {repo-id}"`), while the implementation at line 175 constructs the message from the API endpoint: `err "Model not found: ${endpoint#/api/models/}"`. The stripped endpoint value is the same as repo-id when the endpoint is `/models/{ns}/{repo}`, but if the endpoint is `/models/{ns}/{repo}/tree/{branch}`, the stripped value would be `{ns}/{repo}/tree/{branch}` — which is confusing.

**Severity:** SUGGESTED
**Certainty:** HYPOTHESIS — only manifests when 404 is returned from `/tree/{branch}` endpoint (which strips to `{ns}/{repo}/tree/{branch}` in the message). The normal `/models/{ns}/{repo}` path produces the correct repo-id in the message.
**Relevant files/lines:** `bin/pos-ai-hf:175`
**Why it matters:** Minor UX: a 404 from the tree endpoint would show a confusing path in the error message instead of the clean repo-id. The Architect's spec just says `{repo-id}`.
**Suggested fix:** Capture the `repo_id` and pass it to `hf_api` or handle the error at the caller level where `repo_id` is available. Or, in `hf_api`, accept an optional display-name parameter for error messages.

---

## Architect Compliance

| Decision | Implemented? | Notes |
|----------|-------------|-------|
| Decision 1: File location `bin/pos-ai-hf` | [YES] | Created at correct path |
| Decision 2: Subcommands (download, search, list, remove) | [YES] | All 4 implemented |
| Decision 3: Config scope extends `ai` | [YES] | `# POS_CONFIG: ai \| ai.env` — correct |
| Decision 4: Download directory layout | [YES] | `<namespace>-<model-name>/` under XDG data dir, `.hf-meta` metadata |
| Decision 5: Download logic | [PARTIAL] | Download flow correct; missing disk space check; missing API fallback |
| Decision 6: Output contract | [PARTIAL] | Emojis, paths correct; multi-file size is always 0 (subshell bug) |
| Decision 7: Error handling | [PARTIAL] | All error matrix cases handled; missing disk space pre-flight |
| Decision 8: Deps/lint compliance | [YES] | POS headers correct, deps before help, source chain |
| Decision 9: Testing strategy | [YES] | Stub-PATH harness exists at expected location with 46 tests |

**Deviations from Architect design:**
1. Disk space pre-flight check not implemented (architect-specified, REQUIRED).
2. `hf_repo_files` API fallback not implemented (architect-specified, REQUIRED).
3. Rate-limit handling uses extra HEAD request instead of extracting from original response (architect did not specify implementation detail — minor deviation).
4. Config loader is an inline pattern rather than copying from `bin/pos-ai` (functionally equivalent, not a deviation in behavior).

---

## Verification Verified

| Claim | Evidence | Status |
|-------|----------|--------|
| Builder: "46/46 tests green" | Test harness exists at `/tmp/opencode/hf-test/run-tests.sh` with 45 numbered tests visible (tests 1-45). Could not execute to confirm count. | UNVERIFIED |
| Builder: "make gen && make check OK" | Generated files (AGENT_Context line 66/283/613, completions line 6) contain correct ai-hf entries. | STRONG INFERENCE |
| Builder: "make lint 0 FAIL, 0 WARN" | All conventions verified by static analysis (POS headers, deps guards, source chain, exec bits claimed). | UNVERIFIED |
| Builder: "bash -n OK" | Cannot execute. No syntax errors visible by manual inspection. | UNVERIFIED |
| Builder: "POS.md updated" | Git diff confirms: ai File line updated (line 58), command table + detail block added (lines 103-112). | FACT |
| Builder: "No changes to bin/pos, bin/pos-ai, preinstall.sh, lib/common.sh" | `git ls-files` confirms these files tracked; grep confirms no hf-related changes. | FACT |

---

## Verification Unverified

| Claim | Reason |
|-------|--------|
| `bash -n` passes | Sandbox prevents execution |
| `make gen && make check` passes | Sandbox prevents execution |
| `make lint` 0 FAIL 0 WARN | Sandbox prevents execution |
| Tool is executable (100755) | Sandbox prevents `ls -la` |
| Test harness 46/46 passes | Sandbox prevents execution |
| Config file ai.env chmod 600 | Controlled by postinstall.sh, not this tool |

---

## Scope Compliance

**In-scope (confirmed):**
- `bin/pos-ai-hf` created with all 4 subcommands
- `DOC/POS.md` ai hf row + detail block
- Generated docs/completions updated via `make gen`
- `AGENT_TODO.md` Done entry

**Out-of-scope (confirmed NOT present):**
- No ollama integration
- No parallel downloads
- No changes to `bin/pos-ai`, `bin/pos`, `preinstall.sh`, `lib/common.sh`
- No new config scope (extends `ai`)
- No `INTERACTIVE_CMDS` change

**Unexpected changes:** None detected.

---

## Remaining Uncertainty

1. Whether `bash -n`, `make gen`, `make check`, and `make lint` actually pass — Builder claims they do, and generated artifacts are consistent with this, but execution was blocked.
2. Whether the 46 test cases actually all pass — the test harness exists with the correct structure, but Test 22 masks the subshell bug (checks for `[0-9] B)` which matches "0 B)").
3. Whether the tool is truly `chmod 100755` — Builder claims it is, file is in git index.
4. Live network behavior against real `huggingface.co` — only stub-tested, not end-to-end verified.

---

## Recommended Next Agent

**Builder**

**Reason:** The 1 BLOCKING finding (subshell variable loss) and 2 REQUIRED findings (disk space check, API fallback) are all within the approved scope and well-understood fixes. The Builder should:
1. Fix the subshell bug (replace pipe with process substitution or pre-compute sum via jq)
2. Add the disk space pre-flight check (~5 lines, `df` + `warn`)
3. Add the `hf_repo_files` fallback to `/api/models/{ns}/{repo}` on 404
4. Update Test 22 to check actual expected size value instead of regex `[0-9] B)`
5. Re-run `bash -n`, tests, and gates

---

## Changes Made by Reviewer

None — read-only review.
