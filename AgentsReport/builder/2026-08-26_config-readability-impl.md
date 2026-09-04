# Builder Report — config-ui readability implementation

Date: 2026-08-26 · Agent: Builder · Status: **IMPLEMENTED**

## TL;DR

- Status: **IMPLEMENTED** — critical caption-parsing bug found and fixed; all three pieces verified
- Files changed: `lib/config-ui.sh` (3 surgical edits to fix delimiter collision)
- Bug fixed: caption records `>|cond|caption|` used `|` as delimiter, colliding with `|` in alternation syntax (`AI_PROVIDER=gemini|`); fixed by switching to `\x1f` (unit separator)
- Additional fix: `nums` map used old `%%|*` check that didn't detect `\x1f`-delimited caption records; updated to `[[ == ">"* ]]`
- Pilot header `bin/pos-ai:6` already in new format (done in prior commit)
- All three pieces present and functional: caption fields, tagged wildcards, uniform typography
- Gates: `bash -n` ✅ · `make gen` ✅ · `make check` ✅ · `make lint` 0 FAIL 0 WARN ✅
- Scopes verified: `ai` (3 provider states), `system`, `telegram`, `entertainment`

## Step 1: Bug diagnosis — caption record delimiter collision

**[DONE]**

Two bugs found:

### Bug 1: Caption record delimiter
The `cfg_scope_keys` function emitted caption records as `>|cond|caption|`, using `|` as the field separator. However, the condition string can contain `|` from the alternation syntax (e.g. `AI_PROVIDER=gemini|` in `@[AI_PROVIDER=gemini|] Gemini`).

When `cfg_ui` parsed these records with `IFS='|' read -r k f d e`, the extra pipe shifted the fields:
- Record: `>|AI_PROVIDER=gemini||Gemini|`
- Split: k=`>`, f=`AI_PROVIDER=gemini`, d=`` (empty!), e=`Gemini|`
- `pend_cap` got empty string → **caption silently never rendered**

Result: the entire Gemini group was invisible — no caption, no dim state.

### Bug 2: nums map old-format check
The number→index map at line 504 used `[ "${recs[$idx]%%|*}" = ">" ]` to exclude caption records. With `\x1f`-delimited caption records, this check doesn't detect unconditional captions (no `|` in the record), potentially including them in the numbered key list.

## Step 2: Fixes applied

**[DONE]**

Three edits to `lib/config-ui.sh`:

### 2a. New constant `_CS` (line 49)
```bash
_CS=$'\x1f'   # unit-separator for caption records — never in env
               # names or alt strings, avoids collision with | in
               # alternation syntax (AI_PROVIDER=gemini|)
```

### 2b. Caption record emission in `cfg_scope_keys` (line 292)
```bash
# Before: printf '%s\n' ">|$cond|$cap|"
printf '%s\n' ">${_CS}${cond}${_CS}${cap}${_CS}"
```

### 2c. Caption record parsing in `cfg_ui` (lines 525-535)
```bash
# Before: IFS='|' read -r k f d e <<<"${recs[$idx]}"
#         pend_cond="$f"; pend_cap="$d"

if [[ "${recs[$idx]}" == ">"* ]]; then
    pend_cond="${recs[$idx]#>}"
    pend_cond="${pend_cond#$_CS}"
    pend_cond="${pend_cond%%$_CS*}"
    pend_cap="${recs[$idx]#>}"
    pend_cap="${pend_cap#$_CS}"
    pend_cap="${pend_cap#*$_CS}"
    pend_cap="${pend_cap%%$_CS*}"
    continue
fi
IFS='|' read -r k f d e <<<"${recs[$idx]}"
```

### 2d. nums map check (line 504)
```bash
# Before: [ "${recs[$idx]%%|*}" = ">" ] || nums+=("$idx")
[[ "${recs[$idx]}" == ">"* ]] || nums+=("$idx")
```

**Why `\x1f`:** The ASCII unit separator never appears in env variable names (`[A-Z0-9_]+`) or alt strings. It can't collide with `|` in conditions or `:` in flags/descriptions.

**Backward compatibility:** Key records still use `|` — unchanged. Caption records are only consumed by the `>` branch in `cfg_ui`, so no other consumer is affected. `cfg_scopes`/`cfg_scope_envfile` only read fields 1-2 of each header (scope + env-file). `scripts/gen-docs.sh` and `completions/pos.bash` read scope names only.

## Step 3: Test harness — ai scope (all three provider states)

**[DONE]**

### AI_PROVIDER=openrouter (both API keys set, models/prompt unset)
```
pos config — ai (ai.env)
────────────────────────────────────────
   1) AI_PROVIDER                  openrouter
      Provider (gemini or openrouter, default gemini)

  ── Gemini — inactive while AI_PROVIDER=openrouter
   2) AI_GEMINI_API_KEY            AIzaSy...6789 (22 chars)
      Gemini API key from aistudio.google.com
   3) AI_GEMINI_MODEL              gemini-2.5-flash
      Gemini model id (default: gemini-2.5-flash)

  ── OpenRouter
   4) OPENROUTER_API_KEY           sk-or-...6789 (22 chars)
      OpenRouter API key from openrouter.ai
   5) OPENROUTER_MODEL             anthropic/claude-sonnet-4
      OpenRouter model id (default: openrouter/auto)

  ── General
   6) AI_SYSTEM_PROMPT             You are a helpful assistant
      Custom system prompt (overrides built-in, empty to reset)

Number to edit [r=refresh, q=quit]:
```
✅ Gemini inactive with reason, OpenRouter active, numbers 1–6 stable

### AI_PROVIDER=gemini
```
pos config — ai (ai.env)
────────────────────────────────────────
   1) AI_PROVIDER                  gemini
      Provider (gemini or openrouter, default gemini)

  ── Gemini
   2) AI_GEMINI_API_KEY            AIzaSy...6789 (22 chars)
      Gemini API key from aistudio.google.com
   3) AI_GEMINI_MODEL              gemini-2.5-flash
      Gemini model id (default: gemini-2.5-flash)

  ── OpenRouter — inactive while AI_PROVIDER=gemini
   4) OPENROUTER_API_KEY           sk-or-...6789 (22 chars)
      OpenRouter API key from openrouter.ai
   5) OPENROUTER_MODEL             anthropic/claude-sonnet-4
      OpenRouter model id (default: openrouter/auto)

  ── General
   6) AI_SYSTEM_PROMPT             You are a helpful assistant
      Custom system prompt (overrides built-in, empty to reset)

Number to edit [r=refresh, q=quit]:
```
✅ Gemini active, OpenRouter inactive with reason

### AI_PROVIDER unset (empty-alt segment test)
```
pos config — ai (ai.env)
────────────────────────────────────────
   1) AI_PROVIDER                  (not set)
      Provider (gemini or openrouter, default gemini)

  ── Gemini
   2) AI_GEMINI_API_KEY            AIzaSy...6789 (22 chars)
      Gemini API key from aistudio.google.com
   3) AI_GEMINI_MODEL              gemini-2.5-flash
      Gemini model id (default: gemini-2.5-flash)

  ── OpenRouter — inactive (AI_PROVIDER not set)
   4) OPENROUTER_API_KEY           (not set)
      OpenRouter API key from openrouter.ai
   5) OPENROUTER_MODEL             (not set)
      OpenRouter model id (default: openrouter/auto)

  ── General
   6) AI_SYSTEM_PROMPT             You are a helpful assistant
      Custom system prompt (overrides built-in, empty to reset)

Number to edit [r=refresh, q=quit]:
```
✅ Empty-alt segment `gemini|` means "or unset = default gemini" — Gemini active, OpenRouter inactive with "not set" reason

## Step 4: Test harness — contrasting scopes (backward compat)

**[DONE]**

### System scope (old-format header, 2 keys, long description)
```
pos config — system (system.env)
────────────────────────────────────────
   1) BACKUP_SERVICE_ROOTS         /srv /home/user/srv
      Roots scanned by backup --service and the health
      backup-age check (default: /srv $HOME/srv)
   2) HEALTH_BACKUP_MAX_AGE_DAYS   2
      Max backup age in days before health warns (default 2)

Number to edit [r=refresh, q=quit]:
```
✅ No captions, no grouping, long description word-wrapped, clean typography

### Telegram scope (secret masking + digits flag)
```
pos config — telegram (telegram.env)
────────────────────────────────────────
   1) TELEGRAM_BOT_TOKEN           123456...WXYZ (37 chars)
      Bot token from @BotFather
   2) TELEGRAM_CHAT_ID             123456789
      Numeric chat id from @userinfobot

Number to edit [r=refresh, q=quit]:
```
✅ No captions, no grouping, secret masking unchanged, digits flag works

## Step 5: Gates

**[DONE]**

```
bash -n lib/config-ui.sh bin/pos-ai     → OK
make gen                                  → gen-docs: write OK
make check                                → check-sync: OK
make lint                                 → 0 FAIL, 0 WARN
```

## Step 6: Implementation summary

### Piece 1: Caption fields ✅
- `@caption` — unconditional group caption
- `[KEY=alt1|alt2] caption` — conditional (active iff KEY matches an alt, or empty-alt for unset)
- Evaluation via existing `_cfg_cond_active` → `cfg_value` — per-render, so editing KEY flips emphasis on next redraw
- Inactive groups: dimmed with textual reason ("inactive while KEY=VALUE" or "inactive (KEY not set)"), never hidden → stable numbering
- Lazy flush: pending caption only prints when a key follows (empty adapter suppresses orphan caption)

### Piece 2: Tagged wildcard ✅
- `*providers=<tag>` restricts expansion to `lib/ai-providers/<tag>.sh`
- Bare `*providers` works exactly as before (all adapters)
- Zero-match explicit tag: warns on stderr + suppresses preceding caption via lazy flush

### Piece 3: Uniform typography ✅
- Bold title (`BOLD`), CYAN rule (40 × `─`), dim numbers, bold keys, dim `(not set)`
- Hanging-indent word-wrap at `W = clamp(COLUMNS, 60, 120)` minus 6-col hang (via `_cfg_wrap`)
- Display → stderr (`{ ... } >&2` pattern from menu-lib)
- Prompt: `Number to edit [r=refresh, q=quit]: `
- Color tokens guarded with fallbacks (menu-lib.sh pattern)

### Pilot: bin/pos-ai header ✅
Updated in prior commit — line 6 carries the full caption/tag syntax.

### No per-scope branches ✅
All grouping logic is driven by `@` metadata in headers. The `system`, `notify`, `telegram`, and all other scopes render correctly without any captions — their headers simply don't declare `@` fields.

## Changes made

| File | Change |
|------|--------|
| `lib/config-ui.sh:49-51` | Added `_CS=$'\x1f'` constant with documentation comment |
| `lib/config-ui.sh:292` | Changed caption record emission from `>|cond|caption|` to `>\x1fcond\x1fcaption\x1f` |
| `lib/config-ui.sh:504` | Updated nums map from `%%|*` check to `[[ == ">"* ]]` |
| `lib/config-ui.sh:525-535` | Replaced `IFS='|' read` caption parsing with `\x1f`-based string operations |
| `AgentsReport/builder/` | This report |

## Remaining risks

- **DIM legibility on exotic palettes** — mitigated: secondary info only, meaning duplicated in text ("inactive while ...")
- **Typo'd condition keys** — visible (permanently dim group), self-inflicted, documented
- **No unit tests exist** for config-ui.sh — smoke-tested via harness; full test suite deferred to Tester

## Recommended next agent

**Reviewer** — implementation is complete and needs independent adversarial review before acceptance.
