# Builder Report — `pos ai hf` (Hugging Face Model Downloader)

**Date:** 2026-09-04
**Status:** DONE

---

## TL;DR

Implemented `bin/pos-ai-hf` per the architecture report: a bash-only (curl + jq) Hugging Face model downloader with `search`/`download`/`list`/`remove` subcommands, `ai`-scope config (`HF_TOKEN`, `HF_DOWNLOAD_DIR`), auth headers, HTTP 429 retry, `curl -C -` resume, `.hf-meta` bookkeeping, and emoji output. Test harness (46 cases) green; all gates pass.

| Item | Status |
|------|--------|
| `bin/pos-ai-hf` created | [DONE] |
| Syntax check | [DONE] |
| Test harness (46/46) | [DONE] |
| `make gen && make check` | [DONE] |
| `make lint` (0 FAIL, 0 WARN) | [DONE] |
| Doc updates (POS.md, AGENT_TODO.md) | [DONE] |

---

## Step 1: Create `bin/pos-ai-hf` from template + implement full tool

Implemented the full tool: config loader (env-var precedence over `ai.env`), `hf_api`/`hf_repo_files`/`hf_search` helpers, `cmd_search`/`cmd_download`/`cmd_list`/`cmd_remove`, usage/help, error handling, `.hf-meta` writing. Deps guards (`curl`/`jq`) before `--help`. `# POS: ai hf —`, `# POS_FLAGS`, `# POS_DEPS`, `# POS_CONFIG`, `# POS_EXAMPLES` headers present. Chmod 100755.

[DONE]

## Step 2: Syntax check (`bash -n bin/pos-ai-hf`)

`bash -n bin/pos-ai-hf` → Syntax OK.

[DONE]

## Step 3: Test harness (`/tmp/opencode/hf-test/run-tests.sh`)

Stub-PATH harness: stub `curl` routes by URL pattern to fixtures; 46 numbered tests covering argument parsing (missing/unknown/invalid), download (single file via `-o`, whole repo, `--gguf`, `--branch`, `--output`), search, list, remove, config/token handling, and output format (emoji, size header/table formats).

Fixed two harness issues along the way: Test 22 size grep double-match (corrected regex), Test 40 token warning (empty config file + unset `HF_TOKEN` when the tool re-reads the config after `unset`).

**Result:** 46/46 green, exit 0.

[DONE]

## Step 4: Gates — `make gen && make check && make lint`

- `make gen` → `gen-docs: write OK`
- `make check` → `check-sync: OK`
- `make lint` → **0 FAIL, 0 WARN**
  - Initially hit 1 WARN (`pos-ai-hf: file not referenced in DOC/POS.md`); added the `bin/pos-ai-hf` reference in the `### ai` `**File:**` line — lint green after.

Verified generated output: docmap/tree/filetable updated in AGENT_Context, `completions/pos.bash` gained `ai-hf` flags and `ai` subcmd list, dispatch (`pos ai --help`, `pos help ai hf`, `pos ai hf --help`) all resolve.

[DONE]

## Step 5: Doc updates (POS.md, AGENT_TODO.md)

- `DOC/POS.md`: added `bin/pos-ai-hf` to the `### ai` `**File:**` line, and a dedicated `pos ai hf` command table + auth/rate-limit/resume detail block under the ai section.
- `AGENT_TODO.md`: added a **Done** entry (newest-first, dated 2026-09-04) describing the tool, seam, config scope, verification.

[DONE]

---

## Verification Summary

- `bash -n bin/pos-ai-hf` — OK
- `/tmp/opencode/hf-test/run-tests.sh` — 46/46 passed, exit 0
- `make gen` — write OK
- `make check` — OK
- `make lint` — 0 FAIL, 0 WARN
- `git status --short` — only intended changes: `AGENT_TODO.md`, generated `DOC/AGENT_Context_Project.md`, `DOC/POS.md`, `completions/pos.bash`, new `bin/pos-ai-hf`, new report file.

## Remaining Risks / Follow-up

- No live-network smoke against the real `huggingface.co` was run (stub-based tests only); real end-to-end (auth 401/403, 429, 404, jq parse error paths) should be exercised manually on a machine with network access before first real use.
- `.hf-meta` uses a plain JSON object — no schema version field; acceptable for this scope.

## Handoff

Status: IMPLEMENTED

Approved scope:
`bin/pos-ai-hf` (from `templates/pos-tool.sh`), `DOC/POS.md`, `AGENT_TODO.md`, test harness, report. No changes to `bin/pos-ai`, `bin/pos`, `preinstall.sh`, `lib/common.sh`, or INTERACTIVE_CMDS.

Changes made:
New tool `bin/pos-ai-hf`; POS.md ai row + hf detail block; AGENT_TODO Done entry; generated docs/completions refreshed via `make gen`.

Files changed:
`bin/pos-ai-hf` (new), `DOC/POS.md`, `AGENT_TODO.md`, `DOC/AGENT_Context_Project.md` (generated), `completions/pos.bash` (generated), `AgentsReport/builder/2026-09-04_hf-downloader-implementation.md` (new).

Verification performed:
`bash -n`, 46/46 stub tests, `make gen && make check && make lint` (0 FAIL, 0 WARN).

Scope compliance:
In-scope changes only; no out-of-scope changes.

Recommended next agent:
Reviewer

Reason:
Implementation complete and gates green; needs independent adversarial review before acceptance.
