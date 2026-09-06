# Maintainer Report — 2026-09-06 — POS CLI convention sweep (AI tools)

## TL;DR

- Objective: comprehensive convention/maintenance sweep over the POS CLI AI tooling
  after several AI-tool changes (`bin/pos-ai-llamacpp` forwarder, enhanced
  `bin/pos-ai-hf`, enhanced `bin/pos-ai-server`, `bin/pos-ai` shorthand,
  `bin/pos` INTERACTIVE_CMDS) + llamacpp doc drift. Restore the established
  standard; do not redesign.
- Verified-clean (no changes needed): `bin/pos-ai-llamacpp` (shebang, strict-mode,
  `# POS:` style, `# POS_SUBCMDS:` = actual adapter support, mode 100755,
  `-h|--help`, exec body — byte-mirror of gemini), `bin/pos-ai-hf` (all headers vs
  implementation, 11 unique examples, no dupes), `bin/pos-ai-server` (all headers
  vs implementation; config keys already registered in the `ai` scope via
  `bin/pos-ai` POS_CONFIG, commit adf88cc), `bin/pos` (INTERACTIVE_CMDS entry
  format + lint expectation; usage EXAMPLES has no factual provider list).
- Corrected 7 factual provider-list omissions (llamacpp is a real provider:
  `lib/ai-providers/llamacpp.sh` + wired in `bin/pos-ai` resolve/require/model
  paths): `bin/pos-ai` usage() ×2, `DOC/POS.md` AI_PROVIDER config row,
  `DOC/howto/ai.md` ×4 (adapter list, `--provider` backend list, backward-compat
  shorthand, "Available providers" table row).
- Ledger: 1 dated Done entry added to `AGENT_TODO.md`.
- Validation: `bash -n` all `bin/pos*` OK; `make gen` idempotent (byte-identical
  before/after — no header changes); `make check` → `check-sync: OK`;
  `make lint` → **0 FAIL, 0 WARN (convention lint)**; smoke:
  `pos-ai --help` shows llamacpp lists, `pos-ai llamacpp --help`/`providers`
  dispatch correctly to provider llamacpp.
- No commit (per brief — Orchestrator integrates).

## Step 1: `bin/pos-ai-llamacpp` (new forwarder) — verify only

Evidence (`bin/pos-ai-llamacpp:1-7`):
- `#!/usr/bin/env bash` + `set -euo pipefail` (lines 1-2) ✓
- `# POS: ai llamacpp — Forward to pos ai --provider llamacpp (backward compat)`
  (line 3) — same style as `bin/pos-ai-gemini:3` / `bin/pos-ai-openrouter:3` ✓
- `# POS_SUBCMDS: ask chat models sessions capture` (line 4) — mirrors gemini;
  verified against `lib/ai-providers/llamacpp.sh`: it implements
  `provider_generate` (drives `cmd_ask`/`cmd_chat`/`cmd_sessions`/`cmd_capture`
  in `bin/pos-ai`) and `provider_models_list` (drives `cmd_models`) — so all 5
  listed subcommands are supported by the adapter. No invented subcommands ✓
- mode `755` (100755) via `stat` ✓
- `-h|--help` case (line 6) present, same as gemini; no deps guards to order
  against ✓
- exec forward body `exec pos ai --provider llamacpp "$@"` (line 7) ✓
- Lint gate cross-check (`scripts/lint-conventions.sh`): shebang/strict-mode for
  all shell files; exec-bit for `bin/pos-*`; `# POS:` + em-dash; `-h|--help`
  regex; `uses_stdin` → forwarded tool reads stdin via `pos ai chat`, so
  `ai-llamacpp` must be in INTERACTIVE_CMDS (it is, see Step 5) — and the reverse
  lint rule (`INTERACTIVE_CMDS` entry needs matching executable `bin/pos-ai-llamacpp`)
  is satisfied.

No changes. Status: [DONE]

## Step 2: `bin/pos-ai-hf` (enhanced) — verify only

Evidence vs implementation:
- `# POS: ai hf — …` (`bin/pos-ai-hf:3`) ✓
- `# POS_FLAGS: --branch --gguf --list --output --quant --include --exclude --revision`
  (line 4) — every flag is parsed in the arg loop (lines 122-145: `--branch`,
  `--gguf`, `--list`, `--quant`, `--output`, `--include`, `--exclude`,
  `--revision`); no stale/duplicated flags ✓
- `# POS_DEPS: curl jq` (line 5) — both `command -v` guards sit before `--help`
  (lines 18-19) ✓
- `# POS_CONFIG: ai | ai.env | HF_TOKEN=secret:… | HF_DOWNLOAD_DIR=:…` (line 6) —
  script reads `HF_TOKEN` (lines 27, 167-168, 183-184) and `HF_DOWNLOAD_DIR`
  (lines 28, 164) ✓
- `# POS_EXAMPLES:` — 11 unique lines (7-17), no duplicate lines; every example
  maps to an implemented subcommand (search / download variants / list / remove /
  info / files) ✓
- usage() (lines 48-97) lists subcommands `search download list remove info files
  cache` — dispatch (lines 813-823) implements exactly those (`cmd_search`,
  `cmd_download`, `cmd_list`, `cmd_remove`, `cmd_info`, `cmd_files`, `cmd_cache`);
  all 8 flags documented in usage match the parse loop ✓

No changes (the 3 duplicate examples were already removed by the previous
maintainer pass `2026-09-06_restore-cleanup.md`). Status: [DONE]

## Step 3: `bin/pos-ai-server` (enhanced) — verify only

Evidence vs implementation (full read of `bin/pos-ai-server`):
- `# POS: ai server — llama.cpp local inference server (start, stop, status, models, logs)` (line 3) ✓
- `# POS_SUBCMDS: start stop status models logs` (line 4) — dispatch (lines 605-613:
  `start`, `stop`, `status`, `models`, `logs`) matches exactly ✓
- `# POS_FLAGS:` (line 5) — all 23 listed flags are parsed in the arg loop
  (lines 262-340: `--port --host --model --ctx --gpu --threads --gpu-layers
  --gpu-threads --tensor-split --n-gpu-layers --batch-size --ubatch-size
  --temperature --top-k --top-p --repetition-penalty --mmap --mlock --kv-cache
  --ctx-size --metrics --health --slots`); no extra/missing flags ✓
- `# POS_DEPS: curl jq` (line 6) — both guarded before `--help` (lines 11-12) ✓
- usage() (lines 174-233): commands, all flags, and the `LLAMACPP_*` config-key
  block (lines 222-228) match the implementation (reads `LLAMACPP_PORT/HOST/MODEL/
  CTX_SIZE/GPU_LAYERS/THREADS` from `~/.config/linux_post_install/ai.env`) ✓
- POS_CONFIG: the tool itself has no `# POS_CONFIG:` header, but the `LLAMACPP_*`
  keys it reads are ALREADY registered in the `ai` scope by `bin/pos-ai:6`
  POS_CONFIG (committed `adf88cc fix: pos config ai splits llamacpp into its own
  section`), same env file. Adding a header here would duplicate the registration
  and is a feature add, not drift restoration → left untouched per "smallest safe
  change" + Do-not-redesign.

No changes. Status: [DONE]

## Step 4: `bin/pos-ai` (modified) — shorthand case OK; 2 stale usage() lines fixed

- New `llamacpp` dispatch case (`bin/pos-ai:701-704`):
  `llamacpp) exec "$0" --provider llamacpp "${args[@]}" ;;` — matches the
  gemini/openrouter forwarder semantics (`pos ai llamacpp <subcmd> … == pos ai
  --provider llamacpp <subcmd> …`); sits with the other parallel cases in the
  final `case "${cmd:-}"` dispatch, `*)` error still last. Verified behavior:
  `bin/pos-ai llamacpp --help` and `llamacpp providers` both resolve to provider
  llamacpp (`llamacpp configured (model: … ) ← active`).
- STALE usage() provider lists — FACTUALLY WRONG about supported providers
  (llamacpp is wired: `lib/ai-providers/llamacpp.sh` exists; `bin/pos-ai`
  `resolve_key`/`require_key`/`resolve_model` handle `llamacpp` cases; POS_CONFIG
  line 6 already lists "gemini, openrouter or llamacpp"; POS.md row 72 lists
  llamacpp):
  - `bin/pos-ai:42` `AI assistant with pluggable providers (gemini, openrouter).`
    → `AI assistant with pluggable providers (gemini, openrouter, llamacpp).`
  - `bin/pos-ai:59` `--provider <name> Provider to use (gemini|openrouter; default: gemini).`
    → `--provider <name> Provider to use (gemini|openrouter|llamacpp; default: gemini).`
  - Line 81 (`AI_PROVIDER … (gemini|openrouter|llamacpp, default gemini)`) was
    already correct — untouched.
- Headers: `# POS_SUBCMDS: ask chat sessions capture models providers` (line 4)
  vs dispatch (ask/capture/chat/models/providers/sessions) — same 6, complete ✓;
  `# POS_FLAGS: --provider --model --session --system --full --last --trust`
  (line 5) — all 7 parsed in the arg loop (lines 655-680) ✓; POS_CONFIG (line 6)
  includes llamacpp + `LLAMACPP_*` keys ✓.

Status: [DONE]

## Step 5: `bin/pos` (modified) — INTERACTIVE_CMDS verified; EXAMPLES verdict

- `ai-llamacpp` added to INTERACTIVE_CMDS (`bin/pos:269`) after `ai-openrouter`,
  byte-consistent with `ai-gemini`/`ai-openrouter` (space-separated in the same
  string). Lint gate (`scripts/lint-conventions.sh:174-180`) requires each entry
  to have a matching executable `bin/pos-$entry` — `bin/pos-ai-llamacpp` exists
  (100755) → the entry is required AND correct. The stdin rule
  (lint lines 162-167) is satisfied via the INTERACTIVE_CMDS registration
  (`pos ai llamacpp chat` reads stdin → must skip the logging tee pipe).
- usage() EXAMPLES block (`bin/pos:201-204`): showcases `pos ai gemini …`, shows
  no factual provider list → no change (matches the Builder's judgment; adding a
  llamacpp line would be inconsistent with openrouter having none).

No changes. Status: [DONE]

## Step 6: `DOC/POS.md` — AI_PROVIDER row fixed; Builder's 3 edits verified

- Builder's 3 hand-edits verified consistent end-to-end:
  - line 58 file list now includes `bin/pos-ai-llamacpp` ✓
  - line 72 `--provider <name>` row `(gemini\|openrouter\|llamacpp)` ✓
  - line 82 backward-compat sentence includes `pos ai llamacpp` ✓
  - line 59 adapters list already includes `lib/ai-providers/llamacpp.sh` ✓
- Remaining staleness fixed: line 90 config table
  `| AI_PROVIDER | no | gemini | Active provider (gemini\|openrouter) |`
  → `Active provider (gemini\|openrouter\|llamacpp)` — llamacpp is a real provider
  adapter, and the row lists provider values for the other two, so llamacpp must
  be mentioned (brief's explicit criterion).
- Also verified no duplicate/stale `pos ai hf` / `pos ai server` rows elsewhere
  in the section.

Status: [DONE]

## Step 7: `DOC/howto/ai.md` — 4 provider-list fixes (brief lines 29-30 + same root cause)

Same root cause as Step 6 (provider/shorthand lists omit llamacpp); fixed all
instances minimally, facts from `lib/ai-providers/llamacpp.sh`:
1. line 5 `pluggable provider adapters (gemini, openrouter)` →
   `(gemini, openrouter, llamacpp)`.
2. lines 19-20 `--provider <name>` backend list `(gemini|openrouter;` →
   `(gemini|openrouter|llamacpp;` (wrap preserved).
3. lines 29-30 backward-compat shorthand sentence (brief's named instance):
   `pos ai gemini` / `pos ai openrouter` → adds `pos ai llamacpp` as shorthand
   for `pos ai --provider llamacpp`.
4. "Available providers" table (lines 134-137) gains a row:
   `| llamacpp | Local llama.cpp (OpenAI-compatible) | loaded on the running server | LLAMACPP_MODEL |`
   — facts verified: OpenAI-compatible `/v1/chat/completions` (llamacpp.sh:3,31),
   `provider_default_model()` reads the loaded model from the running server via
   `/v1/models` (llamacpp.sh:11-16), config key `LLAMACPP_MODEL`
   (llamacpp.sh:7 `PROVIDER_CONFIG:`).

Terse-but-correct statements left alone (e.g. line 3 "Gemini, OpenRouter, and
more", line 10 openrouter-only example rows — the doc's example style, not
factual provider enumerations).

Status: [DONE]

## Step 8: `bin/pos` usage() EXAMPLES — no factual provider list → no change

Verified `bin/pos:201-204`: the ai EXAMPLES show `pos ai gemini …` as a usage
showcase only (openrouter has no line either) — no provider enumeration to
update. Per brief, no change. Status: [DONE]

## Step 9: Global gates (`bash -n` / `make gen` / `make check` / `make lint`)

- `bash -n` across every `bin/pos*` file → all OK.
- `make gen` → `gen-docs: write OK`; second run byte-identical (md5sums of
  `DOC/AGENT_Context_Project.md` + `completions/pos.bash` match the pre-edit
  baseline) → idempotent, no gen drift introduced (no `# POS_*` headers changed).
- `make check` → `check-sync: OK`.
- `make lint` → `0 FAIL, 0 WARN (convention lint)`.
- Smoke: `bin/pos-ai --help` prints the corrected provider lists;
  `bin/pos-ai llamacpp --help` → usage exit 0; `bin/pos-ai llamacpp providers` →
  `llamacpp … ← active` (no "Unknown ai subcommand").

Status: [DONE]

## Step 10: `AGENT_TODO.md` ledger

- Added one dated Done one-liner (2026-09-06, convention sweep — llamacpp
  doc/usage sync) at the top of `## Done`, established style (newest batch at
  top; single entry this pass). Existing entries untouched.

Status: [DONE]

## Remaining drift found but NOT fixed (with reason)

- `DOC/POS.md:124` `pos ai server` "Flags:" line enumerates only 7 of the 23
  implemented flags (omits the 16 advanced flags from commit 0856b25); same for
  `DOC/POS.md:108` `pos ai hf` "Options:" line (omits `--include`/`--exclude`/
  `--revision`). This is the established terse-summary style of POS.md flag rows
  (both sections predate the enhanced work), the statements are correct as far as
  they go, and the sweep brief names only llamacpp-caused drift for docs — the
  tool usage() help documents all flags. Reason: out of named scope; fixing would
  require a doc-completeness decision (Architect/Writer), not drift restoration.
- `bin/pos-ai-server` has no `# POS_CONFIG:` header. NOT a gap: the `LLAMACPP_*`
  keys it reads are already registered in the `ai` scope via `bin/pos-ai:6`
  POS_CONFIG (commit adf88cc), same env file `ai.env` — `pos config ai` already
  edits them. Adding a header would be a duplicate registration / feature add.
- Untracked plan documents in the working tree (`AUDIT.md`, `AUDIT_TABLE.md`,
  `FINAL_SUMMARY.md`, `IMPLEMENTATION_PLAN.md`) and untracked
  `AgentsReport/maintainer/2026-09-06_restore-cleanup.md` +
  `AgentsReport/builder/*.md` reports — noted in Step 1 of the previous
  maintainer pass; Orchestrator decision (commit/delete), not this brief.

## Completion handoff

Status: MAINTENANCE_COMPLETE

Maintenance objective:
- Convention sweep over the POS AI CLI tooling after the AI-tool changes;
  verify/fix conventions only, restore the established standard, do not redesign.

Findings addressed:
- 7 factual provider-list omissions fixed (llamacpp omitted): `bin/pos-ai`
  usage() ×2, `DOC/POS.md` AI_PROVIDER row ×1, `DOC/howto/ai.md` ×4.
- Verified clean (no changes): `bin/pos-ai-llamacpp`, `bin/pos-ai-hf`,
  `bin/pos-ai-server`, `bin/pos` INTERACTIVE_CMDS + EXAMPLES, all `# POS_*`
  headers vs implementations.

Standard enforced:
- `templates/pos-tool.sh` convention + AGENTS.md header rules; provider list
  claims in docs/help must match the real adapters
  (`lib/ai-providers/{gemini,openrouter,llamacpp}.sh`); generated blocks only via
  `make gen`; `pos config` scope registry via `# POS_CONFIG:`.

Files changed (this pass):
- `bin/pos-ai` (+2 lines: usage() provider lists)
- `DOC/POS.md` (+1 row edit: AI_PROVIDER)
- `DOC/howto/ai.md` (4 edits: adapter list, backend list, backward-compat, table row)
- `AGENT_TODO.md` (+1 Done entry)
- `AgentsReport/maintainer/2026-09-06_convention-sweep.md` (this report)

Verification performed:
- `bash -n` all `bin/pos*` OK; `make gen` idempotent (byte-identical);
  `make check` → `check-sync: OK`; `make lint` → 0 FAIL, 0 WARN;
  smoke: llamacpp shorthand/usage paths live.

Records updated:
- `AGENT_TODO.md` Done ledger (1 dated entry); this report.

Scope compliance:
- In-scope corrections only; no behavior changes; no redesign; no commit.
- Out-of-scope changes: none. `README.md`, `lib/ai-providers/*.sh`, `bin/pos`,
  `bin/pos-ai-hf`, `bin/pos-ai-server`, `bin/pos-ai-llamacpp` untouched by me
  (working-tree changes from Builder preserved).

Remaining / deferred items:
- POS.md flag rows are terse partial enumerations (established style; tool
  usage() is complete) — noted, out of named scope.
- Untracked plan docs + agent reports awaiting Orchestrator decision.

Recommended next agent:
- Orchestrator

Reason:
- All sweep items verified, gates green, docs synchronized; per the brief no
  commit was made — Orchestrator integrates and commits.

Changes made by Maintainer:
- 7 minimal factual provider-list corrections (usage + docs) and 1 ledger entry.