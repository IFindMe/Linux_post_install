# Builder Report — fix `_alias_find()` set -e crash

## TL;DR

- **Status:** COMPLETE
- **File changed:** `bin/pos-ai-alias` (line 103: `return 1` → `return 0`)
- **Gate:** 0 FAIL, 0 WARN
- **Verification:** bash -n OK, make gen OK, make check OK, make lint OK

## Step 1: Fix `_alias_find()` return code

`_alias_find()` (line 94-104) outputs `-1` on not-found and returns 1. Callers capture stdout in a variable (`existing="$(_alias_find "$name")"`) and check for `-1`. The exit code is never checked — the return 1 is purely harmful under `set -e`.

**Change:** line 103 `return 1` → `return 0`.

[DONE]

## Step 2: Scan for same pattern in other functions

Only `_alias_find` is captured via `$(...)` variable assignment and returns non-zero as a "not found" signal. Other non-zero returns:
- `_alias_regen` line 77: `return 1` on syntax error — called directly (not in `$()`), so it's a fatal-error propagation, not the same pattern.
- `_alias_provider_pick` / `menu_pick`: callers already guard with `|| return 0`.
- `_alias_name_valid`: always used in `if` statements.

No other fixes needed.

[DONE]

## Step 3: Gates — syntax, gen, check, lint

- `bash -n bin/pos-ai-alias` — OK
- `make gen` — gen-docs OK
- `make check` — check-sync OK
- `make lint` — `0 FAIL, 0 WARN`

All green.

[DONE]
