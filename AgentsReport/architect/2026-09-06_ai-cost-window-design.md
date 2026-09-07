# AI cost & session-window design — OpenRouter 402 + bounded session memory

**Date:** 2026-09-06
**Author:** Architect (big-pickle)
**HEAD:** 8ce5479 (clean tree)
**Mode:** design-only (no file edits besides this report)

## TL;DR

Two tightly associated defects in `pos ai` / `bin/pos-ai`:

1. **402 root cause** — no provider ever sends `max_tokens`, so OpenRouter's credit
   pre-check charges the routed model's full worst-case output (131072 on
   `openrouter/auto`) and rejects balances under that. Fix: send an explicit capped
   `max_tokens`.
2. **Unbounded-ish session** — `MAX_SESSION_TURNS=40` counts *messages* (20
   exchanges); user wants "last 5 req/response" = 10 messages.

**Decisions:** add `AI_MAX_TOKENS` (num, default **2048**) honored by openrouter
(body `max_tokens`) and gemini (`generationConfig.maxOutputTokens`); **skip** llamacpp.
Add `AI_SESSION_TURNS` (num, default **40** — backward compatible) honored lazily in
`session_push`; user sets **10** for 5 pairs. Both vars declared in the `@General`
section of the `# POS_CONFIG:` header, docs updated. No chat/alias wrapper changes.

**Open items:** none blocking. Tester should add provider-body + session-pruning
coverage (see §Testing).

---

## Verified fact confirmation (A–D)

All user-reported facts confirmed against source at HEAD:

**A — 402 root cause: CONFIRMED.**
- `lib/ai-providers/openrouter.sh:22-23` — body is only `{model,messages}`; no
  `max_tokens`. `:24-29` POSTs straight to OpenRouter with unchanged body.
- `lib/ai-providers/gemini.sh:17-19` — body only `{contents,...}`; no
  `generationConfig`. (`:20-23` adds only `systemInstruction`.)
- `lib/ai-providers/llamacpp.sh:32-33` — body `{model,messages,stream:false}`.
- Conclusion: none carry a generation cap → OpenRouter 402 with the user's thin
  balance. Fix is to send an explicit `max_tokens`.

**B — session window: CONFIRMED.**
- `bin/pos-ai:25` `MAX_SESSION_TURNS=40`.
- `session_push()` `bin/pos-ai:285-290` → `'.messages |= .[-"$MAX_SESSION_TURNS":]'`
  prunes to last N **messages** (40 msgs = 20 exchanges). User wants 5 pairs = 10 messages.

**C — config surface: CONFIRMED.**
- `# POS_CONFIG:` header `bin/pos-ai:6`, scope `ai | ai.env`.
- `num:` type already used in the same header (`LLAMACPP_CTX_SIZE=num:…`,
  `LLAMACPP_GPU_LAYERS=num:…`).
- Validation: `lib/config-ui.sh:419` `*,num,*) [[ "$val" =~ ^-?[0-9]+$ ]]` — integer-only
  on *entry*; empty input ="kept current value" (`:468-471`); `-` = clear (`:472-477`).
  So `num:` + empty/unset → falls back to code default. Clean.
- Env precedence: `load_env_file` (`lib/config-ui.sh:336-357`) exports a file key only
  when the variable is not already set in the environment (`:351-353`) → env beats
  file beats default. Providers read config via env (`AI_API_KEY` pattern).
- `PROVIDER_CONFIG` headers exist on `openrouter.sh:7-8`, `gemini.sh:7-8`,
  `llamacpp.sh:7` for *provider-specific* keys.

**D — provider resolution: CONFIRMED.**
- `bin/pos-ai:679-683` — `--provider` flag > `AI_PROVIDER` env > `gemini`.
- `load_config()` `bin/pos-ai:141-151` loads `ai.env` (+ legacy files); called by
  `resolve_key` (line 155) and at provider resolution (line 681).
- Call site `bin/pos-ai:522` (ask) and `:557` (chat): `provider_generate "$model" "$messages" "$system"`.

**Gates/tests scan:**
- No test pins `MAX_SESSION_TURNS`, the provider request bodies, or header text
  (`t-config-precedence.sh` targets `pos-ai-server`, a separate tool). No forced
  test update.
- `DOC/POS.md` has a hand-maintained ai.env config table (`:88-97`) and mentions
  "capped at 40 turns" at `:64`. `DOC/HOWTO.md:45` and `DOC/AGENT_Context_Project.md:491`
  list ai.env vars (hand-maintained). All need doc rows/bumps for the new vars.

---

## Decision 1: `AI_MAX_TOKENS` — cap generation tokens

**Status: [DECIDED]**

### Options & trade-offs

**Option 1 (chosen) — single global `AI_MAX_TOKENS=num`, default 2048, honored by remote providers (openrouter + gemini); skip llamacpp.**
- *Advantages:* smallest change that fixes the 402 (OpenRouter pre-check sees a
  capped cost) and is a real per-request cost ceiling; one var, one default; fits
  the existing `AI_*` env naming and the tool-level `@General` config section; no
  new per-provider surface.
- *Costs:* remote providers share one ceiling (no per-provider cap without user
  intervention).
- *Risks:* a too-low cap truncates long answers — mitigated by default 2048 being
  ample for terse `ask`/`chat` CLI answers; user can raise it.
- *Reasoning for default 2048:* conservative (user's balance affords ~4511 tokens at
  routed price, so 2048 passes the pre-check with margin) while being a practical,
  real ceiling. 2048 tokens ≈ several thousand chars — plenty for the terse,
  commands-first assistant role this tool plays.

**Option 2 — per-provider caps via `PROVIDER_CONFIG` (e.g. `AI_MAX_TOKENS` on openrouter.sh, gemini.sh).**
- *Advantages:* independent ceilings per provider.
- *Costs:* two declarations, redundant section plumbing, and the *default* (which is
  the entire point) still has no shared home → awkward. `PROVIDER_CONFIG` is for
  provider-specific concerns; a cost ceiling + 402 pre-check over both remote
  providers is tool-level, not provider-specific.

**Option 3 — no gemini cap; only openrouter.**
- *Advantages:* minimal (402 only affects OpenRouter).
- *Costs:* leaves Gemini without any cost ceiling while introducing the same var —
  inconsistent, and Gemini's own pricing can surprise. Rejected.

**Option 4 — include llamacpp too (`max_tokens` in body; it accepts it).**
- *Advantages:* provider parity on the OpenAI-compatible endpoint.
- *Costs:* local & free — no credit pre-check, no cost. Adds surface with zero user
  benefit. Rejected on the "smallest sufficient design" principle.

### Implementation contract
- Env var name: **`AI_MAX_TOKENS`**, type `num`, default **2048**.
- OpenRouter body (`openrouter.sh:22-23`): add `max_tokens`.
- Gemini body (`gemini.sh:17-19`): add `generationConfig.maxOutputTokens`.
- llamacpp: **no change**.
- Providers read `"${AI_MAX_TOKENS:-2048}"` from env; value is present because
  `load_config` runs before `provider_generate` (resolve path confirmed in D).
- Declare in `@General` section of `# POS_CONFIG:` header (`bin/pos-ai:6`).

---

## Decision 2: `AI_SESSION_TURNS` — bounded session window

**Status: [DECIDED]**

### Options & trade-offs

**Option 1 (chosen) — new `AI_SESSION_TURNS=num`, default 40 (unchanged), resolved lazily in `session_push`.**
- *Advantages:* fully backward compatible — no silent memory truncation for existing
  users. The user's "last 5 req/response" = setting `AI_SESSION_TURNS=10`. One var,
  one default.
- *Costs:* existing users must opt in (they already have the 40 behavior, so no
  regression).
- *Why keep default 40:* backward compatibility is a hard project value; silently
  shifting the default changes session context for *every* user, discards history
  they may rely on, and is a behavioral change not requested globally (only for this
  user). Keep 40.

**Option 2 — change the default to 10.**
- *Advantages:* meets the stated want out-of-the-box.
- *Costs:* silent behavior change for all users; discards memory; not requested
  globally. Rejected — keep the change opt-in via the new var.

### Semantics (must be documented)
The existing prune is `.messages |= .[-N:]` where N counts **messages** — 2 messages
per exchange. So `AI_SESSION_TURNS=10` ⇒ last **5** exchanges (5 user + 5 assistant).
The config description must state: "message count (2 per exchange); 10 = last 5
exchanges".

### Implementation constraint — lazy resolution (important)
`MAX_SESSION_TURNS` is currently assigned at `bin/pos-ai:25`, which executes at
top-level **before** `load_config` is first called (line 681). If we wrote
`MAX_SESSION_TURNS="${AI_SESSION_TURNS:-40}"` at line 25, an `AI_SESSION_TURNS` set
*only in ai.env* would not yet be loaded → always 40.

Therefore:
- Keep **line 25** as-is (`MAX_SESSION_TURNS=40`), used for the help text (`:67`
  shows the default, accurate).
- In `session_push()` (lines 285-290), resolve **lazily**:
  `local n="${AI_SESSION_TURNS:-$MAX_SESSION_TURNS}"` and use `$n` in the jq prune.
  Because `session_push` runs inside `cmd_ask`/`cmd_chat` — after `load_config`
  (via `resolve_key` at `:499`/`:538`) has exported `AI_SESSION_TURNS` into the
  process env — the ai.env value is honored. Shell-exported `AI_SESSION_TURNS`
  wins too (env-wins in `load_env_file`).
- Help text `bin/pos-ai:67` stays accurate ("capped at $MAX_SESSION_TURNS turns")
  since the default remains 40. Optionally add a `Config:` help line documenting the
  var — recommended, and it confirms "turns = messages, 10 = 5 pairs".

---

## Decision 3: `# POS_CONFIG:` header change

**Status: [DECIDED]**

- Single `@General` section addition (not per-provider `PROVIDER_CONFIG`):
  - `AI_MAX_TOKENS=num:Max output tokens per request (default 2048; OpenRouter/Gemini cost cap)`
  - `AI_SESSION_TURNS=num:Session message cap — 2 per exchange (default 40 = 20 exchanges; 10 = last 5)`
- Place both in the `@General` section alongside `AI_SYSTEM_PROMPT` (end of the
  long header line, `bin/pos-ai:6`).
- **Why @General, not PROVIDER_CONFIG:** the default is shared across providers
  (2048, 40) and both caps are tool-level concerns. `PROVIDER_CONFIG` is reserved for
  provider-specific keys (API keys, models). A single global declaration is the
  cleanest and avoids duplicating the default in two provider files.
- `num:` type confirmed suitable: `lib/config-ui.sh:419` enforces integer on entry;
  empty=keep current, `-`=clear (`:468-477`); unset → code default. No empty-parse
  concern.
- Provider bodies consume the vars from env, so no `PROVIDER_CONFIG` additions are
  needed on `openrouter.sh`/`gemini.sh`. (They could be added later if per-provider
  caps are ever wanted — out of scope now.)

---

## Decision 4: Docs & gates

**Status: [DECIDED]**

- **`DOC/POS.md`** (hand-maintained):
  - ai.env table (`:88-97`): add rows for `AI_MAX_TOKENS` (no/`2048`/"Max output
    tokens per request (OpenRouter/Gemini cost cap)") and `AI_SESSION_TURNS`
    (no/`40`/"Session message cap — 2 per exchange; 10 = last 5 exchanges"). The
    `AI_SYSTEM_PROMPT` row (`:93`) is the placement anchor.
  - Line 64 text "capped at 40 turns" remains true (default unchanged) — no edit
    strictly needed, but a short parenthetical "(configurable via AI_SESSION_TURNS)"
    is recommended.
- **`DOC/HOWTO.md:45`** — append `AI_MAX_TOKENS`, `AI_SESSION_TURNS` to the listed
  ai.env vars.
- **`DOC/AGENT_Context_Project.md:491`** — append the two vars to the ai.env
  summary parenthetical (hand-maintained).
- **`make gen`**: header text change does not add commands/subcommands/flags, so the
  generated tree/dispatch tables are unaffected; `completions/pos.bash` config-scope
  table regenerates to include the new keys. Run `make gen` (deterministic, `LC_ALL=C`
  per convention), then `make check`, then `make lint`.
- **Line-count rows** above the filetable marker in `AGENT_Context_Project.md`: only
  bump a row if a `pos-*`/`lib/*` file's length changes (it does — lib/ai-providers
  grow; bin/pos-ai grows). Do not touch rows for files that don't change.
- **tests**: existing suite does not pin the session default or provider bodies, so
  nothing is *forced*. Recommend new coverage (§Testing).

---

## Decision 5: Scope fence

**Status: [DECIDED]**

**Approved outcome:** OpenRouter 402 eliminated (explicit capped `max_tokens` on
remote providers) and session history bounded via configurable `AI_SESSION_TURNS`.

**In-scope files:**
- `bin/pos-ai` — `# POS_CONFIG:` header (line 6, @General additions); `session_push`
  lazy `AI_SESSION_TURNS` resolution (lines 285-290); optional `Config:` help lines
  for the two vars. Line 25 stays `MAX_SESSION_TURNS=40`.
- `lib/ai-providers/openrouter.sh` — add `max_tokens` to body (lines 22-23).
- `lib/ai-providers/gemini.sh` — add `generationConfig.maxOutputTokens` (lines 17-19).
- `lib/ai-providers/llamacpp.sh` — **no change**.
- Docs (hand-maintained): `DOC/POS.md`, `DOC/HOWTO.md`, `DOC/AGENT_Context_Project.md`.
- tests (later, Tester).

**Allowed interface changes:** two new config keys in scope `ai`; provider request
bodies gain a token cap. Provider call signature `provider_generate "$model" "$messages" "$system"`
is unchanged.

**Explicitly out of scope:** `bin/pos-ai-server`, chat/alias wrappers, `pos-ai-alias`,
HuggingFace downloader, other tools, per-provider caps, changing `MAX_SESSION_TURNS`
default, any llmacpp body change.

**Architectural constraints:**
- No new provider-side config plumbing; vars read from env (`AI_*` convention).
- Backward compatible: session default 40 and empty/unset values fall back to
  documented defaults.
- Deterministic `make gen`; `make check` + `make lint` green (definition of done).

**Open risks:**
- `AI_MAX_TOKENS` too low truncates long `--full` answers — default 2048 mitigates;
  user can raise.
- env-vs-file precedence: exported env var beats config file (per `load_env_file`) —
  expected and documented.

**Verification:**
- `bash -n` clean; `make gen`/`make check`/`make lint` green.
- A 402 reproduction no longer triggers when `AI_MAX_TOKENS` is set/at default.
- `AI_SESSION_TURNS=10` prunes the session to last 5 exchanges.

---

## Testing budget (suggestion for Tester / Builder verification)

- **Provider body cap:** source each provider adapter in a sandbox with `curl`
  stubbed, assert the request JSON contains `max_tokens` (openrouter) / a truthy
  `generationConfig.maxOutputTokens` (gemini). Pattern: `t-config-precedence.sh` style
  curl-log capture with a fake `curl` in `PATH` (see existing tests).
- **Session pruning:** drive `session_push` with a crafted messages JSON and
  `AI_SESSION_TURNS=10`, assert exactly the last 10 messages remain (5 pairs); and
  `AI_SESSION_TURNS` unset → 40 retained (default commits to backward compat).
- **Help/default fidelity:** `pos ai --help` still shows 40; `pos config ai` lists the
  two new `num:` keys and rejects a non-integer (`cfg_validate`).
- **Regression:** existing `t-config-precedence.sh`, `run-tests` full suite green.

---

## Handoff

**Status:** DECISION_READY

**Problem:** OpenRouter 402 (no `max_tokens` → full worst-case pre-check) and
unbounded session memory; user wants 5 req/response.

**Decision:** add `AI_MAX_TOKENS=num` (default 2048) honored by openrouter + gemini
(skip llamacpp); add `AI_SESSION_TURNS=num` (default 40, backward compatible) resolved
lazily in `session_push`; both in `@General` config section; docs updated.

**Ownership:** `bin/pos-ai` + `lib/ai-providers/{openrouter,gemini}.sh` (+ docs).

**Interfaces:** two new `ai`-scope config keys; provider bodies gain a token cap.
Call signature unchanged.

**Approved scope / constraints / verification / out-of-scope:** see Decision 5.

**Risks:** see Decision 5 (token-cap truncation; env-vs-file precedence — all mitigated).

**Recommended next agent:** **Builder**

**Reason:** the architecture and scope are fully specified with exact line-level
changes (no architectural ambiguity left). Builder can implement without making
architecture decisions. Tester follows for the recommended coverage.
