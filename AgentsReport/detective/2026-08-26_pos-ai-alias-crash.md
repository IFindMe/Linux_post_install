# Detective Report: `pos ai alias` Silent Crash

**Date:** 2026-08-26
**Symptom:** `pos ai alias` exits silently after user enters alias name in create flow
**Status:** ROOT_CAUSE_ESTABLISHED

---

## TL;DR

The `_alias_find` function returns exit code 1 when a name is not found (which is the normal/not-found case). This return code is captured in a variable assignment `existing="$(_alias_find "$name")"` under `set -euo pipefail`. On bash 5.2, `set -e` is NOT suppressed for command substitutions inside variable assignments, so the non-zero return code causes the script to exit immediately and silently.

**Root cause:** `bin/pos-ai-alias:103` — `_alias_find()` returns 1 when name is not found; combined with `set -e` at line 2.
**Bug is present at 4 call sites** — ALL of them crash when the name doesn't exist.
**Fix:** Make `_alias_find` always return 0 (the "not found" signal is the `-1` on stdout, not the exit code), or add `|| true` at each call site.

---

## Step 1: Reproduce the reported symptom

**Command:** `pos ai alias` → choose 1 → enter "assist"
**Result:** Script exits immediately after input. No step 2/4 header. No error message.

The tool silently returns to the shell prompt with no output beyond the alias name prompt.

---

## Step 2: Trace the create flow (static analysis)

File: `bin/pos-ai-alias`

| Line | Code | Analysis |
|------|------|----------|
| 208 | `name="$(menu_ask_value "Alias name" "")"` | ✅ Works correctly — user types "assist", captured on stdout, rc=0 |
| 210 | `[ -z "$name" ]` | ✅ False — name is "assist", no warning |
| 211 | `if ! _alias_name_valid "$name"` | ✅ Regex matches `assist`, validation passes |
| 215 | `_alias_load` | ✅ File doesn't exist → returns 0, arrays stay empty |
| **217** | **`existing="$(_alias_find "$name")"`** | **💥 CRASH — this is where the script dies** |
| 218 | `if [ "$existing" != "-1" ]; then` | Never reached |

---

## Step 3: Confirm root cause with controlled experiments

### Experiment 1: Isolated `set -e` + function return code

```bash
bash -c '
set -euo pipefail
f() { echo "-1"; return 1; }
x="$(f)"
echo "after: $x"
'
# Result: exits immediately. "after" never printed. EXIT CODE: 1
```

**Conclusion:** `set -e` in bash 5.2 does NOT suppress errexit for command substitutions inside variable assignments. A function returning 1 inside `x="$(f)"` triggers immediate script termination.

### Experiment 2: Same code without `set -e`

```bash
bash -c '
set -uo pipefail
alias_names=()
alias_find() { echo "-1"; return 1; }
existing="$(alias_find "test")"
echo "existing=$existing"
echo "DONE"
'
# Result: existing=-1, DONE printed. EXIT CODE: 0
```

**Conclusion:** Without `set -e`, the code works correctly.

### Experiment 3: Fix with `|| true`

```bash
bash -c '
set -euo pipefail
alias_names=()
alias_find() { echo "-1"; return 1; }
result="$(alias_find "assist" || true)"
echo "result=$result"
echo "DONE"
'
# Result: result=-1, DONE printed. EXIT CODE: 0
```

**Conclusion:** `|| true` inside the command substitution masks the non-zero return code and prevents `set -e` from firing.

### Experiment 4: Exact reproduction with real script logic

```bash
bash -c '
set -euo pipefail
name="assist"
# line 217 of pos-ai-alias
existing="$(_alias_find "$name")"
echo "existing=$existing"
' 2>&1
# EXIT: 1 — "existing" never printed
```

**Conclusion:** Crash confirmed with the exact code pattern from the source.

---

## Step 4: Identify ALL affected call sites

The `_alias_find` function is called at **4 locations** in `bin/pos-ai-alias`:

| Line | Function | Code | Crashes when? |
|------|----------|------|---------------|
| **217** | `_alias_create` | `existing="$(_alias_find "$name")"` | **New alias name (not yet in file)** — THIS IS THE REPORTED BUG |
| 139 | `_alias_show` | `idx="$(_alias_find "$1")"` | `pos ai alias show <nonexistent>` |
| 318 | `_alias_edit` | `idx="$(_alias_find "$name")"` | `pos ai alias edit <nonexistent>` (non-interactive preset) |
| 453 | `_alias_remove` | `idx="$(_alias_find "$name")"` | `pos ai alias remove <nonexistent>` (non-interactive preset) |

**All four are equally broken** — any path where the name isn't found triggers a silent crash.

---

## Step 5: Root cause analysis

### The bug

`bin/pos-ai-alias:94-104` — `_alias_find()`:

```bash
_alias_find() {
    local name="$1" i
    for ((i = 0; i < ${#_ALIAS_NAMES[@]}; i++)); do
        if [ "${_ALIAS_NAMES[$i]}" = "$name" ]; then
            echo "$i"
            return 0          # found → rc 0
        fi
    done
    echo "-1"                 # ← not-found signal on stdout
    return 1                  # ← PROBLEMATIC: rc 1 under set -e
}
```

The function uses **two** signals for "not found":
1. stdout: echo `-1` (the value callers check)
2. exit code: `return 1` (lethal under `set -e`)

When combined with `set -euo pipefail` (line 2) and captured in a variable assignment, bash 5.2 treats the non-zero exit code as fatal and terminates the script immediately.

### Why bash 5.2 matters

Historically, bash suppressed `set -e` for command substitutions inside variable assignments (`x=$(false)` was safe). Bash 5.1+ tightened this behavior to be more POSIX-compliant. On this system's **bash 5.2.37**, the suppression no longer applies, making `var=$(function_that_returns_1)` fatal under `set -e`.

### Why this is "silent"

`set -e` exits the script with the exit code of the failed command, but does NOT print any error message (there's no ERR trap configured). The user sees the prompt return with no output — a "silent crash."

### The first divergence

**Expected:** After entering "assist", `_alias_find` should return `-1` as a value, the script should check `existing != "-1"` (false), and break out of the loop to proceed to step 2/4.

**Actual:** `_alias_find` returns exit code 1 alongside the `-1` value. `set -e` intercepts the non-zero exit code from the command substitution and terminates the script before the `if` check at line 218 is ever reached.

**First divergence point:** `bin/pos-ai-alias:217` — the moment `_alias_find` returns 1 and `set -e` fires.

---

## Step 6: Classification

**Certainty:** FACT

This is a deterministic, reproducible bug. The crash path is:
1. Script starts with `set -euo pipefail`
2. User enters a new alias name (not in the env file)
3. `_alias_name_valid` passes → code reaches line 217
4. `_alias_load` loads empty arrays (file doesn't exist)
5. `_alias_find("assist")` iterates empty array, echoes "-1", returns 1
6. `existing="$(_alias_find "assist")"` — bash 5.2 does NOT suppress errexit here
7. Script exits with code 1 — silent crash

---

## Step 7: Recommended fixes

**Option A (minimal, targeted):** Change line 103 from `return 1` to `return 0`:

```bash
_alias_find() {
    ...
    echo "-1"
    return 0    # was: return 1
}
```

The not-found state is already communicated via stdout (`-1`). The exit code adds nothing. All callers check the value, not the exit code.

**Option B (defensive, all call sites):** Add `|| true` at each call site:

```bash
existing="$(_alias_find "$name" || true)"    # line 217
idx="$(_alias_find "$1" || true)"             # line 139
idx="$(_alias_find "$name" || true)"          # line 318
idx="$(_alias_find "$name" || true)"          # line 453
```

**Recommended:** Option A — fix the source of the problem rather than patching all consumers. The `-1` sentinel value is the designed interface; the non-zero exit code is an accidental footgun.

---

## Handoff

```
Status: ROOT_CAUSE_ESTABLISHED

Symptom:
`pos ai alias` exits silently after user enters alias name in create flow.
No error message. No continuation to step 2/4.

Expected:
After entering a valid alias name, the tool should proceed to step 2/4 (Provider selection).

Actual:
The script exits immediately after the name is captured, returning to the shell prompt.

Root cause:
`_alias_find()` at bin/pos-ai-alias:103 returns exit code 1 when a name is
not found. This is captured in a variable assignment (line 217) under
`set -euo pipefail`. Bash 5.2 does not suppress errexit for command
substitutions in variable assignments, causing immediate script termination.

Classification: FACT

Evidence:
- Reproduced with bash -x trace (stops at `existing=-1`)
- Isolated in controlled experiments (set -e + function return 1 = fatal)
- Confirmed fix with `|| true` inside command substitution

Tests performed:
1. bash -x bin/pos-ai-alias (non-interactive) — trace confirms stop at line 217
2. Isolated `set -euo pipefail` + `x="$(f)"` where f returns 1 — exits
3. Same without set -e — works
4. Same with `|| true` — works
5. Bash version confirmed: 5.2.37

Alternatives eliminated:
- _alias_name_valid regex failure: "assist" matches ^[a-zA-Z][a-zA-Z0-9_-]*$
- menu_ask_value returning non-zero: it returns 0 with value on stdout
- _alias_load failure: file doesn't exist → returns 0 cleanly
- Missing error handling around read: read succeeds, value captured correctly
- pipefail interaction: no pipes in the critical path

Affected components:
- bin/pos-ai-alias (lines 103, 139, 217, 318, 453)
- All 4 call sites of _alias_find are equally broken

Scope / decision boundary:
- The fix is within pos-ai-alias only, no architectural changes needed
- Single-line fix in _alias_find, or 4-site fix in callers

Remaining uncertainty:
- Whether other tools in the project have the same pattern
  (functions returning 1 captured in var=$(...) under set -e)

Recommended next agent: Builder

Reason:
The root cause is a single line change in _alias_find (line 103: change
`return 1` to `return 0`). The fix is mechanical and well-understood.
No architectural decisions needed.
```
