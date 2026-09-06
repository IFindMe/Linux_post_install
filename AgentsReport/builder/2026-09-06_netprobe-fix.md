# Builder Report — 2026-09-06: NET_PROBE unbound-variable fix

## TL;DR
- **Status:** IMPLEMENTED (one-line scope, verified)
- **Root cause:** `NET_PROBE="${NET_PROBE:-timeout 3 bash -c 'exec 3<>/dev/tcp/$1/$2' _ 8.8.8.8 53}"` — inside the double-quoted assignment the OUTER shell expanded `$1`/`$2` at assignment time. Under `set -u` with no positional args this is an unbound-variable crash on every `pos network download` run (unless `NET_PROBE` is already exported).
- **Fix:** escape the positional markers so only the inner `bash -c` sees them — `\$1`/`\$2` in the default string. Env-var override contract (`NET_PROBE` = full command string) unchanged.
- **File changed (only):** `bin/pos-network-download` — line 31 (NET_PROBE default). Nothing else.
- **Verification:** `bash -n` OK; bare `--help` and non-network `info` path reach the assignment with `NET_PROBE` UNSET → no unbound crash; `NET_PROBE='true'` override returns 0; static inspection confirms outer shell does not expand `$1/$2`; gates green (`make gen` idempotent, `make check` OK, `make lint` `0 FAIL, 0 WARN`).
- **Not committed** (per brief).

## Step 1: Confirm bug & scope
`bin/pos-network-download` line 31 holds the double-quoted default; `net_up()` (line 379) runs `bash -c "$NET_PROBE"`, which relies on the inner bash receiving the trailing positional args `_ 8.8.8.8 53` (`$0=_, $1=8.8.8.8, $2=53`).
Reproduced: `set -u; NET_PROBE="${NET_PROBE:-...$1/$2...}"` → `/bin/bash: line 1: $1: unbound variable`.
Confirmed the pre-existing HEAD default was `'</dev/tcp/8.8.8.8/53>'` (no `$1/$2`) — a prior security change to the probe introduced the regression.
[DONE]

## Step 2: Apply fix (escaped literal default)
Changed only line 31:
`NET_PROBE="${NET_PROBE:-timeout 3 bash -c 'exec 3<>/dev/tcp/\$1/\$2' _ 8.8.8.8 53}"`
The `\$` escapes keep the outer assignment from expanding `$1`/`$2`; the string stored is the literal `.../dev/tcp/$1/$2...`, so the inner `bash -c` receives the proper positional args. `net_up()` unchanged — it already passes the whole command string to the inner bash. Env override contract preserved and documented in usage() ("NET_PROBE override defaults (test seams)").
[DONE]

## Probes (report output)
1. **`set -u; bash -n bin/pos-network-download`** → OK (no error).
2. **Bare help, NET_PROBE UNSET** (stubbed `aria2c`/`jq`/`curl`, isolated `HOME`/`CONFIG_DIR`): `--help` exits 0, no `unbound` in output → assignment reached without crash.
   **Non-network path, NET_PROBE UNSET:** `info` (no gid) → graceful `ERROR: info: gid required`, no unbound-variable crash (assignment ran at source time before dispatch).
3. **`NET_PROBE='true'` env override** → `net_up()` returns 0 (override still honored).
4. **Static default string inspection** → default stored as `timeout 3 bash -c 'exec 3<>/dev/tcp/$1/$2' _ 8.8.8.8 53` (literal `$1/$2`, NOT expanded by outer shell). Simulated probe with `echo inner sees $1 $2` → inner bash prints `8.8.8.8 53`, proving positional probe still correct.
5. **`--dry-run`/usage unaffected** — neither references NET_PROBE; usage() unchanged by this fix.
[DONE]

## Step 3: Repo gates
- `bash -n bin/pos-network-download` → OK.
- `make gen` → ran; re-ran: **idempotent** (byte-identical diff before/after), i.e. no new output. Net-probe is an env var, not a `# POS:` header, so it feeds nothing.
- `make check` (`scripts/check-sync.sh`) → OK.
- `make lint` (`scripts/lint-conventions.sh`) → `0 FAIL, 0 WARN`.
[DONE]

## Scope compliance
- Approved scope: `bin/pos-network-download` ONLY (NET_PROBE lines + net_up).
- Change made: exactly the NET_PROBE default string (line 31). `net_up` confirmed correct, no change required.
- Out-of-scope changes: none made by Builder. (Working tree contains pre-existing unstaged changes from prior agents — not authored here.)
- Not committed (per brief).

## Remaining risks / follow-up
- None for this fix. The env-var override string is operator-controlled; passing an invalid command there is the operator's responsibility (unchanged behavior).

## Recommended next agent
Orchestrator — task is complete, targeted verification and all gates pass; no cross-track coordination needed.

## Changes made by Builder
- `bin/pos-network-download`: escaped `$1`/`$2` to `\$1`/`\$2` in the `NET_PROBE` default so the inner `bash -c` (not the outer shell) performs the probe-host positional expansion.
