# Detective Report — pos ai alias create: silent abort on empty System Prompt

- Date: 2026-09-06
- Scope: interactive UI failure in `pos ai alias` create flow (host `ciya` paste)
- HEAD: `0b5043a`
- Role: read-only investigation (no project files modified)

## TL;DR

The reported abort is **confirmed and reproducible**. In `_alias_create()` the
"System prompt (empty = use built-in)" step calls `menu_ask_value` with **no
default**, and `menu_ask_value` returns rc 1 for an *empty* answer when there is
no default (`lib/menu-lib.sh:357`). The caller's `|| return 0` (`bin/pos-ai-alias:410`)
then silently aborts to the menu — exactly the reported symptom. The Session step
worked because it passes a default (`$name`), so empty→default→rc 0→proceeded.

- **Root cause (FACT):** `bin/pos-ai-alias:410` invokes `menu_ask_value "System prompt (empty = use built-in)" ""` — an empty 2nd arg means *no default* — while the UI text explicitly advertises empty as valid ("use built-in"). Empty→`rc 1`→`|| return 0`→silent abort.
- **Blast radius:** 7 distinct `menu_ask_value` call sites in `pos-ai-alias`; 6 outside. Per-site classification is in the table below. Only `pos-ai-alias:353` and `:410` show class-a (empty advertised as valid → defect). The edit flow is **NOT** affected (its prompt step explicitly handles empty; see edit verdict).
- **Step-count defect (FACT):** create flow has 5 steps but lines `bin/pos-ai-alias:352,383` hardcode `/4` (should be `/5`), while 396/409/424 are `/5`. Introduced by commit `300b742a` (feat: alias trust flag) which bumped the total only on the lines it touched.
- **Provenance (FACT):** `pos-ai-alias` is byte-identical to HEAD; clean `git status`. Both defects are pre-existing, NOT regressions from the 2026-09-06 stabilization commits (`d817c37`, `0b5043a` which only touched `pos-network-download`/`pos-system-backup`, not these call sites).
- **Fix constraint:** the `menu_ask_value` "empty + no default → cancel" contract must be preserved (6+ callers rely on it). The fix must be **local/opt-in** in `pos-ai-alias` (e.g. treat empty as valid where the UI says so, or pass a sentinel default / use a `menu_ask_value` opt-in variant), never a global semantic change.

Report path (this file):
`AgentsReport/detective/2026-09-06_alias-menu-abort.md`

---

## Step 1: Trace the abort path (Task A) `[DONE]`

### menu_ask_value contract (`lib/menu-lib.sh:344-362`)
```
350 menu_ask_value() {
351   local label="$1" def="${2:-}" val pr="$1"
352   [ -n "$def" ] && pr="$pr [$def]"
353   if ! val="$(menu_read_value "$pr")"; then
354     return 1                          # EOF / cancel
355   fi
356   if [ -z "$val" ]; then
357     [ -n "$def" ] || return 1          # <-- empty + no default => rc 1
358     echo "$def"
359     return 0
360   fi
361   echo "$val"
362 }
```
The documented contract at line 349 says: `rc 0 value on stdout · rc 1 EOF/cancel,
or empty answer with no default`. This is exactly the `f61766b0` lineage (the
empty-no-default clause predates the 4306a53 paste-safe reader rewrite;
`4306a53` only swapped the `read -rp`/`menu_read_value` internals, leaving the
`menu_ask_value` empty clause untouched — see Step 5).

### menu_read_value (the reader, 4306a53+)
`menu_read_value` returns `rc 0 + ""` on a plain empty Enter (submit=1, empty
`val`, printed nothing), and `rc 1` only on genuine EOF / Ctrl-C/Z/\ / Ctrl-D-on-empty
(lines 272-280, 302-304). So **cancel vs empty is distinguishable at the reader level**
— it is `menu_ask_value` that deliberately collapses *empty-with-no-default* into
*rc 1*, folding it into the same code path as cancel.

### _alias_create callers (`bin/pos-ai-alias`)
- Line 410 (System Prompt): `prompt="$(menu_ask_value "System prompt (empty = use built-in)" "")" || return 0`
  - 2nd arg is `""` → `def` empty → **no default**.
  - UI text promises empty is valid ("use built-in").
  - empty → `rc 1` → `|| return 0` → **silent abort** to menu. ✔ matches paste.
- Line 397 (Session): `session="$(menu_ask_value "Session name" "$name")"` — passes default `$name` (non-empty for any valid name). empty→default→`rc 0`→proceeded. ✔ matches paste (session step proceeded).
- Line 353 (Alias name): `name="$(menu_ask_value "Alias name" "")" || return 0` — no default; empty→`rc 1`→abort. The loop's empty-name warn/re-prompt at line 355 is unreachable for the empty case.

### Empirical confirmation
The reader needs a TTY (stty raw mode). I drove a non-TTY fallback path (which
shares the exact `menu_ask_value` empty/no-default logic — `stty -g` fails → plain
`read` → `menu_ask_value` still hits line 357) to confirm the contract:

```
$ echo "" | menu_ask_value "System prompt (empty = use built-in)" ""
empty-no-default -> rc=1 out=<>
$ echo "" | menu_ask_value "Session name" "assist"
empty-with-default -> rc=0 out=<assist>
$ printf '' | menu_ask_value "Alias name" ""
EOF-no-default -> rc=1 out=<>
```

This deterministically reproduces the exact divergence: empty-with-default succeeds
(rc 0, default returned), empty-no-default aborts (rc 1). A full pty repro of the
raw-mode reader is possible (pty available) but adds no discriminating evidence
beyond this.

A note on the harness: a naive `prompt="$(menu_ask_value ...)"` under `set -e` in
the harness exits immediately on the rc-1 cmdsubst — itself a live demonstration
that the failing assignment is the abort point.

### Task A conclusion
Findings 1-2 **confirmed**. The report's abort path maps exactly to
`menu_read_value` returning empty (rc 0) on plain Enter, then `menu_ask_value`
returning 1 for empty-with-no-default, then `|| return 0` in `_alias_create`.

---

## Step 2: Blast radius — every caller of menu_ask_value (Task B) `[DONE]`

### pos-ai-alias (7 sites)
| line | code | class | evidence |
|------|------|-------|----------|
| 353 | `menu_ask_value "Alias name" ""` | **a (defect)** | UI "Alias name"; loop expects to re-prompt on empty (355 warn) but rc 1 short-circuits. Loop's empty-warn is dead code. |
| 397 | `menu_ask_value "Session name" "$name"` | ok | default `$name`; empty→default→rc 0. Correct. |
| 410 | `menu_ask_value "System prompt (empty = use built-in)" ""` | **a (defect)** | UI explicitly says empty valid; empty→rc 1→abort. **The reported bug.** |
| 433 | `menu_ask_value "Trust this alias? (y/N)" "N"` | ok | default `N`; empty→N→rc 0. Correct. |
| 538 | `menu_ask_value "Session name" "$new_session"` (edit) | c (edge) | default = current session. If a stored session were empty (shouldn't happen post-create, create defaults to `$name`), empty→rc 1→`return 0`→abort. Requires an empty-stored-session precondition. See edit verdict. |
| 557 | `menu_ask_value "System prompt" "$default_display"` (edit) | **handled** | edit explicitly guards: when `default_prompt` empty, line 560 sets `tmp_prompt=""` instead of aborting. No bug. |
| 585 | `menu_ask_value "Trust this alias? (y/N)" "$cur_trust_label"` (edit) | ok | default = current label, non-empty. Correct. |

### Outside pos-ai-alias (6 call sites, 4 files)
| file:line | code | class | evidence |
|-----------|------|-------|----------|
| pos-system-backup:231 | `menu_ask_value "Folder to back up"` (no default) | **b (cancel, correct)** | empty→rc 1→`return 0`; a real folder must be typed, or user backs out. `menu_backup_folder` returns 0 on empty. Correct today. |
| pos-media-sync:67 | `menu_ask_value "Source folder [current: $SRC]"` (no default; `$SRC` is in the **label**, not 2nd arg) | **b (cancel, correct)** | empty→rc 1→`return 0`; empty not a valid folder (checked at 68-70). Correct. |
| pos-network-download:949 | `menu_ask_value "$1" "N"` (menu_ask_yn, default N) | ok | empty→N→rc 0; rc 1 only genuine cancel. Correct. |
| pos-network-download:1001 | `menu_ask_value "URL to add (download dir: ...)" ` (no default) | **b (cancel, correct)** | empty→rc 1→`return 0`; line 1002 redundant `[ -n "$url" ] || return 0`. Empty means "back out". Correct. |
| pos-network-download:1027 | `menu_ask_value "Type purge to clear finished/error history"` (no default) | **b (cancel, correct)** | empty→rc 1→`return 0`; must literally type `purge`. Empty=cancel is intentional (must-type confirmation). Correct. |
| pos-docker-vbox:495 | `menu_ask_value "Image ref"` (no default) | **b (cancel, correct)** | comment 106-107: "empty answer and a dead stream are indistinguishable (menu_ask_value has no default there)". Typed-value add loop; empty = cancelled typing → back to picker. Intentional. |
| pos-docker-vbox:831 | `menu_ask_value "VM name"` (no default) | **b (cancel, correct)** | comment 107/828-830: empty answer intentionally tears down loudly with nothing created ("both rc 1 ... both take the loud teardown"). Intentional. |

### Blast-radius conclusion
Only `pos-ai-alias:353` and `:410` are class-a defects. The other 6 external call
sites and the remaining pos-ai-alias sites are correct by design (empty=cancel or
empty=default). **A global change to `menu_ask_value`'s empty-no-default semantics
would break at least these correct sites**: pos-system-backup:231,
pos-media-sync:67, pos-network-download:1001/1027, and both pos-docker-vbox sites
(explicitly documented). The fix must be local to `pos-ai-alias`.

---

## Step 3: Step-count defect + edit flow (Task C) `[DONE]`

### Create step numbering (`bin/pos-ai-alias`)
Confirmm via `grep -n 'step [0-9]'`:
```
352: step 1 4   (create Alias Name)
383: step 2 4   (create Provider)
396: step 3 5   (create Session)
409: step 4 5   (create Prompt)
424: step 5 5   (create Trust)
```
Create has **5 steps**, but lines 352/383 print `/4` while 396/409/424 print `/5`.
Confirms the cosmetic `[1/4] [2/4]` mismatch in the paste.

Introducing commit: `git blame` shows 352 = `9f289ba3`, 383 = `9f289ba3`,
396/424 = `300b742a`. `300b742a` ("feat: alias trust flag") added the Trust step
and set 396/409/424 to `/5` but **did not** update 352/383, leaving them at `/4`.

### Edit flow
`grep`:
```
520: step 1 4   (edit Provider)
537: step 2 4   (edit Session)
556: step 3 4   (edit Prompt)
581: step 4 4   (edit Trust)
```
Edit numbering is internally **consistent** (4 steps, all /4). No mis-numbering.

**Edit empty-input traps:** verified the edit Prompt step (556-573) explicitly
guards the empty-original-prompt case:
```
557 if ! tmp_prompt="$(menu_ask_value "System prompt" "$default_display")"; then
559   # EOF/cancel: empty-answer abort only when there IS a default;
560   # Enter on an empty original prompt keeps it empty and continues.
560   [ -z "$default_prompt" ] && tmp_prompt="" || return 0
```
So when the stored prompt is empty (`default_display` empty), empty Enter →
`tmp_prompt=""` → continues (no abort). When the stored prompt is non-empty,
empty Enter → returns the default (rc 0). **Edit prompt step has NO bug** — it is
the correct pattern the create flow's Step 4 should have used.

Minor/edge: edit Session step (538) aborts on empty Enter **only if the stored
session is empty**, which the create flow prevents (line 404 defaults session to
`$name`). Classified c (ambiguous/edge), low practical impact, no action required.

---

## Step 4: Provenance — byte-identical to HEAD, pre-existing (Task D) `[DONE]`

- `git status --short` → **clean** (empty). Working tree matches HEAD `0b5043a`.
- `git diff HEAD -- bin/pos-ai-alias lib/menu-lib.sh` → **empty**. No uncommitted edits.
- `git log --format=%H ... -- bin/pos-ai-alias` → 5 commits, all Aug 26-27 2026:
  `9f289ba` (feat: pos ai alias), `e969234`, `59935dc`, `300b742` (trust flag),
  `4306a5` (paste-safe reader). None are the 2026-09-06 stabilization commits.
- The 2026-09-06 commits `d817c37` and `0b5043a` touched `bin/pos-network-download`
  and `bin/pos-system-backup` **but not** any `menu_ask_value` call site in those
  files (their diffs contain no `menu_ask_value` additions/deletions/-context edits
  to those lines — verified by grepping the diffs). They never touched `pos-ai-alias`
  or `lib/menu-lib.sh`.
- **Introducing commit for both defects:**
  - `menu_ask_value` empty-no-default → rc 1 contract: **`f61766b0`** (Aug 24) in
    `lib/menu-lib.sh` (lines 356-357 unchanged since then; verified by blame).
  - The `pos-ai-alias` mis-use (empty advertised as valid + `|| return 0`) for
    step 4 and the alias-name step: **`9f289ba3`** (Aug 26) originally; the abort
    remains in tree to HEAD.
  - The create step-count (`/4` vs `/5`) mismatch: **`300b742a`** (Aug 27, trust flag).

**Verdict: pre-existing; NOT a regression from the 2026-09-06 stabilization/fix
commits.**

---

## Step 5: Fix constraints (Task E) `[DONE]`

A correct fix must preserve:
1. **Cancel vs empty must remain distinguishable.** The reader already
   distinguishes them (Ctrl-D/EOF/Ctrl-C → rc 1; plain Enter → rc 0 + empty). The
   semantic collapse happens *only* in `menu_ask_value` (empty-no-default → rc 1).
   The fix must not blur this line.
2. **The 6 external callers relying on empty=cancel must keep that behavior:**
   pos-system-backup:231, pos-media-sync:67, pos-network-download:1001/1027 and
   both pos-docker-vbox sites (documented comments 106-107 and 828-830).
3. **No global semantic change to `menu_ask_value`** default contract ("empty with
   no default = rc 1"). Any change there ripples to the correct callers above.
4. **The fix must be local/opt-in to `pos-ai-alias`:** at lines 353 and 410, the
   UI explicitly advertises empty as valid, so empty must proceed as an empty
   value instead of aborting. Candidate shapes for Builder (not decided here —
   implementation is out of the Detective's read-only scope): pass a sentinel
   default, add an opt-in `menu_ask_value` flag to keep empty, or restructure the
   `|| return 0` into `|| if cancel then return; else continue with empty`.
5. **Step-count fix (create):** lines 352/383 `/4` → `/5` to match the 5-step flow
   (edit is already consistent at 4).
6. Whatever the fix, the edit-flow Pattern (empty-with-default guard, lines
   557-560) shows the codebase's intended way to handle optional-input prompts.

---

## Confirmed Root Cause Statements

**ROOT CAUSE (FACT):** In `_alias_create()`, the "System prompt (empty = use
built-in)" step (`bin/pos-ai-alias:410`) calls `menu_ask_value` with an empty
second argument (no default), and the shared helper `lib/menu-lib.sh:356-357`
returns **rc 1** for an empty answer when there is no default — conflating
"user typed nothing" with "user cancelled". The caller's `|| return 0`
(`bin/pos-ai-alias:410`) then silently aborts the create flow back to the menu with
no alias created. The same latent trap exists at `bin/pos-ai-alias:353` (alias
name), where the loop's empty-name warn/re-prompt (`:355`) is dead/unreachable; the
UI at both 353 and 410 explicitly advertises empty as acceptable ("use built-in").

**Related defect (FACT):** create-flow step numbering is inconsistent — line 352
and 383 print `/4` while lines 396/409/424 print `/5`, so the wizard shows
`[1/4] [2/4] [3/5] [4/5] [5/5]` for its 5 steps.

**Provenance (FACT):** pre-existing (not a 2026-09-06 stabilization regression);
`pos-ai-alias` is byte-identical to HEAD on a clean tree. Introducing commits:
`9f289ba3` (abort mis-use), `300b742a` (step-count mismatch), with the `menu_ask_value`
empty-no-default contract from `f61766b0`.

## Blast Radius Table

| caller | line | class | evidence |
|--------|------|-------|----------|
| pos-ai-alias create Alias name | 353 | **a (defect)** | empty advertised in flow; loop warn (355) unreachable |
| pos-ai-alias create Session | 397 | ok | default `$name`; empty→default→rc 0 |
| pos-ai-alias create Prompt | 410 | **a (defect — reported)** | UI "(empty = use built-in)" is valid; aborts |
| pos-ai-alias create Trust | 433 | ok | default N |
| pos-ai-alias edit Session | 538 | c (edge) | aborts only if stored session empty (prevented by create) |
| pos-ai-alias edit Prompt | 557 | handled | explicit empty guard at 560 |
| pos-ai-alias edit Trust | 585 | ok | default = current label |
| pos-system-backup Folder | 231 | **b (cancel, keep)** | empty must not be a folder; empty=cancel correct |
| pos-media-sync Source | 67 | **b (cancel, keep)** | label carries `$SRC`, not a default; empty=cancel correct |
| pos-network-download menu_ask_yn | 949 | ok | default N |
| pos-network-download add URL | 1001 | **b (cancel, keep)** | empty→rc 1→return 0; redundant 1002 guard |
| pos-network-download purge | 1027 | **b (cancel, keep)** | must type `purge`; empty=cancel intentional |
| pos-docker-vbox image ref | 495 | **b (cancel, keep)** | comments 106-107; empty=cancel intentional |
| pos-docker-vbox VM name | 831 | **b (cancel, keep)** | comments 107, 828-830; empty→loud teardown intentional |

## Step-Count Verdict

Create flow is 5 steps but prints `/4` on steps 1-2 (353/383). Edit flow is
internally consistent at 4. Introduced by `300b742a`.

## Edit-Flow Verdict

No bug: edit Prompt (557-560) explicitly handles the empty-original-prompt case
and empty-with-default correctly; edit numbering is consistent. Only theoretical
edge is a stored-empty session, prevented by create (404) and class-c.

## Provenance Verdict

Pre-existing. Clean tree, byte-identical to HEAD. Not a 2026-09-06 regression.
Introducing commits: `f61766b0` (contract), `9f289ba3` (abort mis-use),
`300b742a` (step-count + trust step).

## Fix Constraints

1. Preserve cancel-vs-empty distinction (reader already separates them; do not
   blur).
2. Preserve empty=cancel for the 6 external call sites (pos-system-backup:231,
   pos-media-sync:67, pos-network-download:1001/1027, pos-docker-vbox:495/831 —
   two explicitly documented).
3. NO global semantic change to `menu_ask_value`'s empty-no-default→rc 1 contract.
4. Fix local/opt-in to `pos-ai-alias` 353/410: empty must be accepted as an empty
   value where the UI says it's valid.
5. Fix create step numbering: 352/383 → `/5`.
6. Follow the edit-flow pattern (empty-with-default guard) as the codebase's
   intended shape for optional-input prompts.

## Handoff

```
Status: ROOT_CAUSE_ESTABLISHED

Symptom: pos ai alias create aborts back to menu after the empty "System prompt"
         step — no [5/5] trust step, no confirmation, no alias created; with a
         cosmetic [1/4] [2/4] vs [3/5]-[5/5] step count.

Expected: empty system prompt (advertised "use built-in") proceeds to the trust
          step and creates the alias with an empty prompt.

Actual: empty + no default → menu_ask_value rc 1 → `|| return 0` → silent abort.

Root cause: lib/menu-lib.sh:356-357 returns rc 1 for empty-with-no-default,
            collapsing "empty" into "cancel"; bin/pos-ai-alias:410 (and 353)
            advertise empty as valid but pass no default, and the `|| return 0`
            converts rc 1 into a silent abort.

Classification: FACT

Evidence: code trace (menu-lib.sh:344-362; pos-ai-alias:344-467) + deterministic
          non-TTY repro (empty-no-default→rc 1; empty-with-default→rc 0 default);
          clean HEAD tree; git blame provenance.

Tests performed: menu_ask_value empty/EOF/with-default matrix; created/edit flow
                 step numbering; provenance (git status/diff/blame, stabilization
                 commit diffs).

Alternatives eliminated: not a reader (menu_read_value) bug — reader distinguishes
          empty(rc 0) from cancel(rc 1); not a global menu_ask_value bug needing
          semantic change — 6 external callers rely on empty=cancel; not a
          2026-09-06 regression — those commits didn't touch these lines.

Affected components: bin/pos-ai-alias (create 353/410; step numbers 352/383);
                     lib/menu-lib.sh (contract, no change needed).

Scope / decision boundary: implementation of the fix (how to make 353/410
          opts accept empty) is Builder territory; whether to add an opt-in
          menu_ask_value variant or a sentinel is an implementation decision.

Recommended next agent: Builder

Reason: root cause and blast radius are established; a local, opt-in fix in
        pos-ai-alias is understood and within approved scope, preserving the
        empty=cancel contract for the 6 external callers.

Changes made by Detective: none (read-only).
```
