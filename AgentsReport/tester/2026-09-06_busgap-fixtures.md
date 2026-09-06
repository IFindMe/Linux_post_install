# Busgap Fixture Update — 2026-09-06

## TL;DR

- **F4 (`ensure_user_bus`)** in `bin/pos-ai-server` now runs in `cmd_start` BEFORE the DRY_RUN return (verified in `lib/common.sh:148` + `bin/pos-ai-server:654-671`), so every unit-path `start` without a reachable user systemd bus aborts with rc 1 and no `ExecStart:` output.
- Three pre-existing DRY_RUN test files never provided a `systemctl` stub / bus env, so 33 checks failed (26 + 3 + 4).
- **Fix:** added a succeeding `systemctl` stub (return 0) to each affected sandbox, matching the established pattern in `t-systemd-unit.sh` and `t-ai-server-bus.sh`. No assertions weakened; bus-missing behavior remains covered in `t-ai-server-bus.sh`.
- **Result:** full suite green — **16 files pass / 0 fail, 269 checks pass / 0 fail, 0 skip. Runtime 72s.**

**PASS/FAIL totals: 269 pass / 0 fail. Defects by severity: none.**

---

## Step 1: Establish failure & mechanism

Read `bin/pos-ai-server`, `lib/common.sh`, `tests/run-tests.sh`, the 3 affected tests, and the passing control tests (`t-systemd-unit.sh`, `t-ai-server-bus.sh`).

**Verified call order:** `cmd_start` (pos-ai-server:654-655) calls `ensure_user_bus` when `NO_UNIT != 1`, i.e. **before** the `DRY_RUN` early-return at line 661. `ensure_user_bus` (common.sh:148-154) runs `systemctl --user show-environment &>/dev/null` and `err`s on nonzero. All three DRY_RUN tests drive the unit path (no `--no-unit`), so without a `systemctl` stub they abort with rc 1 and no `ExecStart:` output.

## Step 2: Apply fixtures (systemctl stub returning 0)

Established pattern: `printf '#!/usr/bin/env bash\nexit 0\n' > "$stubs/systemctl"` + add to `chmod +x` (exact copy of `t-systemd-unit.sh:41,46`). Also tested that this satisfies the `systemctl --user show-environment` probe without needing `XDG_RUNTIME_DIR` — the stub returns 0, so the pre-flight passes. Assertion lines untouched.

- `t-ai-server-flags.sh`: added stub after nvidia-smi, extended chmod.
- `t-unsupported-flags.sh`: added stub after first llama-server/chmod, extended chmod.
- `t-config-precedence.sh` (Part B): added stub after nvidia-smi, extended chmod.

[PASS]

## Step 3: bash -n + full suite

- `bash -n` on all three edited files: OK.
- `make test`: 16 files / 269 checks, all pass.

Counts per modified file: `t-ai-server-flags.sh` 28, `t-config-precedence.sh` 43, `t-unsupported-flags.sh` 19. (Prior failing counts: 26 / 4 / 3. The higher post-fix counts reflect the checks now actually running to completion instead of aborting on the bus error; the pre-existing assertion set was preserved.)

[PASS]

---

## Handoff

**Status:** TESTS_READY

- **Files changed (test fixtures only):** `tests/t-ai-server-flags.sh`, `tests/t-unsupported-flags.sh`, `tests/t-config-precedence.sh`
- **Assertions:** unchanged (only added a systemctl stub + chmod); bus-missing behavior stays in `t-ai-server-bus.sh`.
- **Verification:** `bash -n` all three; `make test` → 269 pass / 0 fail, 72s.
- **No production code changed; nothing committed.**
- **Residual failures:** none. (Noted: F1-regex fix and these fixtures land in parallel; this run was green, so no rerun needed.)
