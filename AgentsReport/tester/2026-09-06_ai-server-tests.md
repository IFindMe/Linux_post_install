# Tester report — llama-server breakage (F1–F7) regression tests

Date: 2026-09-06 · Tester · Objective: regression tests `tests/` for the fixed llama-server contract, `make test` evidence, no commits (per brief). Status: TESTS_READY (new files) / suite blocked by 2 pre-existing issues.

## TL;DR

- New test files (all pass, runnable via `make test`; sandbox-only, no prod/other-test edits): `tests/t-ai-server-validate.sh` (F1/F2/F5/F6), `tests/t-ai-server-model.sh` (F3), `tests/t-ai-server-bus.sh` (F4 + E2E user/SSH scenarios), `tests/t-llamacpp-install.sh` (F7).
- **New-suite result: 90 checks PASS / 0 FAIL / 0 SKIP, runtime ~7 s.** Total `make test` (16 files): 12 files pass / 4 files fail / 0 skip, 235 check PASS / 34 FAIL / 62 s — the 34 failures are ALL in 4 pre-existing test files, 2 root causes, NEITHER caused by my new files (verified: new files pass standalone and in the combined run).
- **Production bug observed (REPORTED, not fixed, per brief):** F1 version regex alternation `[0-9]+\.[0-9]+\.[0-9]+|build [0-9]+|b[0-9]+` — leftmost-match makes `grep -oE` return `build 1` (→ version `1`) for `llama.cpp build 1.2.3 (…)`. File/repro: `bin/pos-ai-server:86`; `echo "llama.cpp build 1.2.3 (abcdef)" | grep -oE '…'` → `build 1`. Breaks pre-existing `tests/t-ai-llama-detect.sh` (expects `1.2.3`, gets `1`). Real b10822 (`… (build 10822)` → `10822`) is unaffected.
- **Fixture gap introduced by F4 pre-flight:** 3 pre-existing DRY_RUN test files (`t-ai-server-flags.sh` 26 FAIL, `t-unsupported-flags.sh` 3 FAIL, `t-config-precedence.sh` 4 FAIL) never provided a `systemctl` stub / bus env, so the new `ensure_user_bus` (called before the DRY_RUN return in `cmd_start`) aborts with rc 1 and no `ExecStart:` is emitted. NOT a production bug. Per brief I did NOT modify other tests; the fix is a fixture update (succeeding `systemctl` stub + `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` in those 3 files) → needs Orchestrator routing.
- `make test` is therefore NOT green on the merged tree (34 fails above). After the F1 regex fix and the 3 file fixture updates, expected status: all 16 files green (my 4 + 12 already-green).

## Step 1: Contracts read (architect/detective/builder reports, test infra, F1–F7 code)

Read `AgentsReport/{architect,detective,builder}/2026-09-06_ai-server-*.md`, `tests/run-tests.sh`, `tests/test-lib.sh`, the 4 affected pre-existing tests + `t-systemd-unit.sh` (control, passes), `bin/pos-ai-server`, `lib/common.sh` `ensure_user_bus` (lines 143–154), `apps/ai/llamacpp.sh` `llamacpp_sanity` (lines 23–36) + `LLAMACPP_BIN_DIR` seam (line 17). Marked: F4 order (bus check BEFORE DRY_RUN return), `--no-unit` skips bus, `NO_UNIT_PIDFILE`/`NO_UNIT_LOG` seams, DRY_RUN unit-path output line `(dry-run) ExecStart: …`, `DRY_RUN+--no-unit` output `(dry-run) nohup …`. Pre-existing failures reproduced on the current tree before writing any new test (baseline full run: 12/4).

[PASS]

## Step 2: tests/t-ai-server-validate.sh (F1/F2/F5/F6) — 27 checks

Approach: `extract_fn` (brace-counting awk) extracts the REAL shipped `detect_llama_version`, `find_llamacpp`, `validate_requested_flags`, `validate_default_flags` bodies into a sandbox file sourced in `bash -c` subshells (with `$ROOT/lib/common.sh`) — no prod edit, tests the exact shipped code. 25× `validate_default_flags` loop against a real-shaped 63 864-byte / 732-line `--help` fixture (flags at lines 7/25/140/503/506, matching Detective's real llama.cpp layout, just under the 64 KB pipe buffer — the adversarial size that made the pre-fix `printf|grep -q` race observable). Each run asserts the whole invocation rc=0 AND all five globals `1|1|1|1|1` (catches an rc=141 SIGPIPE component explicitly). 20× requested-flag cases (`--port` accepted; `--tensor-split` rejected naming `0.4.0`); F1 stderr-vs-file cases (`stderr` → `0.4.0`, `build 10822` → `10822`, `b10822` → `b10822`, file-read ok, missing binary → `unknown` rc 0; all real CLI). F5: bare `server` no longer a candidate (only `llama-server`/`llama-server-cuda`), `llama-server` preferred. F6: DRY_RUN `start` (succeeding `systemctl` stub, real CLI) → ExecStart has `--port 8088 --host 127.0.0.1 --n-gpu-layers 0 --ctx-size 4096 --threads`; `status` shows `version:   0.4.0`, never `unknown`.

Result: 27 PASS / 0 FAIL / 0 SKIP, ~3 s.

[PASS]

## Step 3: tests/t-ai-server-model.sh (F3) — 18 checks

Unit tests of real `resolve_model`/`resolve_gguf_in_dir` (HF layout fixture: `models/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf`, multi dir, empty dir, flat file, absolute path) via `bash -c "source '$com'; source '$fn_file'; resolve_model '<arg>'";` with `HF_DOWNLOAD_DIR` env; plus CLI integration through real `pos-ai-server` (`start … --no-unit` DRY_RUN resolves to `-m "…/Qwen3-1.7B-Q8_0.gguf"`; multi-dir CLI start errs `pick one` rc 1). First run had 4 failures in the multi/empty unit cases (`err`/`pick_model` not found in the un-sourced subshell); fixed by sourcing `$com` in every subshell — re-run 18/18.

Result: 18 PASS / 0 FAIL / 0 SKIP, ~1 s.

[PASS]

## Step 4: tests/t-ai-server-bus.sh (F4 + E2E) — 36 checks

Stub farm (install-shaped `llama-server` with b10822 stderr version + full-support help; failing `systemctl` = bus-missing SSH shape; `nvidia-smi` exit 1 → deterministic CPU path; `curl` → `{"status":"ok"}`; `loginctl` → `Linger=no`; env `-u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS` for bus-less cases since the outer shell has them unset). Verified: bus missing + real `start` → rc≠0, output has BOTH remediation lines + `no unit was written`, NO orphaned unit file; bus present (env + succeeding stub) + DRY_RUN → rc 0 and proceeds to `ExecStart:`; `--no-unit` bus-less escape hatch → real start writes pidfile, launches stub (`exec sleep 300` so the logged pid IS the sleeper — no orphans; stop killed it, no stray processes after suite), `status` finds `service:   running` via pidfile, `stop` kills + removes pidfile; E2E user scenario (bus up, unit path): `start Qwen-Qwen3-1.7B-GGUF` rc 0, unit written, ExecStart has model + `--port 8088 --host 127.0.0.1 --n-gpu-layers 0 --ctx-size 4096 --threads`, `status` reports `version:   0.4.0` not `unknown`, `systemd-analyze verify` accepts the unit (BEFORE-LINGER/WARN tolerances confirmed on systemd 257), `stop` removes unit; E2E SSH-shaped: rc 1, both remediation lines, no unit. The `printf '...%s...'` with `--`-leading strings lesson from Step 2 also applies to the unit ExecStart assertions — used `printf '%s\n'` consistently.

Result: 36 PASS / 0 FAIL / 0 SKIP, ~4 s.

[PASS]

## Step 5: tests/t-llamacpp-install.sh (F7) — 9 checks

Extracts real shipped `llamacpp_sanity` via `extract_fn`; exercises through the `LLAMACPP_BIN_DIR` seam with the bin dir on PATH. Healthy fixture → rc 0 + `llama.cpp sanity OK`; dangling symlink → rc 1 + `dangling symlink`; non-executable file → rc 1 with a sanity err (bash `command -v` finds the file by PATH existence, so the failure surfaces at the `--version` exec step: `did not run`); broken binary (`--version` exit 1, missing-shared-lib shape) → rc 1 `did not run`; static guard: shipped installer wires `llamacpp_sanity` into install. Fixed one assertion after the first run: my expected `not on PATH` message was wrong for the non-executable case (real behavior: `command -v` exists-check passes, exec fails) — re-run 9/9.

Result: 9 PASS / 0 FAIL / 0 SKIP, <1 s.

[PASS]

## Step 6: Full-suite evidence

- My 4 files together: `./tests/run-tests.sh t-ai-server-validate.sh t-ai-server-model.sh t-ai-server-bus.sh t-llamacpp-install.sh` → files 4 pass / 0 fail / 0 skip; checks 90 pass / 0 fail / 0 skip; runtime 7 s (fits the ≤30 s new-suite budget).
- `make test` (16 files): files 12 pass / 4 fail / 0 skip; checks 235 pass / 34 fail / 0 skip; runtime 62 s (< 90 s budget).
- Fail breakdown (all pre-existing files): `t-ai-llama-detect.sh` 8 checks, 1 FAIL — F1 regex production bug (`version:   1` vs expected `1.2.3`); `t-ai-server-flags.sh` 28 checks, 26 FAIL — bus-gap (all 26 abort rc 1 before `ExecStart:`); `t-config-precedence.sh` 39 checks, 4 FAIL — bus-gap (B1–B4, empty ExecStart); `t-unsupported-flags.sh` 16 checks, 3 FAIL — bus-gap (rc 1 + missing `--threads` warn because start aborted before validation path).
- `bash -n` clean on all 4 new files. No stray processes/pidfiles after the `--no-unit` case (`pgrep -af 'llama-server|sleep 300'` empty, no `/tmp/pos-ai-server.pid`).
- git status: 4 new `tests/t-*.sh` untracked (not committed per brief); working tree still carries Builder's uncommitted F1–F7 changes.

[PASS] (new files) · suite-level blockers in TL;DR

## Handoff / blockers

- **F1 production bug** → Builder: fix `bin/pos-ai-server:86` alternation ordering (e.g. put `[0-9]+\.[0-9]+\.[0-9]+` first or drop `build [0-9]+`, matching real b10822 semantics); then `t-ai-llama-detect.sh` should go green (verify).
- **F4 bus-gap fixtures** → Orchestrator to authorize editing the 3 pre-existing DRY_RUN test files (`t-ai-server-flags.sh`, `t-unsupported-flags.sh`, `t-config-precedence.sh`): add a succeeding `systemctl` stub + set `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` in their `start` invocations (pattern: `tests/t-systemd-unit.sh` + my `t-ai-server-bus.sh`). Once authorized, this is a small Maintainer/Tester fixture edit, not a prod change.
- After both: expect all 16 files green — 269 checks = my 90 + 145 pre-existing passes + the 34 fixed. Reviewer can then independently re-run `make test`.
- Residual risk (documented, not blocking): F1 regex fragility for `build X.Y.Z-dev` strings remains until the production fix; my F1 tests assert real b10822-shaped output which the current code handles.