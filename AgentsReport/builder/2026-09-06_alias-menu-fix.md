# Builder Report — Alias Menu Fix (2026-09-06)

## TL;DR
- **Status:** IMPLEMENTED
- **Files changed:** `lib/menu-lib.sh`, `bin/pos-ai-alias`, `AgentsReport/builder/2026-09-06_alias-menu-fix.md`
- **Verification:** bash -n OK; make gen ×2 (deterministic, no drift); make check OK; make lint 0 FAIL 0 WARN; functional smoke 7/7 pass.
- **Summary:** Added `--allow-empty` flag to `menu_ask_value`, switched 2 alias call sites (353, 410), fixed step counters 352/383 → /5.

---

## Step 1: Update function index line in lib/menu-lib.sh
Updated line 27: `menu_ask_value <label> [default]` → `menu_ask_value [--allow-empty] <label> [default]`.
[DONE]

## Step 2: Add --allow-empty documentation to menu_ask_value doc block
Added doc line (after line 349) documenting the flag: empty+no-default → rc 0 + empty value; only cancel/EOF returns rc 1.
[DONE]

## Step 3: Implement --allow-empty flag in menu_ask_value body
Implemented per architect reference (`--allow-empty` parsed as first arg, shift; empty branch: default→echo+rc 0; no default → allow_empty rc 0 echo empty / else rc 1; cancel always rc 1). Prompt label display unchanged (default suffix only when non-empty).
[DONE]

## Step 4: Fix step counters and add --allow-empty to pos-ai-alias call sites
- line 352: `step 1 4` → `step 1 5`
- line 353: added `--allow-empty` flag (kept `|| return 0`)
- line 383: `step 2 4` → `step 2 5`
- line 410: added `--allow-empty` flag (kept `|| return 0`)
[DONE]

## Step 5: Verification (bash -n, make gen, make check, make lint, functional smoke)
- `bash -n lib/menu-lib.sh` → OK; `bash -n bin/pos-ai-alias` → OK.
- `make gen` run twice → both write OK, no gen drift (git diff after gen shows ONLY the 2 source files, no generated blocks touched) → byte-identical on rerun = deterministic.
- `make check` → check-sync: OK.
- `make lint` → `0 FAIL, 0 WARN`.
- Functional smoke (non-TTY harness at /tmp/opencode/menu_smoke.sh, sources lib/menu-lib.sh):
  - empty-no-default no flag → rc 1 (contract unchanged) PASS
  - empty-no-default with flag → rc 0 + empty PASS
  - empty-with-default with flag → rc 0 + default (default wins) PASS
  - empty-with-default no flag → rc 0 + default PASS
  - non-empty with flag → rc 0 + value PASS
  - non-empty no flag → rc 0 + value PASS
  - EOF (no input) with flag → rc 1 (cancel stays cancel) PASS
  - TOTAL: 7 pass, 0 fail.
- Alias-name re-prompt reachability (static): line 353 now returns rc 0 + "" on empty Enter → line 355 `[ -z "$name" ]` fires → `warn "Alias name cannot be empty"` → `continue` → re-prompt (step 1 5 shown again); genuine cancel → rc 1 → `|| return 0` → abort to menu. Verified reachable by design; TTY-level end-to-end create-flow run is a Tester/manual check per Architect's note.
[DONE]

## Handoff
Status: IMPLEMENTED (see final message)
[DONE]
