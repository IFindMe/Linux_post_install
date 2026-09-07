# Reviewer Re-check — Finding 1 (input-guard hardening)

**Date:** 2026-09-06
**Reviewer:** big-pickle (read-only, adversarial)
**HEAD:** 8ce5479 + uncommitted Builder changes
**Re-verifies:** `AgentsReport/reviewer/2026-09-06_ai-cost-window-review.md` → Finding 1 (REQUIRED) + Finding 2 (NOTE)

## TL;DR

- **Status: ACCEPT** — all three guard sites match the exact fix spec; no findings remain.
- Guard regex `^[1-9][0-9]*$` rejects 0, -5, 010, abc, empty; legitimate values (512, 2048, 4096) pass.
- `local mt` does not shadow any existing local in either provider; jq plumbing (`--arg mt` + `tonumber`; `--argjson n`) is correct.
- Scope: only the three code files changed for F1; no unrelated diffs; jq response parsing untouched.
- Caveats: (1) runtime gate suite (`make gen/check/lint/test`) still needs Orchestrator execution; (2) live 402 repro unverified.

---

## Step 1: openrouter.sh guard — [PASS]

**Lines 22-25 (actual):**
```
local mt="${AI_MAX_TOKENS:-2048}"
[[ "$mt" =~ ^[1-9][0-9]*$ ]] || mt=2048
body="$(printf '%s' "$body" | jq -nc --arg m "$model" --argjson msgs "$body" --arg mt "$mt" \
    '{model:$m, messages:$msgs, max_tokens:($mt|tonumber)}')"
```

| Check | Result |
|-------|--------|
| Guard BEFORE jq executes | ✅ lines 22-23 precede jq on line 24 |
| `local mt` no shadow | ✅ line 15 declares `model messages system body resp code body_out errmsg` — `mt` not present |
| `$mt` used consistently | ✅ declared line 22, guarded line 23, passed `--arg mt "$mt"` line 24, consumed `($mt\|tonumber)` line 25 |
| Regex rejects 0 | ✅ `0` fails `^[1-9]…` (first char must be `[1-9]`) → falls back to 2048 |
| Regex rejects -5 | ✅ `-` fails `^[1-9]…` |
| Regex rejects 010 | ✅ `0` fails `^[1-9]…` |
| Regex rejects abc | ✅ `a` fails `^[1-9]…` |
| Regex rejects empty | ✅ empty string fails `^[1-9]…` |
| Default on unset/empty | ✅ `${AI_MAX_TOKENS:-2048}` covers both; regex re-confirms |
| Legitimate values pass | ✅ `512`, `2048`, `4096` all match `^[1-9][0-9]*$` |
| jq `tonumber` safe | ✅ only guaranteed-positive-integer strings reach `tonumber` |

## Step 2: gemini.sh guard — [PASS]

**Lines 17-22 (actual):**
```
local mt="${AI_MAX_TOKENS:-2048}"
[[ "$mt" =~ ^[1-9][0-9]*$ ]] || mt=2048
body="$(printf '%s' "$messages" | jq -c --arg mt "$mt" '{
    contents: [.messages[]? | {role: (.role | gsub("assistant";"model")), parts: [{text: .content}]}],
    generationConfig: {maxOutputTokens: ($mt|tonumber)}
}')"
```

| Check | Result |
|-------|--------|
| Guard BEFORE jq executes | ✅ lines 17-18 precede jq on line 19 |
| `local mt` no shadow | ✅ line 15 declares `model messages system body resp code body_out errmsg` — `mt` not present |
| Identical guard pattern to openrouter | ✅ exact same two lines |
| All regex rejection cases | ✅ same analysis as Step 1 |
| jq plumbing correct | ✅ `--arg mt` string → `tonumber` → integer in `generationConfig` |

## Step 3: session_push guard — [PASS]

**Lines 288-293 (actual):**
```
session_push() {
    local messages="$1" role="$2" text="$3"
    local n="${AI_SESSION_TURNS:-$MAX_SESSION_TURNS}"
    [[ "$n" =~ ^[1-9][0-9]*$ ]] || n="$MAX_SESSION_TURNS"
    printf '%s' "$messages" | jq -c --arg r "$role" --arg t "$text" --argjson n "$n" \
        '.messages += [{role:$r, content:$t}] | .messages |= .[-$n:]'
}
```

| Check | Result |
|-------|--------|
| Guard regex is `^[1-9][0-9]*$` | ✅ line 291 — matches spec, rejects leading zeros |
| Old redundant `>= 1` check removed | ✅ gone; regex alone suffices |
| Guard BEFORE jq executes | ✅ lines 290-291 precede jq on line 292 |
| `--argjson n "$n"` correct | ✅ valid JSON integer after regex; jq variable `$n` used in slice `.-$n:` |
| Fallback is `$MAX_SESSION_TURNS` | ✅ line 291, not a hardcoded literal |
| `MAX_SESSION_TURNS=40` untouched | ✅ line 25 of pos-ai confirmed |

## Step 4: Scope — [PASS]

`git diff --stat HEAD` shows exactly 6 files:
- `bin/pos-ai` — F1 session_push guard + earlier-round header/help/config
- `lib/ai-providers/openrouter.sh` — F1 guard only
- `lib/ai-providers/gemini.sh` — F1 guard only
- `DOC/AGENT_Context_Project.md`, `DOC/HOWTO.md`, `DOC/POS.md` — earlier-round docs

No other files changed. No jq response-parsing shapes altered from the earlier round.

## Step 5: Consistency across all sites — [PASS]

Both providers use the identical pattern:
```bash
local mt="${AI_MAX_TOKENS:-2048}"
[[ "$mt" =~ ^[1-9][0-9]*$ ]] || mt=2048
```

session_push uses the same regex pattern for its sibling variable:
```bash
local n="${AI_SESSION_TURNS:-$MAX_SESSION_TURNS}"
[[ "$n" =~ ^[1-9][0-9]*$ ]] || n="$MAX_SESSION_TURNS"
```

The asymmetry that existed before (session had a guard, token cap did not) is now resolved. All user-configurable numeric values that reach jq/`--argjson` are guarded with the same `^[1-9][0-9]*$` pattern.

---

## Findings

None. All demands from the original Finding 1 and Finding 2 are satisfied.

## Verification verified

- All three guard sites exist at exact claimed lines (FACT — direct file read).
- Guard placement before jq confirmed by line-number ordering (FACT).
- No local-name shadowing in either provider (FACT — line 15 declarations compared).
- Regex rejects all specified bad inputs (FACT — `^[1-9][0-9]*$` does not match 0, -5, 010, abc, empty).
- `MAX_SESSION_TURNS=40` at line 25 is untouched (FACT).
- No scope creep (FACT — `git diff --stat`).

## Verification unverified

- Runtime gate suite execution (make gen/check/lint/test) — Orchestrator responsibility.
- Live OpenRouter/Gemini 402 fix confirmation — requires network + API key.

## Verdict

**ACCEPT**

## Caveats

1. Orchestrator must still run `make gen && git diff --exit-code && make check && make lint` before merge.
2. Live 402 reproduction unverified (design §Testing defers to Tester).
