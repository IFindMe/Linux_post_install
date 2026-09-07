# Alias Menu Abort — Fix Design (2026-09-06)

## TL;DR

- **Decision 1 (chosen):** Add an opt-in `--allow-empty` flag to `lib/menu-lib.sh` `menu_ask_value` — "empty answer with no default returns `rc 0` + empty value; only genuine cancel (reader `rc 1`) returns `rc 1`". Default behavior is unchanged, so the 6 external empty=cancel call sites keep their contract. **This is Option A.**
- **Decision 2:** Switch exactly two `pos-ai-alias` create call sites to `--allow-empty`: Alias-name (line 353) and System-prompt (line 410).
- **Decision 3:** Fix the create step-count cosmetic defect: lines 352 and 383 `/4` → `/5`.
- **Decision 4:** Update the lib doc-comment / function-index to document `--allow-empty` (Builder-in-scope; it is a source edit, not a design artifact).
- **Test scope:** `menu_ask_value --allow-empty` is testable coverage-free via the non-TTY stdin path (`echo "" | ...`); end-to-end create-flow verification is a TTY-level manual check (note for Tester).
- **Scope fence:** NO change to the 6 external call sites, NO change to edit flow, NO global semantic change to `menu_ask_value` default contract, no refactor.

---

## Decision 1: Add opt-in `--allow-empty` to `menu_ask_value` `[DECIDED]`

**Problem solved:** The reader (`menu_read_value`) already distinguishes empty (`rc 0` + empty) from genuine cancel/EOF (`rc 1`). `menu_ask_value` collapses empty-with-no-default into `rc 1`. Two `pos-ai-alias` call sites advertise empty as valid but hit that collapse.

**Option evaluated (A chosen):** add `menu_ask_value [--allow-empty] <label> [default]`.

**Option B (local workaround) — rejected:**
- A local re-implementation (e.g. call `menu_read_value` directly + replicate the default-resolution) **duplicates lib logic** (`menu_ask_value` lines 351-361) and risks divergence when the lib evolves.
- A sentinel default + caller-side mapping is **fragile** (some impossible-to-type sentinel must be picked, mapped back, and could still theoretically be typed) and unreadable.
- **Does not scale:** the next tool needing empty-valid would re-invent it; the flag exists once in the lib and every future caller reuses it.
- Neither preserves the alias-name re-prompt UX as cleanly.

**Rationale for A:**
1. **Backward compatible:** default contract (empty + no default → `rc 1`) is untouched for all existing callers — `--allow-empty` only widens behavior for callers that opt in. Satisfies the hard constraint (6 external empty=cancel sites unaffected).
2. **Minimal surface:** one keyword param, two lines of parse, one line of behavior. Not a refactor.
3. **Preserves the cancel/empty distinction:** genuine cancel still returns `rc 1` even with the flag; only empty-answer-with-no-default flips to `rc 0`.
4. **Scales:** standard opt-in shape; `menu_ask_value` currently has no flags, so this defines the cleanest minimal first flag (leading keyword, parsed before the positional label — no ambiguity since no call site's label equals `--allow-empty`).
5. **Matches intended UX:** the alias-name re-prompt (dead at line 355 today) becomes reachable; the system-prompt "use built-in" promise becomes true.

### Exact interface spec (lib/menu-lib.sh)

Signature:
```bash
menu_ask_value [--allow-empty] <label> [default]
```

- `--allow-empty` is an optional leading keyword flag. When present it is consumed and shifted before parsing `<label>`/`[default]` positionals.
- Behavior table:

| input | no flag | `--allow-empty` |
|-------|---------|-----------------|
| reader rc 1 (cancel/EOF/Ctrl-C) | rc 1 | rc 1 (unchanged — cancel stays cancel) |
| empty value, default present | rc 0, echo default | rc 0, echo default (default still wins) |
| empty value, no default | rc 1 (unchanged) | **rc 0, echo empty** |
| non-empty value | rc 0, echo value | rc 0, echo value |

- `--allow-empty` only widens the empty+no-default cell; it never suppresses the default and never converts genuine cancel.
- Doc-comment updates required in the same file:
  - Function index line 27: `menu_ask_value <label> [default]` → `menu_ask_value [--allow-empty] <label> [default]`.
  - Function doc block (lines 344-349): add a line documenting `--allow-empty` with the exact semantics above (empty+no-default → rc 0 empty; cancel still rc 1).

Reference implementation (approval shape — Builder reproduces this exactly):
```bash
menu_ask_value() {
    local allow_empty=0
    if [ "${1:-}" = "--allow-empty" ]; then
        allow_empty=1
        shift
    fi
    local label="$1" def="${2:-}" val pr="$1"
    [ -n "$def" ] && pr="$pr [$def]"
    if ! val="$(menu_read_value "$pr")"; then
        return 1                          # EOF / cancel
    fi
    if [ -z "$val" ]; then
        [ -n "$def" ] && { echo "$def"; return 0; }
        [ "$allow_empty" -eq 1 ] || return 1
        echo ""
        return 0
    fi
    echo "$val"
}
```

**[DECIDED]**

---

## Decision 2: Switch exactly 2 call sites to `--allow-empty` `[DECIDED]`

Only the two class-a (empty advertised as valid) defunct sites get the flag. All other 12 call sites across the repo stay byte-identical.

### bin/pos-ai-alias line 353 (Alias name)
From:
```bash
        name="$(menu_ask_value "Alias name" "")" || return 0
```
To:
```bash
        name="$(menu_ask_value --allow-empty "Alias name" "")" || return 0
```
Behavior after the change:
- Genuine cancel (Ctrl-C/EOF, reader rc 1) → `menu_ask_value` rc 1 → `|| return 0` → **abort to menu** (correct; unchanged).
- Empty Enter → `menu_ask_value` rc 0 + `""` → `name=""` → line 355 `[ -z "$name" ]` fires → `warn "Alias name cannot be empty"` → `continue` → re-prompt (the intended UX, now reachable). **The re-prompt loop is preserved by design.**
- Non-empty / valid / collision cases: unchanged.

### bin/pos-ai-alias line 410 (System prompt)
From:
```bash
        prompt="$(menu_ask_value "System prompt (empty = use built-in)" "")" || return 0
```
To:
```bash
        prompt="$(menu_ask_value --allow-empty "System prompt (empty = use built-in)" "")" || return 0
```
Behavior:
- Genuine cancel → rc 1 → `|| return 0` → **abort to menu** (correct; unchanged — cancel still exits the create flow).
- Empty Enter → rc 0 + `""` → `prompt=""` → passes the `|` check (empty has no `|`) → breaks → **proceeds with built-in prompt**. The UI text "(empty = use built-in)" now means what it says.
- Non-empty prompt: unchanged (validation/truncate/continuation identical).

No change to lines 397, 433 (create) or the edit-flow sites (538, 557, 585) — those are correct today.

**[DECIDED]**

---

## Decision 3: Fix create step-counter 352/383 `/4` → `/5` `[DECIDED]`

Create flow has 5 steps (Alias Name `352`, Provider `383`, Session `396`, Prompt `409`, Trust `424`), and lines 396/409/424 already print `/5`. Only 352 (`step 1 4`) and 383 (`step 2 4`) are stale. Set both to `/5`.

No change to the edit flow — internally consistent at 4 (lines 520/537/556/581 all `/4`).

**[DECIDED]**

---

## Decision 4: Lib source edit (doc/comment) is Builder scope `[DECIDED]`

The doc-comment and function-index updates to `lib/menu-lib.sh` are ordinary source edits. They are part of the approved scope for Builder (decision 1 embedded them). They are NOT an Architect artifact — the architect report (this file) is the design record; the inline doc comment is implementation.

---

## Scope Fence

**Approved outcome:** `pos ai alias` create flow no longer silently aborts on an empty System Prompt; empty alias-name re-prompts with the warn; create step numbers are consistent (5/5).

**In-scope components/files:**
- `lib/menu-lib.sh` — add `--allow-empty` flag + update doc-comment and function index.
- `bin/pos-ai-alias` — lines 352, 353, 383, 410.

**Allowed interface changes:**
- `menu_ask_value` gains optional leading `--allow-empty` (additive; no positional or rc semantics change for existing callers).
- `bin/pos-ai-alias` call sites 353/410 pass `--allow-empty`; step counters 352/383 → `/5`.

**Allowed behavior changes:**
- Empty System Prompt → proceeds (built-in), instead of aborting.
- Empty Alias Name → warn + re-prompt (was dead/unreachable code).
- Create step numbers 1 and 2 display `/5`.

**Required compatibility (untouched — must remain byte-identical):**
- All 6 external `menu_ask_value` call sites: `pos-system-backup:231`, `pos-media-sync:67`, `pos-network-download:1001/1027`, `pos-docker-vbox:495/831`.
- All edit-flow call sites (538/557/585) and create 397/433.
- The default `menu_ask_value` contract (empty + no default → rc 1, no flag).
- Genuine cancel at 353/410 still aborts the create flow (`|| return 0` retained).

**Explicitly out of scope:**
- No global semantic change to `menu_ask_value`.
- No change to `menu_read_value`.
- No change to the edit flow.
- No refactor of `_alias_create`; the re-prompt loop structure at 350-380 is retained.
- No tests written by Architect/Builder (Tester scope, see below); no docs beyond the inline menu-lib.sh comment.

**Architectural constraints:**
- Keep change surface minimal (two flag switches + two counters + one lib flag).
- Preserve cancel/empty distinction end-to-end.
- UI text "(empty = use built-in)" must keep its meaning (empty proceeds with empty).

---

## Test scope (for Tester)

`menu_ask_value --allow-empty` is covered **without a TTY** via the shared non-TTY stdin path (Detective already proved `echo "" | menu_ask_value ...` exercises the exact `menu_ask_value` logic). Recommended coverage matrix:

- `echo "" | menu_ask_value --allow-empty "l" ""` → rc 0, output empty.
- `echo "" | menu_ask_value "l" ""` → rc 1 (regression: default contract unchanged).
- `echo "" | menu_ask_value --allow-empty "l" "def"` → rc 0, output `def` (default wins even with flag).
- `printf '' | menu_ask_value --allow-empty "l" ""` → rc 1 (genuine EOF still cancel).
- `printf 'xyz\n' | menu_ask_value --allow-empty "l" ""` → rc 0, output `xyz`.
- `echo "" | menu_ask_value "l" "def"` → rc 0, output `def` (regression).

Plus one **TTY-level manual check** (needs a real terminal): run `pos ai alias` create → leave System Prompt empty → expect it to proceed to the Trust step and create the alias with empty prompt (built-in); leave Alias Name empty → expect `warn "Alias name cannot be empty"` + re-prompt; press Ctrl-C on any step → expect clean abort to menu.

If a shared non-TTY repro harness exists under `tests/`, add the flag matrix there; otherwise the manual TTY note stands. This is Tester's domain — Architect fixes only scope, not the writing.

---

## Verification expected

1. `bash -n` on `lib/menu-lib.sh` and `bin/pos-ai-alias`.
2. `make gen && make check && make lint` (definition of done: check green, lint `0 FAIL, 0 WARN`) — required because `bin/pos-ai-alias` is touched.
3. Tester runs the `--allow-empty` matrix (above) and the TTY create-flow check.
4. Confirm `git diff --exit-code` clean after `make gen` (determinism gate).

**Open risks / residual:**
- None architectural. The only residual is the class-c edge (edit Session aborts if a stored session is empty), which create-flow line 404 prevents today — out of scope, documented by Detective.

---

## Handoff

```text
Status: DECISION_READY

Problem:
pos ai alias create silently aborts on empty "System prompt" (and empty alias-name
re-prompt is unreachable) because menu_ask_value collapses empty+no-default into
rc 1; plus cosmetic /4 vs /5 step numbers.

Decision:
(A) Add opt-in `--allow-empty` to lib/menu-lib.sh menu_ask_value (empty+no-default
→ rc 0 + empty; cancel still rc 1; default unchanged). (2) Switch pos-ai-alias 353
and 410 to the flag. (3) Fix step counters 352/383 → /5.

Reasoning:
Reader already distinguishes empty from cancel; the collapse happens only in
menu_ask_value. Flag is opt-in (backward compatible, 6 external empty=cancel callers
untouched), scales for future callers, and makes dead re-prompt code reachable.
Option B (local re-implementation / sentinel) duplicates lib logic, risks divergence,
and does not scale.

Ownership:
Builder — edits lib/menu-lib.sh (flag + doc) and bin/pos-ai-alias (2 switches + 2 counters).

Interfaces:
menu_ask_value gains optional leading `--allow-empty`. No positionals, default, or
rc semantics change for existing callers. pos-ai-alias internal behavior: empty
system prompt proceeds built-in; empty alias name re-prompts.

Approved scope:
lib/menu-lib.sh (flag + inline doc; function-index line 27); bin/pos-ai-alias
lines 352, 353, 383, 410.

Explicitly out of scope:
6 external call sites, all edit-flow sites, 397/433, menu_read_value, global semantic
change, refactor of _alias_create, alias-name cancel semantics (still aborts via || return 0).

Constraints:
No global menu_ask_value semantic change. Cancel still aborts at 353/410. Empty
systems-prompt proceeds; empty alias-name re-prompts with warn. Keep change surface minimal.

Verification:
bash -n on both files; make gen && make check && make lint (0 FAIL, 0 WARN); Tester
--allow-empty matrix + TTY create-flow check; git diff --exit-code clean after gen.

Risks:
None architectural. Residual class-c (edit Session on stored-empty) is out of scope
and today prevented by create (line 404).

Recommended next agent:
Builder

Reason:
Design and exact call-site/libeay changes are fully specified; Builder can implement
without making architectural decisions. Tester follows for the matrix + TTY check.

Architect changes:
AgentsReport/architect/2026-09-06_alias-menu-fix-design.md (this file) only.
```