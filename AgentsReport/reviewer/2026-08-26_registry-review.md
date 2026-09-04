# Reviewer Report — Self-Describing Command Registry for POS

**Date:** 2026-08-26
**Status:** ACCEPT_WITH_NOTES

---

## TL;DR

The implementation is well-structured, internally consistent, and correctly scoped. One REQUIRED finding (documentation gap in `AGENT_Context_Project.md` installation flow) and two SUGGESTED findings remain. No BLOCKING issues. Gates could not be re-run in this sandbox; the builder's claims about gate results are plausible but UNVERIFIED by this review.

---

## Gate Results

| Gate | Builder Claimed | Reviewer Verified | Notes |
|------|----------------|-------------------|-------|
| `bash -n lib/registry.sh` | PASS | UNVERIFIED | Sandbox blocks execution; code inspection shows no syntax issues |
| `bash -n scripts/gen-docs.sh` | PASS | UNVERIFIED | Sandbox blocks execution |
| `bash -n bin/pos-tree` | PASS | UNVERIFIED | Sandbox blocks execution |
| `make gen && git diff --exit-code` | PASS (zero drift) | STRONG INFERENCE | No tools have POS_DEPS/POS_EXAMPLES yet; gen_dispatch falls through to unchanged path; gen_tree only adds `[deps:]` when non-empty — both confirmed by code inspection |
| `make check` | PASS | UNVERIFIED | Sandbox blocks execution |
| `make lint` | 1 FAIL + 1 WARN (pre-existing) | UNVERIFIED | Builder cites pos-ai-alias issues, which are plausible given commit `9f289ba` |

---

## Findings

### Finding 1: Documentation gap — installation flow missing `registry.sh`

**Severity:** REQUIRED
**Certainty:** FACT

**Evidence:** `DOC/AGENT_Context_Project.md:211-213` lists the libs copied by Phase 2:
```
│   └─ Copies lib/*.sh (common, flags, notify, entertainment-lib,
│      scheduler-lib, config-ui, user-timers-lib, entertainment-plugin-lib,
│      usb-lib, share-lib, menu-lib) → /usr/local/bin/ (chmod 644)
```
This list does NOT include `registry.sh`. However, `install.sh:143` correctly includes `registry.sh` in the `lib_names` array. The `DEV.md` "Directory Layout" table at line 34 also does not mention `registry.sh` in its lib directory description.

**Relevant files/lines:** `DOC/AGENT_Context_Project.md:211-213`, `DOC/DEV.md:34`
**Approved scope reference:** Arch Decision 5 approved "DOC/AGENT_Context_Project.md — Update line count table for lib/registry.sh"
**Why it matters:** The installation flow description is a hand-maintained doc section. A new library was added to the install pipeline, but the description wasn't updated to reflect it. This creates documentation drift — the next agent reading this section would not know registry.sh is installed.

**Fix:** Add `registry` to the lib list on line 213 of AGENT_Context_Project.md and to the `lib/` directory description in DEV.md line 34.

---

### Finding 2: `gen-docs.sh` header comment not updated for new headers

**Severity:** SUGGESTED
**Certainty:** FACT

**Evidence:** `scripts/gen-docs.sh:8-12` documents the source-of-truth headers:
```bash
# Sources of truth:
#   - bin/pos-* filenames  → category, subcommand
#   - "# POS:" header line → one-line description
#   - "# POS_FLAGS:" line  → flag completion list (flag-style tools only)
#   - "# POS_SUBCMDS:" line → subcommand completion list (multi-command tools)
```
Missing: `# POS_DEPS:` and `# POS_EXAMPLES:` are parsed at lines 45-46 but not documented in the header comment.

**Relevant files/lines:** `scripts/gen-docs.sh:8-12`
**Why it matters:** The header comment is the first thing a developer reads when modifying the script. Omitting the new headers from the "Sources of truth" list could cause confusion.

---

### Finding 3: `AGENT_Context_Project.md` §4 "Available Commands" dispatch table lacks header row

**Severity:** NOTE
**Certainty:** HYPOTHESIS

**Evidence:** When `_has_deps_examples=0`, `gen_dispatch()` (gen-docs.sh:88-93) outputs only data rows, no markdown table header. The committed dispatch block at `AGENT_Context_Project.md:273-315` also has no header row — the table starts directly with data rows. This means the dispatch table is a list of pipe-separated values rendered by GitHub/Gitea markdown as a table, but it technically lacks `|---|---|` separator lines.

**Why it matters:** This is pre-existing behavior, not introduced by this change. Noted for completeness. The architect's spec also shows no header rows in the dispatch table example. Markdown renderers may handle this gracefully, but strict parsers would not.

---

### Finding 4: Architect pseudocode key format ≠ implementation (resolves correctly)

**Severity:** NOTE
**Certainty:** FACT

**Evidence:** The architect's pseudocode in `architect/2026-08-26_registry-architecture.md:272` uses `key="$sub"` (sub-only key, e.g., `download` for `pos-network-download`). The actual implementation at `lib/registry.sh:70` uses `key="$name"` (full key after `pos-`, e.g., `network-download`). However, the architect's "Tool Key Convention" section (lines 142-147) specifies `network-download` as the key — matching the implementation. The builder correctly followed the convention, not the pseudocode bug.

**Why it matters:** Not a defect, but the pseudocode and convention section of the same document contradict each other. Future reference to the pseudocode could cause confusion.

---

### Finding 5: Gate results not independently verifiable

**Severity:** NOTE
**Certainty:** UNVERIFIED

**Evidence:** The sandbox environment blocks `bash -n`, `make gen`, `make check`, `make lint`, and any non-read-only bash commands. The builder's report claims all gates pass, and the code inspection supports these claims being plausible (no syntax errors visible, gen_dispatch backward-compatible when no tools have new headers, etc.). However, I cannot independently confirm them.

**Why it matters:** The Orchestrator should run the gates before accepting. The builder's claims are well-documented but technically unverified by this review.

---

## Scope Compliance

### In-Scope Items (all verified present in working tree)

| Item | Status | Evidence |
|------|--------|----------|
| `lib/registry.sh` — new file (199 lines) | ✅ PRESENT | `git status --short` shows `?? lib/registry.sh` |
| `scripts/gen-docs.sh` — extended tools array, conditional columns, deps annotation | ✅ MODIFIED | `git diff HEAD -- scripts/gen-docs.sh` shows all expected changes |
| `bin/pos-tree` — migrated to registry API | ✅ MODIFIED | `git diff HEAD -- bin/pos-tree` shows sed→registry migration |
| `templates/pos-tool.sh` — documented new headers | ✅ MODIFIED | `git diff HEAD -- templates/pos-tool.sh` adds POS_DEPS/POS_EXAMPLES docs |
| `install.sh` — added registry.sh to lib_names | ✅ MODIFIED | `git diff HEAD -- install.sh` shows registry.sh added to loop |
| `DOC/DEV.md` — documented POS_DEPS and POS_EXAMPLES | ✅ MODIFIED | `git diff HEAD -- DOC/DEV.md` shows header docs and explanation |
| `DOC/AGENT_Context_Project.md` — registry.sh in line-count table | ✅ MODIFIED | `git diff HEAD~1..HEAD` shows new row at line 594 |

### Out-of-Scope Items (verified NOT modified)

| Item | Status | Evidence |
|------|--------|----------|
| `bin/pos` dispatcher logic | ✅ NOT MODIFIED | Not in `git status --short` |
| `completions/pos.bash` | ✅ NOT MODIFIED | Not in `git status --short` |
| `lib/config-ui.sh` | ✅ NOT MODIFIED | Not in `git status --short` |
| `# POS_DEPS:` / `# POS_EXAMPLES:` on existing tools | ✅ NOT ADDED | `grep -c 'POS_DEPS:' bin/pos-*` → 0 |
| `scripts/lint-conventions.sh` | ✅ NOT MODIFIED | Not in `git status --short` (was optional in scope) |

### Scope Deviation

The architect's approved scope stated "install.sh changes — registry.sh is installed with existing lib/* loop" (Decision 5, "Not in scope"). The builder correctly identified that the `lib_names` loop lists files explicitly (not a glob), requiring an explicit addition. The `install.sh` modification was **necessary and correct** — the architect's scope was slightly inaccurate on this point.

---

## Verification Verified

1. **API function completeness:** All 10 declared API functions (`reg_scan`, `reg_list`, `reg_categories`, `reg_tools_in`, `reg_lookup`, `reg_config_scopes`, `reg_config_keys`, `reg_config_envfile`, `reg_each`, `reg_tool_exists`) are implemented in `lib/registry.sh`. (Lines 48, 129, 131, 150, 158, 172, 174, 179, 189, 197) — **FACT**

2. **No shebang:** `lib/registry.sh` has no shebang line — starts with a comment. — **FACT** (line 1)

3. **LC_ALL=C in reg_scan:** Set at line 51, restored at lines 121-125 (with save/restore pattern). — **FACT**

4. **Guarded fallbacks:** `log`, `warn`, `err` use the `declare -F` pattern matching `lib/config-ui.sh` at lines 19-21. — **FACT**

5. **pos-tree sources registry.sh:** Line 7 of `bin/pos-tree` adds the source line with fallback chain. — **FACT**

6. **pos-tree uses registry API:** Lines 48-74 replace direct sed with `reg_scan`/`reg_list`/`reg_lookup`. `add()` and `render()` are unchanged. — **FACT**

7. **gen-docs.sh backward compatibility:** When `_has_deps_examples=0` (which is true since no tools have POS_DEPS/POS_EXAMPLES):
   - `gen_dispatch()` falls to `else` branch (lines 88-93) producing identical `| cat | sub | script | desc |` format — **FACT** (code inspection)
   - `gen_tree()` only adds `[deps:]` annotation when `deps` is non-empty (lines 73-75) — **FACT** (code inspection)

8. **Key format consistency:** Registry key = `"${f##*/pos-}"` (line 68-70 of registry.sh), same as pos-tree's old `name="${f##*/pos-}"`. Consumer pos-tree passes `tool_key` directly to `reg_lookup` — consistent. — **FACT**

9. **Templates documentation:** `templates/pos-tool.sh:12-14` documents `POS_SUBCMDS`, `POS_DEPS`, `POS_EXAMPLES`. — **FACT**

10. **install.sh lib_names:** Line 143 includes `registry.sh` in the for loop. — **FACT**

---

## Verification Unverified

1. **`bash -n` for all three scripts** — sandbox blocks execution.
2. **`make gen && git diff --exit-code`** — strongly inferred (code logic supports it) but not executed.
3. **`make check` and `make lint`** — sandbox blocks execution.
4. **Runtime registry API test** (`source lib/registry.sh; reg_scan; reg_list | wc -l`) — sandbox blocks.
5. **`bin/pos-tree` output byte-identical to previous version** — builder claims `diff` is empty; code inspection supports this (registry provides same data, key format matches), but cannot verify.
6. **`bin/pos docker --help` and `bin/pos network --help` still work** — no code changes to `bin/pos`, so likely fine, but unverified.

---

## Risk Assessment

### Edge Cases in Header Parsing

1. **Tool with no `# POS:` header:** `sed` returns empty; `_reg_desc` stores empty string. `reg_tool_exists` uses `${_reg_desc[$1]+x}` which is false for empty — tool would not be "found" by `reg_tool_exists`. However, `reg_list` would still include it (it's in `_reg_tools` from the filename). **Minor inconsistency** between `reg_tool_exists` (checks `_reg_desc`) and `reg_list` (includes all executable pos-* files). **Severity: LOW** — unlikely to matter since all pos-* files in the repo have `# POS:` headers.

2. **Empty tool directory:** `_reg_tools_dir` fallback works (line 26-34). `reg_scan` with empty glob `"$dir"/pos-*` would expand to literal `pos-*` if `nullglob` is off — the for loop body would fail on the first non-existent file. **Severity: LOW** — `_reg_tools` would be empty (the `[ -x "$f" ] || continue` guard on line 67 protects against this).

3. **Sourcing registry.sh multiple times:** Re-sourcing re-declares arrays (idempotent `declare`) and redefines functions (harmless overwrite). **No conflict.**

### `_reg_tools_dir` vs `$self` in pos-tree

`pos-tree` passes `$self` (the tool's directory) to `reg_scan`, bypassing `_reg_tools_dir`. This is correct — `_reg_tools_dir` is only used when `reg_scan` is called without arguments (future consumers).

---

## Verdict

**ACCEPT_WITH_NOTES**

The implementation is correct, well-scoped, and internally consistent. The REQUIRED finding (documentation gap in installation flow) should be fixed before final acceptance. The two SUGGESTED findings are non-blocking. Gate results are plausible but could not be independently verified — the Orchestrator should run the gates before closing.

**Defect count:**
- REQUIRED: 1 (documentation gap)
- SUGGESTED: 2 (header comment, pseudocode inconsistency)
- NOTE: 3 (dispatch table format, key format discrepancy, edge cases)
- BLOCKING: 0

---

## Handoff

**Recommended next agent:** Builder

**Reason:** One REQUIRED documentation fix needed (Finding 1: add `registry` to the installation flow lib list in AGENT_Context_Project.md and the lib directory description in DEV.md). This is a trivial 2-line change within the approved scope.

**Changes made by Reviewer:** none (read-only)
