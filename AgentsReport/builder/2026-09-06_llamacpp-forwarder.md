# Builder report — 2026-09-06: llamacpp provider forwarder + shorthand

## TL;DR

- Status: IMPLEMENTED
- Objective: make `pos ai llamacpp ask ...` route to `pos ai --provider llamacpp ask ...`
  (fix "Unknown ai subcommand 'llamacpp'" for user alias `what|llamacpp|what`).
- Changes: `bin/pos-ai` gains a `llamacpp` provider-shorthand case in its subcommand
  dispatch; new executable forwarder `bin/pos-ai-llamacpp` (byte-for-byte mirror of
  `bin/pos-ai-gemini`); `ai-llamacpp` registered in `bin/pos` INTERACTIVE_CMDS;
  `make gen` regenerated docs/completions; `DOC/POS.md` ai section hand-edited.
- Verification: `bash -n` OK on all changed files; `make gen` idempotent;
  `make check` green; `make lint` ends **0 FAIL, 0 WARN**;
  smoke: `pos ai llamacpp --help` / `providers` / `ask` / bare `llamacpp` all parse
  as provider llamacpp (no "Unknown ai subcommand"; network error only when no
  local llama.cpp server is running, which is expected).
- Note: `pos ai gemini`/`openrouter` shorthands are implemented by the dispatcher's
  longest-prefix match finding the thin forwarder scripts — there is no in-file
  shorthand parse in `bin/pos-ai` to mirror; the new dispatch case mirrors the
  forwarders' behaviour instead (per approved scope item 1).

## Step 1: Read code and confirm mechanism

- Read `bin/pos-ai` (parse loop lines 648-678, provider resolve 680-687, dispatch
  `case "${cmd:-}"` 693-702 with the "Unknown ai subcommand" error at line 701).
- Read `bin/pos-ai-gemini` / `bin/pos-ai-openrouter` (thin forwarders, 7 lines).
- Read `lib/ai-providers/llamacpp.sh` — implements `provider_name`,
  `provider_default_model`, `provider_generate` (ask/chat/sessions),
  `provider_models_list` (models).
- Read `bin/pos` dispatcher + INTERACTIVE_CMDS; `scripts/lint-conventions.sh`;
  `scripts/gen-docs.sh`; `Makefile`.
- Confirmed root cause: `pos ai llamacpp ask` falls through the `bin/pos` longest-
  prefix dispatch (no `pos-ai-llamacpp`) to `bin/pos-ai`, where `llamacpp` is parsed
  as the subcommand `cmd` → `*) err "Unknown ai subcommand 'llamacpp'"`.
- No gemini/openrouter shorthand exists inside `bin/pos-ai`; the forwarders are the
  mechanism. The scope's step 1 is therefore implemented as a parallel dispatch case
  mirroring the forwarders' `exec pos ai --provider <name> "$@"` behaviour.
[DONE]

## Step 2: Add `llamacpp` provider shorthand to `bin/pos-ai`

- Added to the final `case "${cmd:-}"` dispatch (after `sessions`):

  ```bash
  llamacpp)
      # Provider shorthand (backward compat, same as the gemini/openrouter
      # forwarders): pos ai llamacpp <subcmd> ... == pos ai --provider llamacpp <subcmd> ...
      exec "$0" --provider llamacpp "${args[@]}" ;;
  ```

- No arg-parsing redesign; single parallel case, same style as sibling branches.
- Edge behavior verified: `bin/pos-ai llamacpp` (no subcommand) → re-exec with
  `--provider llamacpp` → usage, exit 0.
[DONE]

## Step 3: Create thin forwarder `bin/pos-ai-llamacpp` (100755)

- Byte-for-byte mirror of `bin/pos-ai-gemini` with provider name substituted
  (verified with `cmp` against a sed-substituted gemini file; em-dash intact).
- `# POS: ai llamacpp — Forward to pos ai --provider llamacpp (backward compat)`
- `# POS_SUBCMDS: ask chat models sessions capture` — mirrors the gemini forwarder:
  llamacpp adapter implements `provider_generate` (ask/chat/sessions/capture) and
  `provider_models_list` (models); no invented subcommands.
- Executable: mode 100755 (`chmod 755`).
[DONE]

## Step 4: Register `ai-llamacpp` in `bin/pos` INTERACTIVE_CMDS + EXAMPLES judgment

- Added `ai-llamacpp` to INTERACTIVE_CMDS (after `ai-openrouter`), matching the
  gemini/openrouter forwarders' registration — `pos ai llamacpp chat` reads stdin
  and must skip the logging `tee` pipe. Lint validates the entry against the new
  tool (`bin/pos-ai-llamacpp` exists → gate green).
- `bin/pos` usage() EXAMPLES: NO change. Existing style showcases only the default
  provider (`pos ai gemini ...`); openrouter has no example line either. Adding a
  llamacpp line would be inconsistent — judgment call per brief ("keep minimal").
[DONE]

## Step 5: `make gen` + hand-edit `DOC/POS.md`

- `make gen` regenerated `DOC/AGENT_Context_Project.md` (tree line 68, dispatch
  row 287, selfcontained line 374, filetable row 619, docmap shifts) and
  `completions/pos.bash` (`_pos_subcmds[ai-llamacpp]`, `llamacpp` appended under
  `_pos_subcmds[ai]`, filetable count). Pre-existing gen drift in the working tree
  (ai-hf/ai-server rows) preserved untouched.
- `DOC/POS.md` hand-edits (3):
  1. File line: `bin/pos-ai-gemini / bin/pos-ai-openrouter` → `... / bin/pos-ai-llamacpp`
     (backward-compat forwarders).
  2. `--provider <name>` row: `(gemini\|openrouter)` → `(gemini\|openrouter\|llamacpp)`.
  3. Backward-compat sentence: `pos ai llamacpp` added alongside `gemini`/`openrouter`.
- Provider adapters line already lists `lib/ai-providers/llamacpp.sh` — no new
  adapters-table row needed.
[DONE]

## Step 6: Verify — bash -n, make check, make lint, smoke tests

- `bash -n bin/pos bin/pos-ai bin/pos-ai-llamacpp` → OK.
- `make check` (check-sync.sh: bash -n + exec bits + gen-docs --check + dispatch
  smoke) → `check-sync: OK`.
- `./scripts/gen-docs.sh --check` → idempotent, no drift.
- `make lint` → `0 FAIL, 0 WARN (convention lint)`.
- Smoke (PATH prefixed with repo `bin/`):
  - `pos ai llamacpp --help` → usage, exit 0.
  - `pos ai llamacpp providers` → lists providers, `llamacpp ... ← active`
    (no "Unknown ai subcommand").
  - `pos ai llamacpp ask "hi"` → `ERROR: curl: (7) Failed to connect to
    127.0.0.1 port 8088` (no local server — parse path verified, provider adapter
    loaded; NOT an unknown-subcommand error).
  - `bin/pos-ai llamacpp ask "hi"` (direct, item 1 dispatch) → same provider path.
  - `pos ai llamacpp` (bare) → usage, exit 0.
  - Regression: `pos ai gemini --help`, `pos ai --help` unchanged; `pos tree`
    shows the new node.
[DONE]

## Remaining risks / follow-up (not in scope)

- `DOC/howto/ai.md` still documents only gemini/openrouter shorthands (line 29-30).
  Not in the brief's hand-edit list; left untouched — Writer/doc follow-up.
- `bin/pos-ai` usage() text lines 42/59 still say `(gemini, openrouter)` /
  `(gemini|openrouter; default: gemini)` and `DOC/POS.md` AI_PROVIDER config row
  still says `(gemini\|openrouter)` — pre-existing staleness predating this change
  (llamacpp provider already existed). Out of approved scope; doc follow-up.
- `pos ai llamacpp` with a real server was not exercised (no local llama.cpp
  server/config in this environment) — addressed by the parse-path verification.

## Handoff

Status: IMPLEMENTED
Approved scope: provider shorthand in bin/pos-ai + bin/pos-ai-llamacpp forwarder +
  make gen + DOC/POS.md hand-edits + targeted verification. Nothing else touched.
Files changed:
- bin/pos-ai (dispatch case)
- bin/pos-ai-llamacpp (new, 100755)
- bin/pos (INTERACTIVE_CMDS)
- DOC/POS.md (3 hand-edits)
- DOC/AGENT_Context_Project.md, completions/pos.bash (make gen)
- AgentsReport/builder/2026-09-06_llamacpp-forwarder.md (this report)
Verification: bash -n OK; make gen idempotent; make check green; make lint
  0 FAIL, 0 WARN; smoke tests pass (parse path verified, no server available).
Scope compliance: in-scope changes only; out-of-scope changes: none
  (README.md, AGENT_TODO.md, lib/ai-providers/*.sh, pos-ai-hf, pos-ai-server untouched).
Recommended next agent: Reviewer
Reason: implementation complete and independently verifiable; adversarial review
  of the dispatch case + forwarder + doc/tree sync before acceptance.