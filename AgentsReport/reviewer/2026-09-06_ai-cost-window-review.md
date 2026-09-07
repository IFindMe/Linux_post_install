# Reviewer Report — AI cost & session-window change review

**Date:** 2026-09-06
**Reviewer:** big-pickle (read-only, adversarial)
**HEAD reviewed:** 8ce5479 (working tree has uncommitted Builder changes)
**Design contract:** `AgentsReport/architect/2026-09-06_ai-cost-window-design.md`
**Builder handoff:** `AgentsReport/builder/2026-09-06_ai-cost-window.md`

## TL;DR

- **Status: CHANGES_REQUIRED** — 1 REQUIRED finding (token-cap input guard), 1 NOTE.
- **Scope:** diff is exactly the 6 approved files (+2 journal reports); no llamacpp.sh / pos-ai-server / aliases / tests / AGENT_TODO edits. Verified.
- **Core fix verified statically:** openrouter + gemini now send a hard `max_tokens` cap (default 2048 on unset/empty); `session_push` resolves `AI_SESSION_TURNS` lazily with a numeric guard; help text and all three docs are truthful and consistent; registry/header format is key-driven so both new keys are discoverable in scope `ai`.
- **Defect:** `AI_MAX_TOKENS=0` / `-5` / `010` are *accepted by `pos config ai`* (`num:` validation regex is `^-?[0-9]+$`) and reach jq with no guard → provider 400s (0/-5) or a raw jq abort (leading zeros, non-numeric via hand-edit). The sibling `AI_SESSION_TURNS` var is guarded; `AI_MAX_TOKENS` is not, and the session guard itself still misses leading-zero values.
- **UNVERIFIED (sandbox denies execution):** `make gen` idempotence, `make check`, `make lint`, `make test` (Builder claims gen x3 no-op, check OK, lint 0 FAIL/0 WARN, 17 files/299 checks green), live `reg_config_keys ai` / `pos config ai` rendering, and the 402 live repro. Static evidence is consistent with all of these; the Orchestrator should run the gates before merge.

---

## Step 1: Diff scope — [PASS]

`git diff HEAD --stat` shows exactly:

- `bin/pos-ai` (+10/−6 net +4 — header line 6, help lines 94-95, `session_push` 288-293)
- `lib/ai-providers/openrouter.sh` (+2/−2, body 22-23)
- `lib/ai-providers/gemini.sh` (+3/−2, body 17-20)
- `DOC/POS.md`, `DOC/HOWTO.md`, `DOC/AGENT_Context_Project.md`

`git status --porcelain` = 6 modified files + 2 untracked journal reports only. **No** llamacpp.sh (`lib/ai-providers/llamacpp.sh:32-33` verified unchanged), no pos-ai-server, no alias wrappers, no tests, no AGENT_TODO, no `completions/pos.bash`. Matches design §Decision 5 file list exactly. `git diff --check` clean.

## Step 2: max_tokens correctness — [PASS] with edge finding

- Default applied: `--arg mt "${AI_MAX_TOKENS:-2048}"` → unset **or empty-exported** env → jq gets `"2048"` → `tonumber` → 2048. Applies in both providers. Var name matches the `# POS_CONFIG:` declaration (`AI_MAX_TOKENS`, bin/pos-ai:6); `cfg_write` writes the header key verbatim, so `pos config ai` writes `AI_MAX_TOKENS`/`AI_SESSION_TURNS` into ai.env; `load_env_file` (config-ui.sh:336-357) exports with env-wins. Providers read the same names.
- Ordering safe: `session_push`/`provider_generate` are only reached after `require_key` → `resolve_key` → `load_config` (cmd_ask:503→524-529, cmd_chat:542→560-565), so ai.env values are loaded before lazy reads.
- **Findings 1 & 2** below cover `AI_MAX_TOKENS=0`/`-5`/`010`/`abc` (no guard; jq `tonumber` semantics) and `AI_SESSION_TURNS=010` slipping through the guard.

## Step 3: session window correctness — [PASS] (with NOTE)

- `session_push` (pos-ai:288-293): `local n="${AI_SESSION_TURNS:-$MAX_SESSION_TURNS}"`; guard `^[0-9]+$` + `(( n >= 1 ))` else 40; jq `--argjson n` + `.messages |= .[-$n:]` (no string interpolation into the filter — improvement over the old `'"$MAX_SESSION_TURNS"'` splice).
- n=10 → append user+assistant then keep exactly last 10 messages = 5 exchanges. ✓ matches user goal.
- Very large arrays / n > length → jq slice clamps to whole array, no error. ✓
- `SESSION` is always `default`/`--session` value (pos-ai:23, 658-660); `session_push` does not depend on SESSION at all and `session_load`/`session_save` early-return on empty SESSION (252-253, 277). No unsafe path.
- Help text: pos-ai:67 renders "capped at 40 turns" (default 40 — truthful); the new Config: lines (94-95) document both vars with the "10 = last 5" semantics. DOC/POS.md:64 adds "(configurable via `AI_SESSION_TURNS`)". Truthful.
- NOTE: `AI_SESSION_TURNS=010` passes the guard (regex matches; bash octal eval 8 ≥ 1) but `--argjson n "010"` is an invalid JSON numeric literal → jq abort under `set -e`. Pathological but config-ui-enterable. Covered by the same fix as Findings 1/2.

## Step 4: Config surface — [PASS: static] / [UNVERIFIED: runtime]

- Registry (`lib/registry.sh`) is format-driven: `reg_config_keys <scope>` echoes the whole `# POS_CONFIG:` line(s) per scope; the `ai` scope line (pos-ai:6) now contains `AI_MAX_TOKENS=num:…` and `AI_SESSION_TURNS=num:…` inside `@General`, exactly matching the proven `LLAMACPP_CTX_SIZE=num:…` pattern. config-ui renders `@`-captioned sections.
- Static conclusion: both keys ARE discoverable under scope `ai` in `@General`. Runtime `reg_config_keys ai` / `pos config ai` display could not be executed (sandbox denies `source`/bash) → **UNVERIFIED**; Orchestrator/next agent can re-run.
- Note: `bin/pos-ai-hf` also declares scope `ai` (pre-existing); both lines merge under `ai` — unchanged behavior.

## Step 5: Doc sync — [PASS]

- `DOC/POS.md:94-95` new rows: `AI_MAX_TOKENS` no/`2048`/"Max output tokens per request (OpenRouter/Gemini cost cap)"; `AI_SESSION_TURNS` no/`40`/"Session message cap — 2 per exchange; 10 = last 5 exchanges" — consistent with header + code (2048 default; 40 messages = 20 exchanges; 10 = 5 exchanges). `:64` parenthetical true (default unchanged).
- `DOC/HOWTO.md:45` and `DOC/AGENT_Context_Project.md:491` append both vars. ✓
- GEN blocks: only the filetable row `bin/pos-ai 705→709` changed (inside `GEN:START filetable`/`GEN:END`, AGENT_Context 614-662); `wc -l bin/pos-ai` = 709 → the generated row is byte-consistent with the file, so a `make gen` rerun would be a no-op for that row. Other GEN blocks and `completions/pos.bash` untouched (no key-level completion table exists — config is read live from headers). Hand-maintained Key-File rows (AGENT_Context:593-613) do not include `lib/ai-providers/*`, so "no bump needed" is correct.

## Step 6: Gates — [UNVERIFIED]

Sandbox permission rules deny `make`, `bash`, `source`, `jq`, `mkdir` (allowlist: git read commands, head/tail/wc/sort/grep/rg only). Builder claims: `make gen` idempotent x3, `make check` OK, `make lint` 0 FAIL 0 WARN, `make test` 17 files/299 checks green, `bash -n` clean, `git diff --check` clean (the last confirmed independently). **Orchestrator must run `make gen && git diff --exit-code`, `make check`, `make lint`, `make test` before merge** to confirm; static review found no gen-drift predicate (no new commands/flags; header text doesn't feed the generated tables).

## Step 7: Behavioral sanity (user's 402 goal) — [PASS with caveats]

- Pre-fix: no `max_tokens` → OpenRouter pre-check bills worst-case 131072 output tokens → 402 at balance-4511. Post-fix the request body carries `max_tokens: 2048`, so the pre-check estimate ≈ input_tokens + 2048 (output) instead of + 131072. With the terse `ask` prompt (~200 input tokens) the estimate is far under the ~4511-token affordance → 402 resolved for typical requests. Math is plausible.
- Caveats for the user (also in Findings → caveats below): (1) if the auto-routed model's *output* price per token is steep, 2048 output tokens can still exceed the balance → 402 persists; set an explicit cheaper `OPENROUTER_MODEL` or switch `AI_PROVIDER=gemini`/`llamacpp`. (2) `max_tokens:2048` truncates long `--full` answers (raise the var). (3) Live OpenRouter/Gemini repro was not run (no network, no key) → UNVERIFIED.

---

## Findings

**Finding 1 — REQUIRED**
- **Evidence:** `lib/ai-providers/openrouter.sh:22-23` and `lib/ai-providers/gemini.sh:17-19` pass `${AI_MAX_TOKENS:-2048}` straight into jq `($mt|tonumber)` with no range/format guard. `lib/config-ui.sh:419` `num:` validation accepts `^-?[0-9]+$` — so `AI_MAX_TOKENS=0`, `-5`, `010` are all savable via `pos config ai`. Consequences: `0`/`-5` → provider 400 on every request (OpenRouter `max_tokens` must be ≥ 1; Gemini `maxOutputTokens` ≥ 1); `010` → jq invalid numeric literal → command substitution fails → `set -euo pipefail` (pos-ai:2) aborts the whole CLI with a raw jq error; same raw abort for a non-numeric value hand-set/exported (e.g. `AI_MAX_TOKENS=abc`). The sibling `AI_SESSION_TURNS` got an explicit guard (pos-ai:290-291) — the asymmetry shows the guard pattern was intended but not applied to the token cap, and the session guard itself misses leading-zero values (see Finding 2).
- **Relevant files/lines:** openrouter.sh:22-23; gemini.sh:17-19; config-ui.sh:419; bin/pos-ai:290-291.
- **Approved scope reference:** design §Decision 1 (providers read `${AI_MAX_TOKENS:-2048}`), §Decision 5 ("empty/unset values fall back to documented defaults" — satisfied, but 0/negative/leading-zero are neither empty nor unset).
- **Why it matters:** a value the project's own config UI accepts (0 — a plausible "no cap" attempt, valid on some OpenAI-compatible backends) hard-breaks both remote providers until manually cleared; the new var is the 402 fix, so its input path should fail closed to the safe default, matching the guarded sibling var.
- **Fix demand (Builder, in scope):** in both providers, before jq: `mt="${AI_MAX_TOKENS:-2048}"; [[ "$mt" =~ ^[1-9][0-9]*$ ]] || mt=2048` (also rejects 0, negatives, leading zeros, empty, non-numeric) then `--arg mt "$mt"`. 2-3 lines each.

**Finding 2 — NOTE (folded into Finding 1's fix)**
- **Evidence:** `bin/pos-ai:290-291` guard is `^[0-9]+$` + `(( n >= 1 ))`; `AI_SESSION_TURNS=010` passes both (octal 8) then `--argjson n "010"` is an invalid JSON numeric literal → jq abort. Pathological, but config-ui-enterable. Fix: switch the session guard to the same `^[1-9][0-9]*$` pattern.

**Finding 3 — NOTE (unverified runtime claims)**
- Gates/suite/live-402 claims from the Builder report could not be re-run under the sandbox (deny rules). The Orchestrator must run `make gen`/`make check`/`make lint`/`make test` and, if desired, a live OpenRouter repro before merge. Static evidence is consistent with the claims (row 709 == `wc -l`; header change adds no commands → gen tables unaffected).

---

## Verification verified (by evidence)

- Diff scope exact (6 approved files; `git status`/`git diff --stat`/`git diff`).
- `git diff --check` clean.
- Default 2048 applied when `AI_MAX_TOKENS` unset or empty (`:-2048` → jq 2048).
- Var-name match across POS_CONFIG header, providers, and config-ui writer.
- Lazy `AI_SESSION_TURNS` resolution after `load_config` in all 4 `session_push` call sites; `n>=1` guard; `--argjson` numeric slicing; n=10 → exactly 10 messages = 5 exchanges; large arrays safe; help text truthful.
- Docs consistent (POS.md 94-95 + :64, HOWTO:45, AGENT_Context:491, filetable 709).
- No GEN block hand-edits (only the generated filetable row; value matches `wc -l`).
- llamacpp.sh / pos-ai-server / aliases / tests / AGENT_TODO untouched.

## Verification unverified

- `make gen` idempotence (and `git diff --exit-code` after gen), `make check`, `make lint` (0 FAIL/0 WARN), `make test` (17/299), `bash -n` — sandbox denies execution; need Orchestrator run.
- Live `reg_config_keys ai` / `pos config ai` display (static evidence strong; runtime render unverified).
- Live OpenRouter/Gemini request + 402 reproduction (no network/key; fake-curl smoke was temp, not committed; design §Testing defers permanent coverage to Tester).

## Scope compliance

- In-scope confirmed: header @General additions; session_push lazy resolution + guard; Config: help lines; openrouter `max_tokens`; gemini `generationConfig.maxOutputTokens`; three doc files; generated filetable row.
- Out-of-scope found: none.

## Remaining uncertainty

- Gate results (Builder's claims unconfirmed in-sandbox).
- Whether the auto-routed OpenRouter model's output price per token is low enough for 2048 output tokens within the ~4511-token balance (live repro needed).
- Leading-zero / 0 / negative `AI_MAX_TOKENS` behavior is *certain* from jq/bash semantics (jq `tonumber` on `"abc"` errors; `"010"` is an invalid numeric literal; `0`/`-5` are valid numbers the providers will reject).

## Verdict

**CHANGES_REQUIRED** — one REQUIRED finding (token-cap input guard), fixable in ~4 lines within the approved scope (Builder), after which the same reviewer step re-verifies; then the Orchestrator runs the four gates and Tester adds permanent provider-body + session-pruning coverage per design §Testing.

## Handoff

**Status:** CHANGES_REQUIRED
**Objective/problem:** one REQUIRED robustness finding on the new `AI_MAX_TOKENS` input path (and the same leading-zero hole in the session guard).
**Evidence:** config-ui:419 accepts 0/-5/010; providers pass them unguarded to jq; provider 400 or raw jq abort under `set -e`; sibling guard at pos-ai:290-291 proves the intended pattern.
**Affected areas:** `lib/ai-providers/openrouter.sh:22-23`, `lib/ai-providers/gemini.sh:17-19`, optionally `bin/pos-ai:290-291` guard regex.
**Scope/decision boundary:** Builder may only add the numeric guard (default-fallback on invalid); no design change.
**Verification performed:** full static diff/code/doc/registry audit; `git diff --check`; `wc -l` consistency; gates UNVERIFIED (sandbox).
**Remaining uncertainty:** gate results; live 402 repro.
**Recommended next agent:** **Builder**
**Reason:** the fix is a scoped, fully-specified 4-line hardening within the approved change; after it lands, Orchestrator runs gates and Tester adds the permanent regression tests (provider-body cap, session pruning) the design already budgets.

**Changes made by Reviewer:** none (report file only).

---

## Caveats for the user (present regardless of the REQUIRED finding)

1. **402 may persist if the routed model is pricey:** 2048 output tokens at a high per-token price can still exceed the ~4511-token balance. Recommended: set an explicit cheaper `OPENROUTER_MODEL`, lower `AI_MAX_TOKENS` (e.g. 512), or switch `AI_PROVIDER=gemini`/`llamacpp`.
2. **Cap truncates long answers:** `--full` requests are cut at `AI_MAX_TOKENS` (default 2048); raise the var if you need long-form output.
3. **Env beats config file:** an exported `AI_MAX_TOKENS`/`AI_SESSION_TURNS` in your shell overrides `ai.env` (documented `load_env_file` semantics).
4. **Session bound is opt-in:** default stays 40 messages (20 exchanges) for backward compatibility; set `AI_SESSION_TURNS=10` for "last 5 req/response".