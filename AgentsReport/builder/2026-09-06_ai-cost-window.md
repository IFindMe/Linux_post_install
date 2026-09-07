# Builder Report — AI cost & session-window design

**Date:** 2026-09-06
**HEAD:** 8ce5479 (clean tree; HEAD unchanged — implementation not committed)
**Design source:** `./AgentsReport/architect/2026-09-06_ai-cost-window-design.md`

## TL;DR

- **Status: IMPLEMENTED** (worktree changes uncommitted)
- **Files changed:** `bin/pos-ai`, `lib/ai-providers/openrouter.sh`, `lib/ai-providers/gemini.sh`, `DOC/POS.md`, `DOC/HOWTO.md`, `DOC/AGENT_Context_Project.md` (6 files, +18/−11; `make gen` auto-updated the `bin/pos-ai` filetable row 705→709)
- **Smoke:** provider-body cap (openrouter + gemini, default 2048 + custom 512) all pass; session_push lazy resolution + numeric guard all pass (incl. boundary 40, `10`, non-numeric/0/negative/empty fallback)
- **Gates:** `make gen` idempotent, `make check` OK, `make lint` 0 FAIL 0 WARN, `make test` 17/17 files + 299/299 checks, `git diff --check` clean, `bash -n` all touched scripts OK
- **Out-of-scope:** no changes to llamacpp.sh, pos-ai-server, aliases, other tools, tests, AGENT_TODO.md

---

## Step 1: POS_CONFIG header — add AI_MAX_TOKENS and AI_SESSION_TURNS

Append two entries to the `@General` section of `# POS_CONFIG:` header at `bin/pos-ai:6`.

- `AI_MAX_TOKENS=num:Max output tokens per request (default 2048; OpenRouter/Gemini cost cap)`
- `AI_SESSION_TURNS=num:Session message cap — 2 per exchange (default 40 = 20 exchanges; 10 = last 5)`

Wording matches the design report §Decision 3 exactly. `num:` type reuses the existing `LLAMACPP_CTX_SIZE=num:…` pattern in the same header.

[DONE]

## Step 2: session_push lazy resolution

Change `session_push()` (`bin/pos-ai:285-292`) to resolve `AI_SESSION_TURNS` lazily with numeric guard.

```bash
local n="${AI_SESSION_TURNS:-$MAX_SESSION_TURNS}"
[[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )) || n="$MAX_SESSION_TURNS"
```

- `^[0-9]+$` regex + `>= 1` → fallback on: empty, non-numeric, `0`, negative.
- Line 25 `MAX_SESSION_TURNS=40` untouched (help text `:67` still accurate).
- jq pruning now uses `--argjson n "$n" ... .[-$n:]` (no string interpolation into the filter).

[DONE]

## Step 3: Add Config help lines for the two new vars

Added to the `Config:` block in `pos ai --help` (`bin/pos-ai:95-96`):
`AI_MAX_TOKENS` + `AI_SESSION_TURNS` lines, matching the design's recommended `Config:` help documentation.

[DONE]

## Step 4: openrouter.sh — add max_tokens to body

`lib/ai-providers/openrouter.sh:22-23`: body now includes `max_tokens:($mt|tonumber)` via `--arg mt "${AI_MAX_TOKENS:-2048}"`. Empty/unset env → jq receives the literal `2048` (the `:-2048` default is a numeric literal, so there is no empty-string `tonumber` failure path).

[DONE]

## Step 5: gemini.sh — add generationConfig.maxOutputTokens

`lib/ai-providers/gemini.sh:17-19`: body now includes `generationConfig: {maxOutputTokens: ($mt|tonumber)}` via the same `--arg mt "${AI_MAX_TOKENS:-2048}"`. `systemInstruction` merging (`:20-23`) unchanged and composes with the new top-level field.

[DONE]

## Step 6: Doc updates

- `DOC/POS.md:93-95` ai.env table: two new rows after `AI_SYSTEM_PROMPT` (`AI_MAX_TOKENS` no/`2048`/"Max output tokens per request (OpenRouter/Gemini cost cap)"; `AI_SESSION_TURNS` no/`40`/"Session message cap — 2 per exchange; 10 = last 5 exchanges").
- `DOC/POS.md:64`: parenthetical "(configurable via `AI_SESSION_TURNS`)" added after "capped at 40 turns" — recommended edit from design §Decision 4.
- `DOC/HOWTO.md:45`: `AI_MAX_TOKENS`, `AI_SESSION_TURNS` inserted after `AI_SYSTEM_PROMPT` in the `ai.env` var list.
- `DOC/AGENT_Context_Project.md:491`: same two vars added to the ai.env summary parenthetical.
- Line-count rows (hand-maintained, `:595-613`): no bump needed — none of those rows' files (install.sh, lib/*, features/*) changed length. `bin/pos-ai` row lives in the GENERATED filetable and was auto-updated 705 → 709 by `make gen`.

[DONE]

## Step 7: make gen x2 + make check + make lint

- `make gen` ran 3× total (twice at implementation, once after the test suite): each rerun is a no-op → **idempotent**.
- Generated delta is ONLY the `bin/pos-ai` line-count row (705 → 709) in the filetable block. `completions/pos.bash` unchanged — verified `_pos_config_scopes` (`completions/pos.bash:55`) lists only scope *names* (already includes `ai`); individual keys are read live by `pos config` via `lib/config-ui.sh` from the `# POS_CONFIG:` headers (confirmed via `lib/registry.sh` `reg_scan bin` + `reg_config_keys ai` showing both new keys). The design's expectation that completions would gain the keys is a no-op in practice — no key-level completion table exists by design.
- `make check` (check-sync.sh): **OK**
- `make lint` (lint-conventions.sh): **0 FAIL, 0 WARN**

[DONE]

## Step 8: Smoke tests (no network — fake curl shim in /tmp/opencode/ai-cost-smoke)

### Provider body cap (`test-provider-body.sh`, 12 checks, exit 0)

Fake `curl` on PATH captures the `--data` body to a file and returns a canned 200 response + the `\n%{http_code}` line the adapters expect.

| Case | Body assertion | Result |
|---|---|---|
| openrouter, AI_MAX_TOKENS unset | `"max_tokens":2048` | OK |
| openrouter, unset — JSON shape | model kept, messages kept | OK |
| openrouter, unset — canned response | `hello from fake openrouter` round-trips | OK |
| openrouter, AI_MAX_TOKENS=2048 | `"max_tokens":2048` | OK |
| openrouter, AI_MAX_TOKENS=512 | `"max_tokens":512` | OK |
| gemini, AI_MAX_TOKENS unset | `generationConfig.maxOutputTokens == 2048` | OK |
| gemini, unset — role conversion | assistant→model (unchanged behavior) | OK |
| gemini, unset — no systemInstruction when empty | absent | OK |
| gemini, unset — canned response | `hello from fake gemini` parses + round-trips | OK |
| gemini, AI_MAX_TOKENS=512 | `generationConfig.maxOutputTokens == 512` | OK |

Canned bodies (shim): openrouter `{"choices":[{"message":{"role":"assistant","content":"hello from fake openrouter"}}]}`, gemini `{"candidates":[{"content":{"parts":[{"text":"hello from fake gemini"}]}}]}`; both + `200`.

### session_push lazy resolution (`test-session-push.sh`, 10 checks, exit 0)

`session_push` brace-extracted from `bin/pos-ai` (same `extract_fn` pattern as `tests/t-menu-allow-empty.sh`; function's braces are balanced so extraction is exact), with `MAX_SESSION_TURNS=40` declared as in `bin/pos-ai:25`.

| Input | AI_SESSION_TURNS | Output length | Result |
|---|---|---|---|
| 30 msgs + 1 push | unset | 31 (no truncation under default) | OK |
| 30 msgs + 1 push | `10` | 10 (5 exchanges) | OK |
| 30 msgs + 1 push | `abc` (non-numeric) | 31 (fallback 40 → no truncation) | OK |
| 39 msgs + 1 push | unset | **40** (exact default boundary) | OK |
| 39 msgs + 1 push | `10` | 10 | OK |
| 39 msgs + 1 push | `0` (<1) | 40 (fallback) | OK |
| 39 msgs + 1 push | `-5` (negative) | 40 (fallback) | OK |
| 39 msgs + 1 push | `''` (empty) | 40 (fallback) | OK |

Note: the brief's "30-message array → 40 default" cannot be exact (30+1=31 < 40, so nothing is trimmed); the 39+1 boundary case proves the exact default of 40.

### Config registry discovery

`reg_scan bin` + `reg_config_keys ai` via `lib/registry.sh` returns both new keys in the `ai` scope (`AI_MAX_TOKENS=num:…`, `AI_SESSION_TURNS=num:…`) — `pos config ai` will present them.

### Full test suite

`make test`: **17 files pass / 0 fail / 0 skip; 299 checks pass / 0 fail / 0 skip** (matches the 17/299 budget).

### Other gates

- `bash -n bin/pos-ai lib/ai-providers/openrouter.sh lib/ai-providers/gemini.sh` — clean
- `git diff --check` — clean
- `make gen` idempotent; `make check` OK; `make lint` 0 FAIL 0 WARN

[DONE]

---

## Files changed (diff summary)

| File | Change |
|---|---|
| `bin/pos-ai` | POS_CONFIG header +2 keys; help Config block +2 lines; session_push lazy + guard (+4 net) |
| `lib/ai-providers/openrouter.sh` | body gains `max_tokens` |
| `lib/ai-providers/gemini.sh` | body gains `generationConfig.maxOutputTokens` |
| `DOC/POS.md` | table +2 rows; line 64 parenthetical |
| `DOC/HOWTO.md` | ai.env var list +2 |
| `DOC/AGENT_Context_Project.md` | ai.env parenthetical +2; generated filetable row auto-updated |

## Scope compliance

- In-scope changes only (design §Decision 5 file list). No llamacpp.sh, no pos-ai-server, no alias wrappers, no other tools, no tests, no AGENT_TODO.md edits.
- Provider call signature unchanged (`provider_generate "$model" "$messages" "$system"`).

## Remaining risks / follow-up

- `AI_MAX_TOKENS` too low truncates long `--full` answers (default 2048 mitigates; user can raise) — design's known risk.
- Env-vs-file precedence: exported env var beats config file (`load_env_file`) — expected and documented.
- Tester is recommended to add permanent provider-body + session-pruning regression tests (design §Testing).

## Handoff

Status: IMPLEMENTED
Recommended next agent: **Reviewer** (independent adversarial review of the diff before acceptance; Tester follows for permanent coverage per design §Testing).

---

## Reviewer finding F1 fix (2026-09-06, after reviewer CHANGES_REQUIRED)

**Source:** `AgentsReport/reviewer/2026-09-06_ai-cost-window-review.md` Finding 1 (REQUIRED) + Finding 2 (NOTE, folded).

**Problem:** `AI_MAX_TOKENS=0`/`-5`/`010` are accepted by `pos config ai` (`num:` regex `^-?[0-9]+$`, config-ui.sh:419) and passed unguarded into jq `($mt|tonumber)` → provider 400 (0/-5) or raw jq abort (010 = invalid JSON literal; abc = tonumber error). The sibling `AI_SESSION_TURNS` guard `^[0-9]+$` also let `010` through (octal 8 ≥ 1) then aborted jq via `--argjson n "010"`.

**Fix (exactly per reviewer demand, ~4 lines):**

1. `lib/ai-providers/openrouter.sh:22-23`:
   ```bash
   local mt="${AI_MAX_TOKENS:-2048}"
   [[ "$mt" =~ ^[1-9][0-9]*$ ]] || mt=2048
   ```
   then `--arg mt "$mt"` (previously `--arg mt "${AI_MAX_TOKENS:-2048}"`), keep `($mt|tonumber)`.
2. `lib/ai-providers/gemini.sh:17-18`: identical guard + use.
3. `bin/pos-ai:290-291` session guard tightened `^[0-9]+$` → `^[1-9][0-9]*$`; the `(( n >= 1 ))` check is now redundant (regex guarantees ≥ 1) and was dropped cleanly:
   ```bash
   local n="${AI_SESSION_TURNS:-$MAX_SESSION_TURNS}"
   [[ "$n" =~ ^[1-9][0-9]*$ ]] || n="$MAX_SESSION_TURNS"
   ```
   `--argjson n "$n"` is safe once n is strictly decimal (`[1-9][0-9]*` is a valid JSON numeric literal — no leading zeros).

**Re-verification (same harness, extended cases):**

| Check | Result |
|---|---|
| bash -n all three files | OK |
| Provider smoke (extended): AI_MAX_TOKENS unset / `0` / `-5` / `010` / `abc` → body `"max_tokens":2048`; `512` → `"max_tokens":512`; openrouter + gemini both | 16 checks OK |
| session_push smoke (extended): AI_SESSION_TURNS `0` / `010` / `-5` / `abc` → output length == default (31 for 30-array / 40 for 39-array boundary); `10` → 10 | 12 checks OK |
| `make gen` idempotent (POS_CONFIG unchanged; no new diff) | OK |
| `make check` | OK |
| `make lint` | 0 FAIL, 0 WARN |
| `make test` | 17 files / 299 checks green |
| `git diff --check` | clean |

**Smoke matrix detail (provider body, openrouter + gemini):**

| AI_MAX_TOKENS | openrouter body | gemini body |
|---|---|---|
| unset | `max_tokens:2048` | `maxOutputTokens:2048` |
| (empty) | `max_tokens:2048` | `maxOutputTokens:2048` |
| `0` | `max_tokens:2048` (fallback) | `maxOutputTokens:2048` (fallback) |
| `-5` | `max_tokens:2048` (fallback) | `maxOutputTokens:2048` (fallback) |
| `010` | `max_tokens:2048` (fallback, no jq abort) | `maxOutputTokens:2048` (fallback, no jq abort) |
| `abc` | `max_tokens:2048` (fallback, no jq abort) | `maxOutputTokens:2048` (fallback, no jq abort) |
| `512` | `max_tokens:512` | `maxOutputTokens:512` |

**session_push matrix (30-msg array + 1 push):**

| AI_SESSION_TURNS | output length | result |
|---|---|---|
| unset | 31 (all, default 40 no-op) | OK |
| `10` | 10 | OK |
| `0` | 31 (fallback 40) | OK |
| `010` | 31 (fallback 40 — former jq abort hole closed) | OK |
| `-5` | 31 (fallback 40) | OK |
| `abc` | 31 (fallback 40) | OK |

**Scope compliance:** only the 3 already-approved files touched in this fix round; no design change, no jq logic shape change (still `($mt|tonumber)` / `generationConfig: {maxOutputTokens: …}`), no new files (report appended).

[Handoff priority for F1 fix: Reviewer re-verify → Orchestrator gates → Tester permanent coverage; same recommendation as original handoff.]
