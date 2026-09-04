# Builder Report: `pos ai server` — llama.cpp Inference Server

## TL;DR

- **Status:** IMPLEMENTED
- **Files created:** `bin/pos-ai-server`, `lib/ai-providers/llamacpp.sh`
- **Files modified:** `bin/pos-ai` (4 case additions + POS_CONFIG header), `config/ai.env` (LLAMACPP_* docs), `DOC/POS.md` (ai server docs)
- **Test harness:** `/tmp/opencode/llamacpp-test/run-tests.sh` — 87/87 passing
- **Verification:** `make gen && make check && make lint` = 0 FAIL, 0 WARN

## Step 1: Create `bin/pos-ai-server`
[DONE] — chmod 100755, syntax check passed, all conventions followed (set -euo pipefail, deps guards before --help, POS/POS_SUBCMDS/POS_FLAGS/POS_DEPS headers, common.sh source chain, err/log/warn/ok helpers, config seam guards)

## Step 2: Create `lib/ai-providers/llamacpp.sh`
[DONE] — PROVIDER_CONFIG header present, 4-function contract (provider_name, provider_default_model, provider_generate, provider_models_list), syntax check passed

## Step 3: Modify `bin/pos-ai` — 4 case additions
[DONE] — resolve_key: llamacpp returns 0 (no key needed), resolve_model: reads LLAMACPP_MODEL, cmd_providers: always "configured", require_key: llamacpp case (no key needed). POS_CONFIG header updated with LLAMACPP_* keys. Syntax check passed.

## Step 4: Modify `config/ai.env` — add LLAMACPP_* docs
[DONE] — All 6 LLAMACPP_* config keys documented with defaults

## Step 5: Add POS.md documentation
[DONE] — ai section updated with file references, server command table, flags, and config keys

## Step 6: Create test harness
[DONE] — `/tmp/opencode/llamacpp-test/run-tests.sh` with 45 test groups (87 individual assertions), 0 failures. Tests cover: help/dispatch, error handling, start (config/arg/fallback), systemd unit generation (all fields), GPU detection (CPU/CUDA), model resolution (config/arg/relative/TTYPick), stop/status/models/logs, dry-run mode, flag overrides, POS headers, deps guards, pos-ai modifications.

## Step 7: Verification
[DONE] — All gates pass:
- `bash -n bin/pos-ai-server` — OK
- `bash -n lib/ai-providers/llamacpp.sh` — OK  
- `bash -n bin/pos-ai` — OK
- Test suite: 87/87 passed
- `make gen` — OK
- `make check` — OK
- `make lint` — 0 FAIL, 0 WARN
