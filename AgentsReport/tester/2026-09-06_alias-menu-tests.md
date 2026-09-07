# Tester Report — Alias-Menu Fix: Regression Tests (2026-09-06)

## TL;DR

- **Status:** IN PROGRESS — see per-step markers below; final summary lands in Step 5/6.
- **Scope:** permanent regression coverage for Builder's alias-menu fix (lib/menu-lib.sh `--allow-empty` + bin/pos-ai-alias 353/410 + step counters 352/383 → /5). Tests only; no source/doc edits.
- **Methods used:** (1) unit matrix on the real `menu_ask_value` via the non-TTY stdin path, (2) static source guards via brace-extracted function bodies (same `extract_fn` pattern as t-ai-server-validate.sh), (3) pty E2E through `script -qec` driving the REAL `pos ai alias create` flow.
- **Pty verdict:** FEASIBLE. `script -qec` with paced input (0.3s inter-input sleep) drives the raw-mode reader deterministically. 3 E2E scenarios proven.
- **Files added:** `tests/t-menu-allow-empty.sh`, `tests/t-ai-alias-create-e2e.sh`.

---

## Step 1: Pty feasibility experiment `[DONE]`

Attempted `script -qec` with a piped script of inputs per DEV.md §7 (`printf 'answer\n' | script -qec "cmd" /dev/null`).

**Evidence (probe A — the reported bug scenario):**
```
printf 'testbot\n1\n\n\n\ny\n'  (paced 0.4s) | script -qec "$ROOT/bin/pos-ai-alias create" typescript
rc=0
typescript showed: [1/5] Alias Name → [2/5] Provider → [3/5] Session Name →
                   [4/5] System Prompt (EMPTY Enter) → [5/5] Trust Level → "Alias 'testbot' created."
env file: testbot|gemini|testbot||0   (4th field EMPTY — the fix)
wrapper:  ~/.local/bin/testbot exists, exec line without --system
```

**Pacing requirement (probe: no-sleep):** all input at once is UNRELIABLE — `menu_read_value`'s raw reader consumes the whole queued burst via `dd bs=4096`, so bytes after the first submitted newline are discarded and later readers see EOF → clean abort. Input MUST be paced (sleep between inputs). 0.2s and 0.3s pacing both proven reliable for all three scenarios; 0.1s is NOT reliable for the empty-first-input case.

**Rejected alternatives:** `expect` not installed; python3 pty module available but unnecessary — `script` is deterministic with pacing and keeps the suite zero-dependency (bash + util-linux coreutils, matching DEV.md precedent).

**Verdict:** pty driver FEASIBLE → E2E included in the permanent suite (case table below).

---

## Step 2: Unit matrix — menu_ask_value --allow-empty `[PENDING]`

See coverage table (Part A of t-menu-allow-empty.sh) — implementation landed, run results pending full suite.

---

## Step 3: Static source guards `[PENDING]`

Create-flow step labels 1-5 of /5 (extracted `_alias_create` body); exactly 2 `--allow-empty` call sites; edit flow still /4. See coverage table.

---

## Step 4: E2E create flow (pty) `[PENDING]`

See coverage table (3 cases in t-ai-alias-create-e2e.sh).

---

## Step 5: Full suite `[PENDING]`

## Step 6: Gates `[PENDING]`

---

## Coverage table

| case | technique | result |
|------|-----------|--------|
| _— unit matrix —_ | | |
| empty+no-default, no flag → rc 1 | non-TTY stdin, real lib | _pending_ |
| empty+no-default, --allow-empty → rc 0 + empty | non-TTY stdin, real lib | _pending_ |
| empty+default, --allow-empty → rc 0 + default (default wins) | non-TTY stdin, real lib | _pending_ |
| empty+default, no flag → rc 0 + default (regression) | non-TTY stdin, real lib | _pending_ |
| non-empty, --allow-empty → rc 0 + value | non-TTY stdin, real lib | _pending_ |
| non-empty, no flag → rc 0 + value (regression) | non-TTY stdin, real lib | _pending_ |
| EOF/cancel, --allow-empty → rc 1 (cancel stays cancel) | non-TTY stdin, real lib | _pending_ |
| EOF/cancel, no flag → rc 1 (contract) | non-TTY stdin, real lib | _pending_ |
| value beats default with --allow-empty | non-TTY stdin, real lib | _pending_ |
| _— static source guards —_ | | |
| create steps 1..5 all labeled /5 (no /4) | extract_fn(_alias_create) + grep | _pending_ |
| exactly 2 --allow-empty call sites (353/410), both in create | grep bin/pos-ai-alias + extract_fn | _pending_ |
| edit flow still 4 × /4 (untouched) | extract_fn(_alias_edit) + grep | _pending_ |
| no OTHER tool adopted --allow-empty (scope fence) | grep -l bin/pos-* | _pending_ |
| _— pty E2E —_ | | |
| empty System Prompt → trust step reached + alias file created (empty 4th field) | script -qec REAL create flow | _pending_ |
| empty Alias Name → warn + re-prompt [1/5] ×2 → created | script -qec REAL create flow | _pending_ |
| Ctrl-D at System Prompt → clean abort, no [5/5], no alias, no env | script -qec REAL create flow | _pending_ |
| script binary unavailable → documented SKIP | require_cmd | _pending_ |

---

## Constraints respected

- Only tests + this report modified; no lib/ bin/ AGENT_TODO.md docs touched; no `make gen`.
- Hard-skip contract honored (SKIP only via `skip_case`, never a fake pass).
- Runtime budget respected (target ≤ ~70s; suite ~49s today + ~10s E2E).