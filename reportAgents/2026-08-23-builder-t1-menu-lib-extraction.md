# Builder Report — T1: Extract category-neutral menu primitives into `lib/menu-lib.sh`

## TL;DR
- Status: **IMPLEMENTED** — all gates green, behavior byte-stable.
- Files changed: `lib/menu-lib.sh` (new, 169 ln) · `lib/share-lib.sh` (436→318) · `install.sh` (+1 entry in explicit lib list) · `DOC/AGENT_Context_Project.md`, `DOC/DEV.md`, `DOC/SCRIPTS.md` (hand-maintained lib rows/sections).
- Verification: `bash -n` ✓ · `make gen` idempotent/no new drift ✓ · `make check` OK ✓ · `make lint` 0 FAIL 0 WARN ✓ · pty probes before/after byte-identical on all 5 cases ✓ · shim delegation asserted ✓.
- install.sh verdict: **needed the addition** — Phase-2 copies libs from an EXPLICIT list (install.sh:143), not a glob; `menu-lib.sh` appended (pre-authorized by brief).
- Zero edits to the five `bin/pos-share-*` tools and DOC/POS.md; no commits.

## Step 0: Scope confirmation + plan [DONE]
- Extraction set (per explorer survey :73–80): `share_menu_guard`→`menu_guard`, `share_menu_run`→`menu_run`, `share_pick`→`menu_pick`, `share_ask_value`→`menu_ask_value`. Everything else in share-lib stays (domain).
- Verified from source before touching anything:
  - The four functions use common.sh helpers only via `${CYAN}`/`${RESET}` (share_menu_run :56–58) — no log/warn/err/run/confirm calls. So menu-lib sources nothing; it gets guarded color fallbacks instead (repo idiom: common.sh:16–18 "standalone-sourced files keep an identical guarded copy").
  - Internal cross-call: none between the four except `share_menu_run` → `share_menu_guard` (:49) — rename-consistent inside menu-lib.
  - One domain helper calls into the extraction set: `share_smb_shares` uses `share_ask_value` (:300) — keeps working through the shim.
  - lib→lib sourcing precedent: scheduler-lib.sh:47–50 (4-way BASH_SOURCE/$0 fallback chain) — replicated for share-lib → menu-lib.
  - install.sh Phase-2 copies libs from an EXPLICIT list (install.sh:143) → `menu-lib.sh` must be added there (brief pre-authorizes this).
- Constraints honored: no edits to `bin/pos-share-*`; no commits; no behavior change (rc semantics preserved by 1:1 delegating shims).

## Step 1: BEFORE byte-baseline probes [DONE]
- Harness `/tmp/opencode/t1-probe/t1-probe.sh` (sources repo `lib/common.sh` + `lib/share-lib.sh`; cases: menu-run, menu-quit, guard-nontty, pick-filter, ask-default), pty runs via `script -qec`, logs in `/tmp/opencode/t1-probe/before/`.
- Results (all as-contracted):
  - `menu-run` ("2"): boxed menu → stderr, `STDOUT_INDEX=2 RC=0`
  - `menu-quit` ("q"): render then `STDOUT=[] RC=1`
  - `guard-nontty` (`< /dev/null`, no pty): `[!] Interactive menu needs a terminal — use a subcommand instead (see --help).` + `GUARD_RC=1`
  - `pick-filter` ("al","1"): `-- 1 of 3 match 'al' --` → `PICK_INDEX=1 RC=0` (index into FULL list)
  - `ask-default` ("" w/ default): `VALUE=[fallback] RC=0`
- These files are the byte-comparison baseline for Step 7 (before/after spot-check).

## Step 2: New lib/menu-lib.sh [DONE]
- Created `lib/menu-lib.sh` (~170 lines): header contracts + guarded color fallbacks (`CYAN="${CYAN:-}"; RESET="${RESET:-}"` — standalone-safe, sourced common.sh wins) + `menu_guard`/`menu_run`/`menu_pick`/`menu_ask_value`.
- Sources nothing (the four functions never used log/warn/err/run/confirm — only `${CYAN}`/`${RESET}`).
- Byte-stability proof: extracted each function body from old/new and diffed after reverse-renaming — 3 of 4 IDENTICAL; `menu_run` differs ONLY in the internal cross-call (`share_menu_guard` → `menu_guard`), which is the mandated rename consistency.

## Step 3: lib/share-lib.sh thin layer + shims [DONE]
- Removed the four function bodies; added the 4-way sourcing fallback chain (scheduler-lib.sh:47–50 precedent) + four 1:1 delegating shims (`lib/share-lib.sh:37–45`).
- Header updated: purpose line + function index now mark the four as shims → menu-lib. Domain section byte-untouched (old :165–436 == new :47–318, 272 lines).
- share-lib.sh: 436 → 318 lines. menu-lib.sh: 169 lines.
- `bash -n` green on both libs.

## Step 4: install.sh lib list [DONE]
- **Verdict: install.sh NEEDED the new lib added** — Phase 2 copies libs from an EXPLICIT list (`install.sh:143`), not a glob. `menu-lib.sh` appended after `share-lib.sh`; `bash -n install.sh` green.

## Step 5: Hand-maintained doc rows [DONE]
- `DOC/AGENT_Context_Project.md`: Installation-Flow Phase-2 prose (+`menu-lib`) · §13 Key File table: share-lib row updated (436→318 + description now "domain layer + compat shims") and new menu-lib row (169 lines) added after it.
- `DOC/DEV.md:34`: lib listing gains `menu-lib.sh` (category-neutral menu primitives); share-lib description corrected to domain probes/listings + compat shims.
- `DOC/SCRIPTS.md`: Phase-2 lib list (+`menu-lib.sh`) · share-lib section rewritten to domain role + shim note · new short `## lib/menu-lib.sh` section (mirrors the per-lib section convention).
- Finding vs brief assumption: the generated filetable contains NO lib rows at all (`gen-docs.sh` emits only pos-tool-derived blocks), so nothing lib-related appears via `make gen`; every spot above is hand-maintained.

## Step 6: Gates (bash -n, make gen/check/lint) [DONE]
- `bash -n lib/share-lib.sh lib/menu-lib.sh install.sh` — all green.
- `make gen` — write OK; re-ran and byte-compared the resulting `git diff` of both gen-target files: **idempotent, zero new drift** (expected — no `pos-*` file changed; the visible diff vs HEAD is the other track's pre-existing WIP staleness).
- `make check` — **OK**.
- `make lint` — **0 FAIL, 0 WARN**.

## Step 7: AFTER probes + before/after diff + shim assertions [DONE]
- Re-ran the identical harness post-change; **all five logs BYTE-IDENTICAL to before/** (`cmp` clean): menu-run (render + `STDOUT_INDEX=2 RC=0`), menu-quit (`q` → `STDOUT=[] RC=1`), guard-nontty (warning + rc 1), pick-filter (`-- 1 of 3 match 'al' --` → index into full list), ask-default (`VALUE=[fallback] RC=0`).
- Brief's named checks: (a) `share_menu_run` renders + returns chosen index ✓, `q` exits rc 1 ✓; (b) `menu_guard` (new name) under non-tty prints `[!] Interactive menu needs a terminal — use a subcommand instead (see --help).` + rc 1 ✓; (c) `share_pick` filter→select ✓.
- Shim delegation assertion — `declare -f` output:
  ```
  share_menu_run () { menu_run "$@"; }      # likewise share_menu_guard → menu_guard,
  share_ask_value () { menu_ask_value "$@"; }  # share_pick → menu_pick
  ```
- New names resolvable after sourcing only `share-lib.sh`: `declare -F` finds all four `menu_*` ✓. Before/after spot-check function: `share_menu_run` (byte-identical log = behavior identical pre/post).
- Temps cleaned (`/tmp/opencode/t1-probe/` removed).

## Final diff summary (this task only)
| File | Change |
|---|---|
| `lib/menu-lib.sh` | NEW · 169 lines (header contracts, guarded CYAN/RESET fallbacks, `menu_guard`/`menu_run`/`menu_pick`/`menu_ask_value`) |
| `lib/share-lib.sh` | 436 → 318 lines (−118): four bodies+their comment blocks out, header purpose/index updated, sourcing chain + 4 shims in (~13 new lines); domain section byte-untouched |
| `install.sh` | 1 line modified: Phase-2 explicit lib list += `menu-lib.sh` (:143) |
| `DOC/AGENT_Context_Project.md` | Phase-2 prose list += `menu-lib`; §13 table: share-lib row updated (436→318 + description), menu-lib row added (+1 line net) |
| `DOC/DEV.md` | lib listing row rewritten (+menu-lib.sh, share-lib described as domain+shims) |
| `DOC/SCRIPTS.md` | Phase-2 lib list += menu-lib.sh; share-lib section rewritten to domain role; new `## lib/menu-lib.sh` section (~+7 lines net) |
| `reportAgents/2026-08-23-builder-t1-menu-lib-extraction.md` | this report |

Note on `git diff` noise: HEAD is stale against the tree for several files (other track's uncommitted WIP — five `bin/pos-share-*`, docs, install.sh, untracked `lib/share-lib.sh`). The table above is MY complete change set; the five share tools were never opened for editing (zero edits).

## Scope compliance
- In-scope changes confirmed: exactly the brief's allowed set (new lib, share-lib, doc rows, install.sh explicit-list addition).
- Out-of-scope changes: none. No commits made. `bin/pos-share-*`, DOC/POS.md, preinstall.sh untouched.

## Remaining risks / notes for next agent
- `INTERACTIVE_CMDS`, dispatcher, completions: correctly unaffected (no tool surface changed).
- The six future P1/P2 consumers (designer Step 4) can now source `lib/menu-lib.sh` directly; they must add themselves to install.sh's lib chain via their own consumer sourcing (menu-lib is already installed).
- usb-server E-004 legacy prompts remain owned by the other track (untouched, per constraint).

REPORT_PATH: ./reportAgents/2026-08-23-builder-t1-menu-lib-extraction.md
