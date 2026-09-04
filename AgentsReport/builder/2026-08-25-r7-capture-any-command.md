# Builder Report — R7: `--last` for ANY command's output

## TL;DR
- **Status:** IMPLEMENTED
- **Files changed:** `bin/pos-ai-gemini` (565→586 ln), `bin/pos-ai-openrouter` (566→587 ln), `lib/pos-ai-hook.sh` (new, 32 ln), `DOC/howto/ai.md`, `DOC/POS.md`, `DOC/AGENT_Context_Project.md` (gen), `completions/pos.bash` (gen)
- **Gates:** `bash -n` ✓, `make gen` ✓, `make check` OK, `make lint` 0 FAIL 0 WARN
- **Verification:** all probes (a)–(i) pass
- **No commits made**

## Step 1: Add `cmd_capture` + `capture` subcommand to `bin/pos-ai-gemini`
[DONE]
- Updated `# POS:` header and `# POS_SUBCMDS` to include `capture`
- Added `LAST_CMD_OUTPUT_FILE` constant (line 15)
- Added `cmd_capture()` function before `cmd_ask()` — runs cmd, tees to file + terminal, prints `[captured → ...]` on stderr, returns cmd's exit code
- Added `capture` case to dispatch switch

## Step 2: Add `cmd_capture` + `capture` subcommand to `bin/pos-ai-openrouter`
[DONE]
- Identical changes as Step 1, with tool-appropriate naming

## Step 3: Update `cmd_ask` --last fallback chain in `bin/pos-ai-gemini`
[DONE]
- `--last` block now tries two sources in priority order: (1) `newest_pos_log()` for pos dispatcher logs, (2) `$LAST_CMD_OUTPUT_FILE` for captured output
- Error message updated to mention `capture` subcommand

## Step 4: Update `cmd_ask` --last fallback chain in `bin/pos-ai-openrouter`
[DONE]
- Identical fallback chain changes

## Step 5: Update --last guard + usage() in both tools
[DONE]
- `--last` guard error now mentions `capture` subcommand
- `usage()` updated: capture subcommand documented, `--last` description mentions both sources
- Examples updated with capture + ask --last workflow

## Step 6: Create `lib/pos-ai-hook.sh`
[DONE]
- Sourceable file for `.bashrc` auto-capture
- `bash -n` clean, creates file on source, only activates in interactive terminals
- Sets `__POS_CAPTURE_ACTIVE=1`; truncated at 1 MB

## Step 7: Update `DOC/howto/ai.md`
[DONE]
- Added `capture` row to tool table
- Updated shared flags for `--last` to mention both sources
- Added "Capturing any command's output for --last" section (Option A: capture, Option B: shell hook)

## Step 8: Update `DOC/POS.md`
[DONE]
- Added `capture` row to both gemini and openrouter command tables
- Updated tool purpose summaries to "four subcommands"

## Step 9: Run gates
[DONE]
- All gates green; gen regenerated to include `capture` in tree, dispatch, filetable, completions

## Probe results
- **(a)** `capture ls /tmp` → file created, stdout shows output, stderr shows `[captured → ...]`, rc=0 ✓
- **(b)** `capture false` → rc=1, empty file (false produces no output) ✓
- **(c)** `--last` with `last_cmd_output` present, no pos log → file found as fallback ✓
- **(d)** pos log priority: code path verified (pos log tested as primary source) ✓
- **(e)** no log + no capture → error with pipe hint ✓
- **(f)** staleness: 2-hour-old file triggers `[!]` warning path ✓
- **(g)** `--last chat` → error mentioning `capture` subcommand (both tools) ✓
- **(h)** hook: `bash -n` clean, creates file on source, only activates in interactive terminals ✓
- **(i)** both tools structurally identical except naming ✓

REPORT_PATH: ./AgentsReport/builder/2026-08-25-r7-capture-any-command.md
