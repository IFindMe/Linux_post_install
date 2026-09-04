# Builder R10 — Dynamic Provider Config Discovery

## TL;DR
- Status: IMPLEMENTED
- Files changed: `lib/config-ui.sh` (+30/-1), `lib/ai-providers/gemini.sh` (+4), `lib/ai-providers/openrouter.sh` (+4), `bin/pos-ai` (+4/-7), `DOC/AGENT_Context_Project.md` (+1/-1 gen drift: line count)
- Pattern: analogous to existing `_cfg_plugin_keys()` for entertainment plugins
- Verification: all syntax checks pass; `make gen && make check && make lint` green
- Dynamic probe: adding a mock `test.sh` with `# PROVIDER_CONFIG:` headers makes keys appear; removing it makes them disappear

## Step 1: Add `_cfg_provider_keys()` to config-ui.sh [DONE]

Added after `_cfg_plugin_keys()` (line 137). Scans `lib/ai-providers/*.sh` for `# PROVIDER_CONFIG:` headers, parses `KEY=flags:description` format, dedupes via `_cfg_seen[]`. Returns `key|flags|desc|` (4-field pipe format matching `_cfg_key_line` output).

## Step 2: Update case dispatch for `*providers` in config-ui.sh [DONE]

Added `*providers*) _cfg_provider_keys ;;` to the existing `case "$field"` block at line ~184.

## Step 3: Add PROVIDER_CONFIG headers to gemini.sh [DONE]

```
# PROVIDER_CONFIG: AI_GEMINI_API_KEY=secret:Gemini API key from aistudio.google.com
# PROVIDER_CONFIG: AI_GEMINI_MODEL=:Gemini model id (default: gemini-2.5-flash)
```

## Step 4: Add PROVIDER_CONFIG headers to openrouter.sh [DONE]

```
# PROVIDER_CONFIG: OPENROUTER_API_KEY=secret:OpenRouter API key from openrouter.ai
# PROVIDER_CONFIG: OPENROUTER_MODEL=:OpenRouter model id (default: openrouter/auto)
```

## Step 5: Update POS_CONFIG header in bin/pos-ai [DONE]

Replaced hardcoded `AI_GEMINI_API_KEY`, `OPENROUTER_API_KEY`, `AI_MODEL` with `*providers` marker. New header:
```
# POS_CONFIG: ai | ai.env | AI_PROVIDER=:Provider (...) | *providers | AI_SYSTEM_PROMPT=:...
```

## Step 6: Update usage() Config section in bin/pos-ai [DONE]

Removed hardcoded key entries; added "Provider keys: auto-discovered from lib/ai-providers/*.sh".

## Step 7: Syntax check all changed files [DONE]

All four files pass `bash -n`: config-ui.sh, gemini.sh, openrouter.sh, pos-ai.

## Step 8: make gen && make check && make lint [DONE]

- `make gen`: gen-docs write OK (line count auto-updated 645→632 for pos-ai)
- `make check`: check-sync OK
- `make lint`: 0 FAIL, 0 WARN

## Dynamic Discovery Probe

Direct invocation of `_cfg_provider_keys()`:
```
AI_GEMINI_API_KEY|secret|Gemini API key from aistudio.google.com|
AI_GEMINI_MODEL||Gemini model id (default: gemini-2.5-flash)|
OPENROUTER_API_KEY|secret|OpenRouter API key from openrouter.ai|
OPENROUTER_MODEL||OpenRouter model id (default: openrouter/auto)|
```

Full `cfg_scope_keys "ai"`:
```
AI_PROVIDER||Provider (gemini or openrouter, default gemini)|
AI_GEMINI_API_KEY|secret|Gemini API key from aistudio.google.com|
AI_GEMINI_MODEL||Gemini model id (default: gemini-2.5-flash)|
OPENROUTER_API_KEY|secret|OpenRouter API key from openrouter.ai|
OPENROUTER_MODEL||OpenRouter model id (default: openrouter/auto)|
AI_SYSTEM_PROMPT||Custom system prompt (overrides built-in, empty to reset)|
```

Mock test: added `lib/ai-providers/test.sh` with `TEST_KEY` and `TEST_MODEL` → both appeared in output. Removed file → both disappeared.

## Diff Stats
```
 DOC/AGENT_Context_Project.md   |  2 +-
 bin/pos-ai                     |  8 +++-----
 lib/ai-providers/gemini.sh     |  4 ++++
 lib/ai-providers/openrouter.sh |  4 ++++
 lib/config-ui.sh               | 30 +++++++++++++++++++++++++++++-
 5 files changed, 41 insertions(+), 7 deletions(-)
```

## Gates
| Gate | Result |
|------|--------|
| bash -n (all 4 files) | PASS |
| make gen | PASS |
| make check | PASS |
| make lint | PASS (0 FAIL, 0 WARN) |

REPORT_PATH: ./reportAgents/2026-08-25-builder-r10-dynamic-provider-config.md
