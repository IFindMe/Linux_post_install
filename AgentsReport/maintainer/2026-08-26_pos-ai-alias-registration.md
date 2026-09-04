# Maintainer Report — 2026-08-26 — pos-ai-alias registration

## TL;DR

- Drift: `bin/pos-ai-alias` reads stdin interactively but was missing from `INTERACTIVE_CMDS` in `bin/pos` (lint FAIL), and was undocumented in `DOC/POS.md` (lint WARN).
- Correction 1: added token `ai-alias` to `INTERACTIVE_CMDS`, after `ai-openrouter`. Nothing else on the line changed.
- Correction 2: documented `pos ai alias …` in the `### ai` section of `DOC/POS.md` (6 table rows + storage/regen paragraph), grounded in `bin/pos-ai-alias` source.
- Validation: `bash -n` OK → `make gen` zero drift → `make check` OK → **`make lint`: 0 FAIL, 0 WARN**.
- Scope compliance: only `bin/pos` + `DOC/POS.md` touched; pre-existing unrelated working-tree modifications left untouched and attributed below.
- No commit made (per brief).

## Step 1: Register `ai-alias` as interactive command

- Finding: lint gate `FAIL bin/pos-ai-alias: reads stdin but NOT in INTERACTIVE_CMDS in bin/pos`.
- Evidence: `bin/pos-ai-alias` uses `menu_pick`/`menu_ask_value`/`confirm` in `_alias_menu`/`_alias_create`/`_alias_edit`/`_alias_remove`; registry at `bin/pos:262`.
- Smallest fix: single-line replacement of line 262 inserting `ai-alias` between `ai-openrouter` and `system-schedule` (keeps the loose `ai*` grouping). Key format matches existing entries (`ai-gemini` ⇒ filename after `pos-`).

Status: [DONE]

## Step 2: Document `pos ai alias` in DOC/POS.md ai section

- Finding: lint gate `WARN bin/pos-ai-alias: file not referenced in DOC/POS.md` (lint greps basename at `scripts/lint-conventions.sh:169`).
- Fix: extended the existing Command/Behavior table in `### ai` (rows appended after the last current row) plus one prose paragraph immediately after the table, before "Backward compatibility:". All claims verified against source:
  - no args → interactive menu loop, alias table shown between picks (`_alias_menu`)
  - create: 4-step wizard — name validation `^[a-zA-Z][a-zA-Z0-9_-]*$` + uniqueness, provider pick from `lib/ai-providers/*.sh`, session defaulting to alias name, optional system prompt (`|` forbidden, >500 chars warns), confirm default yes (`_alias_create`)
  - edit: pre-filled prompts, Enter keeps current, per-field changed/unchanged tags, confirm default yes, no-write when unchanged (`_alias_edit`)
  - remove: confirm default **no**, cannot be undone (`_alias_remove:467`)
  - list: non-interactive Name/Provider/Session/Prompt table, prompt truncation at 42 chars (`_alias_list`, `_alias_prompt_truncate`)
  - show `<name>`: details incl. resolved command `pos ai <provider> ask --session <session>[ --system '<prompt>']` (`_alias_show`)
  - paragraph: `ai-aliases.env` format `name|provider|session|system_prompt`, chmod 600; every write regenerates `ai-aliases.sh` chmod 644 with `alias <name>='pos ai …'`, empty session falls back to name, prompts quote-escaped, file syntax-checked before replace (`_alias_save`/`_alias_regen`); user sources it via shell rc (no repo code auto-sources it yet)
- Density/style matched neighboring rows (single-line dense cells, `\|` escaping consistent with existing `(gemini\|openrouter)` row). Literal `bin/pos-ai-alias` string included, satisfying the coverage grep.
- Purpose/File header lines of the section were NOT touched (they describe `bin/pos-ai`, not the alias tool) — scope fence.

Status: [DONE]

## Step 3: Verify gates

| Gate | Result |
|------|--------|
| `bash -n bin/pos` | OK |
| `make gen` | `gen-docs: write OK`; md5sums of `completions/pos.bash` + all `DOC/*.md` byte-identical before vs after → zero gen drift introduced |
| `git diff --exit-code -- completions/pos.bash DOC/` | exit 1 — **pre-existing** uncommitted mods from other agents (`DOC/AGENT_Context_Project.md` 2 lines, `DOC/DEV.md` 6 lines); attribution: checksums prove gen didn't alter them, I never edited them |
| `make check` | `check-sync: OK` |
| `make lint` | **0 FAIL, 0 WARN (convention lint)** — both target gates cleared |

Diff attribution (working tree vs HEAD):
- `completions/pos.bash`: identical to HEAD (not in diff stat).
- `DOC/POS.md`: exactly my 8 added lines in the ai section, nothing else.
- `bin/pos`: exactly 1 insertion / 1 deletion (the INTERACTIVE_CMDS line).
- `DOC/AGENT_Context_Project.md`, `DOC/DEV.md`: pre-existing other-agent modifications — out of my scope, untouched by me.

Status: [DONE]

## Deferred / notes

- `postinstall.sh` does not yet append a `.bashrc` source line for `ai-aliases.sh` (the tool only logs "Reload shell: source ~/.bashrc"); the architect report lists this as future work — out of maintenance scope here, noted only.
- `AGENT_TODO.md` Done-entry bookkeeping is tied to committing, which this brief forbids — left for whoever commits these changes.
