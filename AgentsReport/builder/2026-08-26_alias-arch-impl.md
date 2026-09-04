# Builder Report: Alias Architecture Rewrite + Dup-Table Fix

**Date:** 2026-08-26
**Files changed:** `bin/pos-ai-alias`, `bin/pos-system-uninstall`, `DOC/POS.md`, `AGENT_TODO.md`
**Gates:** `bash -n` ✅ | `make gen && make check` ✅ | `make lint` 0 FAIL 0 WARN ✅

---

## TL;DR

Implementation found already present in working tree — verified against architect spec, tested, gates green. All architect D1–D4 decisions implemented correctly. Dup-table bug fixed via single `_alias_table` renderer (variant: menu option 4 = no-op returning to loop). 17-category test suite (40 assertions) run externally against the actual script; 3 test-harness quoting artifacts debugged and confirmed not code bugs. No scope violations.

## Step 1: Verify implementation against architect spec ✅ [DONE]

Read architect spec (`AgentsReport/architect/2026-08-26_alias-architecture.md`), current `bin/pos-ai-alias`, and `bin/pos-system-uninstall`.

**Already implemented in working tree:**
- `_alias_regen()` deleted; replaced by `_wrapper_path()`, `_alias_owned()`, `_wrapper_render()`, `_wrapper_install()`, `_alias_check_path()`, `_alias_retire_legacy_sh()`, `_alias_sync()`
- `_alias_quote_cmd()` preserved verbatim (double-%q mechanism)
- `_alias_sync()` wired into every dispatch entry (create/edit/remove/list/show/menu)
- Collision refusals in `_alias_create()` (foreign file + `command -v` check)
- Legacy `ai-aliases.sh` auto-removal with unalias remediation hint
- Success messages updated ("Available immediately", dropped "Reload shell" everywhere)
- `show` gains wrapper path
- `usage()` text updated with activation description
- `bin/pos-system-uninstall`: marker scan in `scan_tier1()` (lines 98-105) and `remove_tier1()` (lines 272-281)
- `DOC/POS.md`: alias rows updated (activation via `~/.local/bin` wrappers, not `.bashrc` sourcing)

## Step 2: Dup-table bug fix verification ✅ [DONE]

**Chosen variant:** Menu option 4 is a no-op (`: ;;`) returning to the loop, which re-renders the table via `_alias_table` in the pre-render block.

**Rationale:** The menu's own pre-render (lines 266-275) already calls `_alias_table` fresh every iteration. Making option 4 a no-op is the simplest correct fix — zero code duplication, no new helper, and the "list" action is semantically "return to see the current list." The `_alias_list()` function remains available for the non-interactive `pos ai alias list` path, which still calls `_alias_table` through its own code path.

**Before (bug):** Menu pre-render showed table, then option 4 called `_alias_list()` which printed the table again → duplicated output.

**After (fix):** Menu option 4 returns to loop → loop re-renders → single table displayed.

## Step 3: Test harness ✅ [DONE]

External test harness (`/tmp/al-test.sh`) runs 17 test categories (40 assertions) against the actual `bin/pos-ai-alias` script with a stub `pos` that captures `$*`:

| # | Test | Result |
|---|------|--------|
| 1 | `_alias_sync` creates wrapper scripts (assist, evil, plain) | ✅ 5/5 |
| 2 | Wrapper content: marker on line 2, shebang, set -euo, exec | ✅ 6/6 |
| 3 | exec line correct provider/session | ✅ 2/2 |
| 4 | `--system` flag present for non-empty prompts | ✅ 2/2 |
| 5 | Empty prompt → no `--system` fragment | ✅ 2/2 |
| 6 | Wrapper executes: `assist "how are you"` → correct argv | ✅ 4/4 |
| 7 | Passthrough args: `--help` forwarded via `"$@"` | ✅ 1/1 |
| 8 | Evil wrapper (complex prompt) executes correctly | ✅ 1/1 |
| 9 | Legacy `ai-aliases.sh` removed by list | ✅ 1/1 |
| 10 | Second list call idempotent (same md5, same mtime) | ✅ 2/2 |
| 11 | Foreign file not touched by sync | ✅ 1/1 |
| 12 | Orphan retraction: removed ENV entry → wrapper deleted | ✅ 2/2 |
| 13 | Empty env → all wrappers deleted | ✅ 2/2 |
| 14 | **Staleness kill-test:** edit gemini→openrouter, wrapper live on next invocation | ✅ 3/3 |
| 15 | `show` includes wrapper path | ✅ 2/2 |
| 16 | Legacy foreign sh file untouched with warning | ✅ 2/2 |
| 17 | Help text mentions `~/.local/bin` and "no shell sourcing" | ✅ 2/2 |

**3 initial test failures debugged:** All were test-harness quoting artifacts (single quotes and `$(echo pwned)` in captured argv broke the assertion's `echo '$var'` pattern). Confirmed via direct `grep` on the captured file: evil wrapper correctly produces `CAPTURED: ai openrouter ask --session evil --system It's a 'quoted' $(echo pwned) \`backtick\` --help`.

## Step 4: Gates ✅ [DONE]

```
bash -n bin/pos-ai-alias              ✅
bash -n bin/pos-system-uninstall      ✅
make gen && make check                ✅ (gen-docs OK, check-sync OK)
make lint                             ✅ (0 FAIL, 0 WARN)
```

## Step 5: AGENT_TODO update ✅ [DONE]

The alias-related entry was already moved to Done (dated 2026-08-26) in the existing AGENT_TODO.md diff.

## Scope compliance ✅

**Touched (in scope):** `bin/pos-ai-alias`, `bin/pos-system-uninstall`, `DOC/POS.md`, `AGENT_TODO.md`, `AgentsReport/`
**Not touched (out of scope):** `bin/pos-ai`, `lib/common.sh`, `lib/menu-lib.sh`, `lib/config-ui.sh`, `completions/`, `postinstall.sh`, `pos-ai-alias` `# POS:` headers, registry code
**No commits made** per brief constraint.

## Dup-table fix variant chosen

**Variant:** Menu option 4 → no-op, returning to the loop's pre-render.
**Rationale:** Cleanest solution. The pre-render block already calls `_alias_table` on every iteration, so returning to the loop naturally shows the current state. Zero added code, zero new abstractions, and `_alias_list()` stays available for the non-interactive `list` path.
