# Tester Report — Matrix-auth daemon-hang rc assertion (Reviewer N1) — 2026-09-06

## TL;DR

- **Status: TESTS_READY** — regression-suite hardening for Reviewer `AgentsReport/reviewer/2026-09-06_stab_acceptance.md` Note N1: `t-matrix-auth.sh` run 1 lacked an exit-code assertion, so a daemon-hang regression could pass vacuously.
- **Defects added:** 2 new `check_rc` assertions (run 1 authorized + run 2 room-unset). File `t-matrix-auth.sh`: 8 → **10 checks**.
- **Suite:** `make test` → **12 files pass / 0 fail / 0 skip**, **179 checks pass**, runtime **45s**, exit 0. No flakes observed.
- **Production code: untouched.** Only `tests/t-matrix-auth.sh` modified; `tests/test-lib.sh` unchanged (the `check_rc` helper already exists).
- **Key correction to the brief:** asserting `TR_RC` under plain `timeout` is vacuous — GNU `timeout` reports **124 in BOTH** the healthy and broken-trap cases. The discriminating fix is `timeout --preserve-status -k 2 …` + assert the daemon's own TERM-trap exit status.

---

## Step 1: Confirm the gap (Reviewer N1)

Reviewed `tests/t-matrix-auth.sh` run 1: `test_run_env … -- timeout 5 "$listener" --run` with `check_contains`/`check_file_exists`/`check_eq` but **no rc assertion**. Confirmed the reviewer's concern: a broken TERM trap (daemon ignores TERM) would not fail any existing check.

Also confirmed the deeper problem with the naive fix: plain `timeout 5` returns **124 whether or not the TERM trap works** (verified empirically — both the working daemon and a no-trap daemon yield 124). So `check_rc … 124` would be itself vacuous.

Evidence (throwaway probes, `/tmp/opencode`, removed after):
```
timeout 1 bash -c 'trap "exit 0" TERM; sleep 30'   → rc=124   (trap WORKS)
timeout 1 bash -c 'sleep 30'                        → rc=124   (no trap)
timeout --preserve-status 1 … (trap WORKS)          → rc=0
timeout --preserve-status 1 … (no trap)             → rc=143 (SIGTERM)
```

[PASS]

## Step 2: Design the discriminating assertion

Goal per the brief: *"so the test genuinely fails on a daemon-hang regression"*. The daemon is an infinite polling loop that only terminates via its `TERM` trap (`trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM INT`), so `timeout` must always be the one signalling it. To make the daemon's own exit status observable:

- **`--preserve-status`** — `timeout` forwards the child's real exit status instead of forcing 124.
- **`-k 2` (`--kill-after`)** — bounds the wait: if a broken trap ignores TERM, `timeout` SIGKILLs at +2s so the test cannot hang the whole suite indefinitely.

**Empirical healthy-path exit status (current production code):** the listener's TERM trap is `kill $(jobs -p) 2>/dev/null; exit 0`. Under `set -euo pipefail`, with no background jobs `kill` (no args) fails with **rc 2**, which triggers errexit **before** the `exit 0` and aborts the trap → the daemon actually exits with **rc 2** (verified on the real listener and a minimal `set -euo pipefail` repro: `rc=2`, the post-kill `exit 0` never runs).

- A genuine **daemon-hang** (TERM ignored / trap non-exiting): `--kill-after` SIGKILLs → **rc 137**.
- A healthy daemon: TERM trap fires → **rc 2**.

So `check_rc … 2` meaningfully discriminates: healthy = daemon's own trap exit (2, definitively not a forced kill), regression = 137/124.

**Note (observation for Orchestrator, NOT fixed — out of scope):** the `kill $(jobs -p)` in the daemon's TERM trap fails under errexit, so the daemon exits 2 rather than the intended 0. Harmless to the daemon's operation (it still terminates, no hang) but the `exit 0` is effectively dead. Flagged for a possible future Builder fix; intentionally not addressed here (production code out of scope). The rc assert documents current healthy behavior and still catches a hang.

[PASS]

## Step 3: Change — `tests/t-matrix-auth.sh`

- Run 1 (authorized): added `--preserve-status -k 2` and `check_rc "daemon terminated via TERM trap, not killed (no hang)" 2 "$TR_RC"`.
- Run 2 (room-unset): same `--preserve-status -k 2` + `check_rc … 2`.
- Comment explains why `--preserve-status -k 2` + rc 2 catches the regression and why plain `timeout` would be vacuous.

Snippet (run 1):
```bash
    # --preserve-status + --kill-after surface the daemon's own TERM-trap exit,
    # so a broken trap (daemon-hang regression → SIGKILL 137 / timeout 124)
    # genuinely fails the rc assert instead of passing vacuously. --kill-after
    # also bounds the wait so a hung daemon can't stall the whole suite.
    test_run_env "${common[@]}" -- timeout --preserve-status -k 2 5 "$listener" --run
    check_rc "daemon terminated via TERM trap, not killed (no hang)" 2 "$TR_RC"
```

Run 2 mirrors it with the room-unset env (no `MATRIX_ROOM_ID`) and desc `"room-unset daemon terminated via TERM trap, not killed (no hang)"`.

`tests/test-lib.sh` was not modified — `check_rc` already exists (`test-lib.sh:19`).

[PASS]

## Step 4: Mutation probe — the new assert genuinely fails on a hang

Copied the listener into a scratch tree and replaced the TERM trap with a non-exiting handler (`trap 'hang…sleep 30' TERM INT`) to simulate the daemon-hang regression, then ran it under the same `timeout --preserve-status -k 2` invocation:

```
… timeout --preserve-status -k 2 3 "$listener" --run
ignoring TERM (regression), sleeping
rc=137
```

Expected `2`, actual `137` → the `check_rc 2` assert **rejects** the regression and the test fails. Healthy path verified → `rc=2` → assert passes. Scratch cleanup performed; no production file touched.

[PASS]

## Step 5: Full suite — `make test`

```
Running 12 test file(s) — strict mode: no network, no sudo, no system changes.
  PASS  t-ai-hf-download.sh    (10 checks)
  PASS  t-ai-llama-detect.sh   ( 9 checks)
  PASS  t-ai-server-flags.sh   (28 checks)
  PASS  t-config-precedence.sh (43 checks)
  PASS  t-gen-docs-drift.sh    ( 4 checks)
  PASS  t-gpg-password.sh      (14 checks)
  PASS  t-lint-gate.sh         ( 5 checks)
  PASS  t-matrix-auth.sh       (10 checks)
  PASS  t-systemd-unit.sh      (11 checks)
  PASS  t-telegram-auth.sh     ( 8 checks)
  PASS  t-uninstall-manifest.sh(18 checks)
  PASS  t-unsupported-flags.sh (19 checks)
──────────────────────────────────────────────
Summary: files 12 pass / 0 fail / 0 skip (of 12)
Checks : 179 pass / 0 fail / 0 skip
Runtime: 45s
```

Exit 0. `t-matrix-auth.sh` independently re-run at 10 checks (10s). No flake source observed; isolated result is representative (no mid-edit contention observed on the suite path — `bin/pos`/`bin/pos-*` are only read by the tests, never written here).

[PASS]

---

## Verification completed

- Baseline `t-matrix-auth.sh` (8 checks, 10s) before edit — green.
- Post-edit standalone run (10 checks, 10s) — green.
- Mutation probe proves the new assert fails (rc 137) on a broken TERM trap / daemon hang.
- Full `make test` green: 179/179 checks, 45s.
- `test-lib.sh` untouched; no production code touched; no commits made.

## Coverage note

The new asserts close the reviewer's vacuous-pass gap: a daemon-hang (TERM-trap) regression now produces rc 137/124 and fails the test rather than passing silently. Both authz runs (authorized + fail-closed) carry the guard.

## Remaining uncertainty / out of scope

- The daemon's dormant `exit 0` in its TERM trap (exits 2 under errexit) — see Step 2 observation. Functional no-hang is preserved; left for Builder/Architect if they want the trap to truly exit 0.
- Not committed (per brief).

## Recommended next agent

**Reviewer** — the regression-suite gap is closed and green; suitable for independent verification of the rc assert.

**Reason:** Tester completes measurement/verification; the change is in test-only scope, ready for reviewer sign-off.

## Changes made by Tester

- `tests/t-matrix-auth.sh` — added `--preserve-status -k 2` to both `timeout` invocations and two `check_rc … 2` (no-hang) assertions; explanatory comments. No other files touched, no commits.
