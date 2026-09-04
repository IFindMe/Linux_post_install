# Builder Report — R11: AI command execution prompt

## TL;DR
- **Status:** IMPLEMENTED
- **Files changed:** `bin/pos-ai` (+48 lines), `DOC/AGENT_Context_Project.md` (gen'd line-count update)
- **What:** After AI responds with fenced code blocks containing shell commands, prompt the user to run them interactively
- **Gates:** `make gen` OK, `make check` OK, `make lint` 0 FAIL / 0 WARN
- **Test outcome:** `bash -n` syntax OK; diff verified clean

---

## Step 1: Add `_extract_commands()` and `_prompt_run_command()` functions

[DONE]

Inserted two new functions after `render_markdown()` (before `mc_clean()`):
- `_extract_commands()` — awk parser extracting commands from ```bash/sh/shell fenced blocks; skips empty lines (`NF > 0`); preserves multi-line commands with newlines
- `_prompt_run_command()` — interactive prompt using `/dev/tty` I/O; errors/status to stderr; `run eval` respects `$DRY_RUN`; `history -s` adds declined commands to shell history for recall; case-insensitive y/n matching

## Step 2: Integrate into `cmd_ask()`

[DONE]

After `render_markdown "$out"` (line 513), added 4-line block extracting commands and offering to run them.

## Step 3: Integrate into `cmd_chat()`

[DONE]

After `render_markdown "$answer"` (line 551), added same extraction + prompt block.

## Step 4: Verify

[DONE]

- `bash -n bin/pos-ai` — syntax OK
- `make gen && make check && make lint` — all green (0 FAIL, 0 WARN)
- Diff verified: only `bin/pos-ai` (new functions + integrations) + auto-generated line-count update in `DOC/AGENT_Context_Project.md`

---

REPORT_PATH: ./reportAgents/2026-08-25-builder-r11-ai-command-prompt.md
