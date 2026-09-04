# Builder Report — Self-Describing Command Registry for POS

**Date:** 2026-08-26
**Status:** COMPLETE

---

## TL;DR

- **Status:** All 8 steps implemented and verified
- **Files created:** `lib/registry.sh` (199 lines, mode 664)
- **Files modified:** `scripts/gen-docs.sh`, `bin/pos-tree`, `templates/pos-tool.sh`, `install.sh`, `DOC/DEV.md`, `DOC/AGENT_Context_Project.md`
- **Verification:** All gates pass — gen drift ✅, tree output identical ✅, make check ✅, make lint shows only pre-existing issues ⚠️

---

## Step 0: Establish Current State

**Prerequisite:** Pre-existing gen drift from `pos-ai-alias` was committed as `6566c83` (`chore: re-gen docs for pos-ai-alias addition`) to get a clean baseline.

**Baselines (all clean after gen drift fix):**

| Gate | Result |
|------|--------|
| `pos-tree` output | ✅ exit 0, captured to `/tmp/pos-tree-before.txt` |
| `make gen && git diff --exit-code` | ✅ zero diff (gen output matches committed) |
| `make check` | ✅ `check-sync: OK` |
| `make lint` | ⚠️ 1 FAIL (pre-existing: `bin/pos-ai-alias` not in `INTERACTIVE_CMDS`), 1 WARN (`pos-ai-alias` not in `DOC/POS.md`) — both unrelated to this task |

**Notes:**
- `make lint` takes ~2-3 minutes to complete (scans 56+ files with regex)
- The pre-existing lint FAIL on `pos-ai-alias` is outside our scope

[DONE]

---

## Step 1: Create `lib/registry.sh`

**File:** `lib/registry.sh` (191 lines, mode 664, no shebang)

**Changes:**
- Created the shared query API library following the architect's pseudocode and `lib/config-ui.sh` structural pattern
- Key derivation: `bin/pos-network-download` → key `network-download`, category `network`; `bin/pos-config` → key `config`, category `""`
- `reg_scan` sets/restores `LC_ALL=C` for deterministic sort
- All associative-array lookups use `${var:-}` fallback for missing keys
- `reg_categories` uses a sentinel `__empty__` to handle empty-category associative array limitation in bash
- All API functions implemented: `reg_scan`, `reg_list`, `reg_categories`, `reg_tools_in`, `reg_lookup`, `reg_config_scopes`, `reg_config_keys`, `reg_config_envfile`, `reg_each`, `reg_tool_exists`

**Functional test:** Registry loads all ~40 tools, lookups return correct data, categories list correctly, config scopes found.

[DONE]

---

## Step 2: Update `scripts/gen-docs.sh`

**File:** `scripts/gen-docs.sh` (modified)

**Changes:**
1. **Tools collection loop (lines ~42-47):** Added `deps` and `examples` fields to the pipe-delimited `tools` array format: `"$cat|$sub|$desc|$flags|$subcmds|$deps|$examples"`
   - `deps`: parsed with same `sed` pattern as existing headers
   - `examples`: parsed with `grep | sed | paste` (pipe-delimited, `|| true` to handle empty matches with `pipefail`)
2. **`_has_deps_examples` flag:** Scans tools array once to determine if any tool has non-empty deps/examples — drives conditional column rendering
3. **`gen_tree()`:** Reads 7 fields now; adds `[deps: X]` annotation line when non-empty
4. **`gen_dispatch()`:** When `_has_deps_examples=1`, adds Deps/Examples columns to the header and all data rows. When 0, renders unchanged format
5. **`gen_filetable()`:** Updated to read 7 fields (output unchanged — no deps/examples columns for now)
6. **`gen_posflags()`:** Updated to read 7 fields (output unchanged)
7. **`gen_possubcmds()`:** Updated to read 7 fields (output unchanged)

**Drift check:** `git diff -- DOC/AGENT_Context_Project.md completions/pos.bash` → **zero diff** — gen output is byte-identical to current committed output.

[DONE]

---

## Step 3: Migrate `bin/pos-tree`

**File:** `bin/pos-tree` (modified)

**Changes:**
1. Added `source lib/registry.sh` after common.sh sourcing (with fallback chain)
2. Replaced file-scanning loop (`for f in "$self"/pos-*`) with `reg_scan "$self"` + `reg_list` iteration
3. Tree data collection now uses `reg_lookup "$tool_key" cat|desc|subcmds|deps`
4. `add()` and `render()` functions kept **unchanged** — only data-collection section changed
5. When `deps` is non-empty, appended `[deps: X]` to the description string before passing to `add()`

**Output comparison:** `diff /tmp/pos-tree-before.txt /tmp/pos-tree-after.txt` → **empty (identical)**

[DONE]

---

## Step 4: Update `templates/pos-tool.sh`

**File:** `templates/pos-tool.sh` (modified)

**Changes:**
- Added `# POS_SUBCMDS:`, `# POS_DEPS:`, `# POS_EXAMPLES:` to the header documentation block (step 2 comment)
- Placed after existing `# POS_FLAGS:` example

[DONE]

---

## Step 5: Update `install.sh`

**File:** `install.sh` (modified)

**Changes:**
- Added `registry.sh` to the `lib_names` array (line 143) alongside other library names

[DONE]

---

## Step 6: Update `DOC/DEV.md`

**File:** `DOC/DEV.md` (modified)

**Changes:**
- Added `# POS_DEPS:` and `# POS_EXAMPLES:` to the header code block in "Adding a New CLI Tool → Make it discoverable"
- Added explanation paragraph for both new headers (POS_DEPS: runtime binary names; POS_EXAMPLES: curated usage examples)
- Both documented as optional with graceful degradation

[DONE]

---

## Step 7: Update `DOC/AGENT_Context_Project.md`

**File:** `DOC/AGENT_Context_Project.md` (modified)

**Changes:**
- Added `lib/registry.sh | 199 | Shared query API for POS tool metadata headers (...)` row to the hand-maintained line-count table (above GEN:START filetable marker)
- Gen blocks updated via `make gen` (docmap line numbers shifted by +1 section; filetable shows pos-tree at 118 lines)

[DONE]

---

## Step 8: Verification

### Syntax checks
```
bash -n lib/registry.sh      ✅
bash -n scripts/gen-docs.sh  ✅
bash -n bin/pos-tree         ✅
```

### Gen drift check
```
make gen && git diff --exit-code  ✅ (no gen drift)
```
- Generated blocks (tree, dispatch, filetable, selfcontained, posflags, possubcmds, posconfigscopes) are **byte-identical** to committed output
- `completions/pos.bash` has **zero diff**

### Tree output comparison
```
diff /tmp/pos-tree-before.txt /tmp/pos-tree-final.txt  → empty ✅
```

### Self-consistency gate
```
make check  →  check-sync: OK  ✅
```

### Convention lint gate
```
make lint  →  1 FAIL, 1 WARN  (both pre-existing, unrelated to this task)
```
- FAIL: `bin/pos-ai-alias` not in `INTERACTIVE_CMDS` — pre-existing
- WARN: `bin/pos-ai-alias` not in `DOC/POS.md` — pre-existing
- **Zero new issues from this implementation**

### Summary

| Gate | Result | Notes |
|------|--------|-------|
| Syntax | ✅ all pass | registry.sh, gen-docs.sh, pos-tree |
| Gen drift | ✅ zero diff | Gen blocks byte-identical |
| Tree output | ✅ identical | Before/after comparison empty |
| make check | ✅ OK | Full self-consistency gate |
| make lint | ⚠️ 1 FAIL, 1 WARN | Pre-existing only (pos-ai-alias) |

[DONE]

---

## Artifact Summary

### Files Created

| File | Mode | Lines | Purpose |
|------|------|-------|---------|
| `lib/registry.sh` | 664 | 199 | Shared query API for POS tool metadata headers |

### Files Modified

| File | Nature of Change |
|------|-----------------|
| `scripts/gen-docs.sh` | Added deps/examples to tools array format; conditional columns in gen_dispatch; deps annotation in gen_tree |
| `bin/pos-tree` | Migrated data collection from direct sed to registry API; source registry.sh |
| `templates/pos-tool.sh` | Documented POS_SUBCMDS, POS_DEPS, POS_EXAMPLES headers |
| `install.sh` | Added `registry.sh` to lib_names array |
| `DOC/DEV.md` | Documented POS_DEPS and POS_EXAMPLES in "Make it discoverable" |
| `DOC/AGENT_Context_Project.md` | Added lib/registry.sh row to hand-maintained line-count table; gen blocks updated |

### Files NOT Modified (scope compliance)

- `bin/pos` — dispatcher logic untouched ✅
- `completions/pos.bash` — no changes needed ✅
- `lib/config-ui.sh` — not integrated with registry ✅
- No `# POS_DEPS:` or `# POS_EXAMPLES:` added to existing tools ✅

### Prerequisite Commits

1. `6566c83` — `chore: re-gen docs for pos-ai-alias addition` (pre-existing gen drift)
2. `5d7407e` — `chore: update docmap + filetable for registry.sh addition` (gen output for my changes)

### Pre-existing Issues (not in scope)

- `bin/pos-ai-alias`: FAIL — reads stdin but not in `INTERACTIVE_CMDS`
- `bin/pos-ai-alias`: WARN — not referenced in `DOC/POS.md`
