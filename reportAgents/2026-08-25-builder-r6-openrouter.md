# Builder R6 — `pos ai openrouter` + doc duplicate fix

## TL;DR
- Status: IMPLEMENTED — new tool + doc fixes; all gates green; 13 probes pass
- Files changed: `bin/pos-ai-openrouter` (new, 566 ln), `bin/pos` (+1 word: INTERACTIVE_CMDS), `DOC/howto/ai.md` (155→197 ln: duplicate fix + OpenRouter section), `DOC/POS.md` (500→521 ln: openrouter table), GEN regen
- Gates: bash -n OK (both tools) · `make gen` idempotent · `make check` OK · `make lint` **0 FAIL, 0 WARN**
- Probes (a)–(m): **13 PASS, 0 FAIL**

## Step 1: R5e — doc duplicate fix [DONE]
- `DOC/howto/ai.md` lines 137-138 (identical duplicate bullet about non-2xx response) → deleted one copy. 155→153 ln.
- Verified: grep -c "On a non-2xx response" returns 1.

## Step 2: Create `bin/pos-ai-openrouter` [DONE]
- Cloned from `bin/pos-ai-gemini` (565 ln) → 566 ln.
- Substitutions applied:
  - Header: `# POS: ai openrouter`, `# POS_SUBCMDS: ask chat models sessions`, `# POS_CONFIG: ai-openrouter`
  - Config: `CONFIG_FILE=ai-openrouter.env`, `API=https://openrouter.ai/api/v1`, `DEFAULT_MODEL=openrouter/auto`, `SESSION_DIR=ai-openrouter/`
  - All `AI_GEMINI_*` → `OPENROUTER_*`
  - `gemini_generate()` → `openrouter_generate()`: Bearer auth, HTTP-Referer header, `jq '.choices[0].message.content'`
  - Session format: `{"messages":[]}` (not `{"contents":[]}`); `session_push` uses `messages += [{role:$r,content:$t}]`
  - `cmd_models()`: OpenAI `/v1/models` endpoint, `.data[]?.id`, sorted list
  - `cmd_chat()`: banner shows `messages | length`, reset creates `{"messages":[]}`
  - `cmd_ask()`: uses `openrouter_generate`, saves as `assistant` role
  - `--last` error messages mention "openrouter" instead of "gemini"
  - `usage()` text: all examples use `pos ai openrouter`, config key `pos config ai-openrouter`
- jq fix: first jq expression in `openrouter_generate` uses `.messages` (extracts array from wrapper object), not bare `.` which would add array+object
- Unchanged: `render_markdown()`, `machine_context()`, `mc_clean()`, `newest_pos_log()`, `last_log_context()`, `human_age()`, `last_log_annotate()`, flag parsing block
- Executable: `chmod 755` confirmed

## Step 3: `DOC/howto/ai.md` — OpenRouter section [DONE]
- Header updated to mention both Gemini and OpenRouter
- New "OpenRouter — many providers, one key" section inserted after Gemini "First run" section
- Covers: key setup, `pos config ai-openrouter`, test command, default model `openrouter/auto`, override with `--model`, sessions path, feature parity note
- 155→197 ln total

## Step 4: `DOC/POS.md` — ai openrouter row [DONE]
- New `bin/pos-ai-openrouter` block added after Gemini section, before `### network`
- Includes: purpose, command table (ask/chat/sessions), configuration table (OPENROUTER_API_KEY, OPENROUTER_MODEL), precedence
- 500→521 ln total

## Step 5: `bin/pos` — INTERACTIVE_CMDS [DONE]
- Added `ai-openrouter` to the `INTERACTIVE_CMDS` list in `bin/pos:262` (lint requirement — tool reads stdin via `cat`)
- 1-word addition to existing string

## Step 6: Gates [DONE]
- `bash -n bin/pos-ai-openrouter` → clean (566 ln)
- `bash -n bin/pos-ai-gemini` → clean (565 ln, unchanged)
- `make gen` → OK; consecutive runs byte-identical → idempotent
- `make check` → `check-sync: OK`
- `make lint` → **0 FAIL, 0 WARN** (timeout headroom ≥300s)

## Step 7: Probes (a)–(m) — 13 PASS, 0 FAIL [DONE]
- (a) `ask "hello"` → body has `model` field + `messages` array + system msg first; no Gemini fields; response parsed from `choices[0].message.content`. PASS
- (b1) `--system CUSTOM9` → system message content is exactly "CUSTOM9". PASS
- (b2) `--full` → messages count = 1 (only user msg, no system). PASS
- (c) `--last` → context block appended to user turn, stderr annotation shows log name + age. PASS
- (d) Default session persists: 2→4 turns across two asks; request carries system/user/assistant/user roles. PASS
- (e) `--session work` creates work.json; default.json absent. PASS
- (f) `sessions reset resetme` deletes the file. PASS
- (g) Non-tty output = "Hello! How can I help?\n" (23 chars). PASS
- (h) Two consecutive non-tty asks produce byte-identical output (md5 `4c91f940b4b3ee899a877e5c3a9b5b9c`). PASS
- (i) `models` lists OpenRouter model IDs (`openrouter/auto` flagged as default). PASS
- (j) `--last chat` → error "only applies to 'pos ai openrouter ask'" (rc 1). PASS
- (k) curl invocation has `Authorization: Bearer` + `HTTP-Referer: https://github.com/admin/Linux_post_install`. PASS
- (l) `bin/pos-ai-gemini` unchanged: bash -n OK, no OPENROUTER references, AI_GEMINI_API_KEY present. PASS
- (m) Duplicate doc line fixed: grep -c returns 1. PASS

## Scope compliance
- Edits confined to `bin/pos-ai-openrouter` (new), `bin/pos` (INTERACTIVE_CMDS only), `DOC/howto/ai.md`, `DOC/POS.md`, GEN outputs (via make gen).
- `bin/pos` INTERACTIVE_CMDS addition: necessary dependency for the tool to function (lint gate requires it; tee pipe hangs without it).
- Out-of-scope changes: none.

## Diff stats
- `bin/pos-ai-openrouter`: new file, 566 ln (cloned from gemini 565 ln)
- `bin/pos`: +1 word (`ai-openrouter` added to INTERACTIVE_CMDS)
- `DOC/howto/ai.md`: 155→197 ln (+42: duplicate fix −2 + OpenRouter section +42)
- `DOC/POS.md`: 500→521 ln (+21: openrouter table)
- GEN: `make gen` resynced `DOC/AGENT_Context_Project.md` (new openrouter row + line counts)

## Remaining risks / notes
- The `openrouter_generate` jq differs from the spec's provided code: first jq uses `.messages` instead of bare `.` because session_load returns `{"messages":[...]}` (full wrapper object), not a bare array. Without this fix, jq errors on "array and object cannot be added". This is a bug in the spec, not the implementation.
- Session role for model responses uses `assistant` (OpenAI convention) instead of `model` (Gemini convention). This is correct for OpenAI-compatible APIs.
- The `# POS_SUBCMDS` header was updated from the brief's `ask chat sessions` to `ask chat models sessions` because the brief also provides `cmd_models()` and verification (i) expects it.

REPORT_PATH: ./reportAgents/2026-08-25-builder-r6-openrouter.md
