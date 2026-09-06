# Tester Report — Regression Test Infrastructure + First Suite (2026-09-06)

## TL;DR (updated continuously)

- **Status:** TESTS_READY — 12/12 test files pass, 177 checks, runtime ~46s (`make test`).
- **Deliverables:** `tests/run-tests.sh` (zero-dep runner), `make test` target, 12 `tests/t-*.sh` files, `tests/README.md`.
- **Findings (production bugs discovered):** none — no production bug surfaced; all defects found during test iteration were in the test framework/stubs/test assertions themselves (see Step 4).
- **Suite timing / counts:** `make test` (2026-09-06): files **12 pass / 0 fail / 0 skip**, checks **177 pass / 0 fail / 0 skip**, runtime **46s** (44s on rerun); exit 0.
- **Gates:** `make lint` still `0 FAIL, 0 WARN`; `make check` now PASS (parallel-track gen drift resolved upstream during this session); tests/ has zero lint/check surface.

---

## Step 1: Environment baseline (before adding tests)

- `make check` at start: **FAILED** — `doc/code drift` (expected: parallel Builder tracks have uncommitted changes; gen output in the working tree not yet refreshed). Now resolves to PASS after upstream sync.
- `make lint` at start: **PASS** — `0 FAIL, 0 WARN` (3.5s).
- `make gen` idempotence on a pristine temp copy: **PASS** (2× ~1.4–1.8s; `git status --porcelain` empty after 2nd gen).
- `systemd-analyze verify` prototype: passes (rc 0) when ExecStart binary exists and model path is quoted.
- Config-loader migration (D-D): **landed in the working tree** — `load_env_file` present in `lib/config-ui.sh:336`; all 9 tools call it. Config-precedence tests target the final contract.

## Step 2: Framework + suite files (status below)

- [x] `tests/run-tests.sh`
- [x] `tests/test-lib.sh`
- [x] `tests/t-ai-server-flags.sh`
- [x] `tests/t-ai-hf-download.sh`
- [x] `tests/t-ai-llama-detect.sh`
- [x] `tests/t-unsupported-flags.sh`
- [x] `tests/t-systemd-unit.sh`
- [x] `tests/t-telegram-auth.sh`
- [x] `tests/t-matrix-auth.sh`
- [x] `tests/t-gpg-password.sh`
- [x] `tests/t-config-precedence.sh`
- [x] `tests/t-uninstall-manifest.sh`
- [x] `tests/t-gen-docs-drift.sh`
- [x] `tests/t-lint-gate.sh`
- [x] `Makefile` `test:` target
- [x] `tests/README.md`

## Step 3: Full suite run (final)

Command: `make test` (target: `./tests/run-tests.sh`) — 2026-09-06.

```
Running 12 test file(s) — strict mode: no network, no sudo, no system changes.

  PASS  t-ai-hf-download.sh (10 checks)
  PASS  t-ai-llama-detect.sh (9 checks)
  PASS  t-ai-server-flags.sh (28 checks)
  PASS  t-config-precedence.sh (43 checks)
  PASS  t-gen-docs-drift.sh (4 checks)
  PASS  t-gpg-password.sh (14 checks)
  PASS  t-lint-gate.sh (5 checks)
  PASS  t-matrix-auth.sh (8 checks)
  PASS  t-systemd-unit.sh (11 checks)
  PASS  t-telegram-auth.sh (8 checks)
  PASS  t-uninstall-manifest.sh (18 checks)
  PASS  t-unsupported-flags.sh (19 checks)

──────────────────────────────────────────────
Summary: files 12 pass / 0 fail / 0 skip (of 12)
Checks : 177 pass / 0 fail / 0 skip
Runtime: 46s
```

Exit code 0. Rerun via `make test`: files 12/12 pass, 44s. `make lint` unaffected (`0 FAIL, 0 WARN`), `make check` passes (parallel drift resolved upstream, not by this track).

[PASS]

## Step 4: Defects found and fixed during test iteration (all in test artifacts, none in production)

1. `tests/test-lib.sh` `check_rc` — `$desc` read before `local desc="$1"` declaration → `set -u` crash on first use. Fixed.
2. `tests/run-tests.sh` — `set -e` in the runner killed the PARENT when a test subshell exited nonzero (e.g. test 4 aborted after 3 passing tests). Fixed: subshell wrapped in `if (…); then rc=0; else rc=$?; fi`; verified a failing test now records FAIL and continues. Also: bare-name args (`run-tests.sh t-gpg-password`) now resolve `$TEST_DIR/<name>.sh`.
3. `tests/t-ai-hf-download.sh` stub — embedded JSON via `$(cat "$tree_resp")` broke stub quoting → replaced with `cat "$TREE_RESP"` env passthrough; `for (( ; i<=$#; i++ ))` expanded `$#` at stub-write time → escaped `\$#`; `base_env` typo → `env_base`; `return 1` at stub top level → `exit 1` (see #6).
4. `tests/t-ai-llama-detect.sh` — asserted literal `cpu`; tool emits `gpu:       CPU` (case differs) → assertions corrected to actual token shape.
5. `tests/t-config-precedence.sh` — Part A env-wins probe `FOO=envval load_env_file …` evaluated in the PARENT shell (no persistence) → rewrote as explicit subprocess with `export` + captured output; Part B needed llama-server + nvidia-smi stubs for the deps guard; Part D legacy guard was a false positive — exactly 3 documented `load_system_env` callers (pos-media-sync, pos-system-backup, pos-system-health) → whitelist those and assert count == 3.
6. **Stub scripts: `return` at top level of a non-sourced script is an ERROR in bash and falls through** (`return: can only 'return' from a function or sourced script`), so every stub response silently gained a trailing `{"ok":true}` → corrupt JSON → listeners slept in a 5s retry loop and never processed (`jq -r '.ok'` returned `true\ntrue`). Fixed all stub heredocs to `exit 0` (telegram/matrix curl stubs; ai-hf already used `exit`).
7. `tests/t-telegram-auth.sh` / `tests/t-matrix-auth.sh` — two line-continuation bugs in `test_run_env` invocations: a missing trailing `\` meant the env-var list became a separate command and `test_run_env` ran bare `env` (prints the whole environment — the mysterious `SHELL=/bin/bash` output) with rc 0. Fixed by single-line invocation. Matrix reply count needle `m.room.message` also matched the URL-encoded sync filter on every `/sync` line → narrowed to `/send/m.room.message`.
8. `tests/t-gpg-password.sh` — artifact-leftover checks false-failed because run 1's `.gpg` remained on disk for runs 2/3 → now `rm -rf "$work"; mkdir` between runs; bare `--passphrase` guard now token-exact (`grep -c '^--passphrase$'`) since `--passphrase-fd` legitimately contains the substring.
9. `tests/t-lint-gate.sh` — negative case invoked the REAL lint (absolute path); `lint-conventions.sh` computes `ROOT="$(dirname "$0")/.."` and `cd`s THERE, so it linted the real repo (clean), not the planted copy. Fixed: run the copy's own `scripts/lint-conventions.sh` (relative path) from inside the copy.
10. `tests/t-uninstall-manifest.sh` — POS_LIBS extraction awk `<^POS_LIBS=( … {getline; while(1)…}` never matched a lone `^)` line because the block is `POS_LIBS=(… \⏎ …registry.sh)` (two lines, `)` on the second) → getline at EOF returns 0, loop spins forever at EOF → the whole test hung (this was the full-suite 300s hang). Replaced with a sed range `/^POS_LIBS=(/,/)$/p` + normalization; also the leftover-gap whitespace made the sorted diff fail (collapsed with `tr -s`), and plugin-removal marker check now greps `POS_PLUGIN` (the marker `installed_plugins()` scans for) instead of a literal `^# POS_PLUGIN:` in the uninstall script.
11. `tests/t-systemd-unit.sh` — systemd unit uses double quotes (not backslash escaping) for the model path → assertion corrected; `EnvironmentFile` check compared against the unit PATH instead of its content → `$(cat "$unit")`.
12. `tests/t-unsupported-flags.sh` — real error text is `installed llama.cpp <v> does not expose <flag> — remove it or upgrade llama.cpp`, not "does not support" → assertions updated.

None of the above touched production code. `make check` / `make lint` / `make gen` results are unchanged by this track (verify with `make check && make lint` — both currently green).

## Step 5: Coverage notes & handoff

- **Behavior covered per area:** ai-server flag seam (CLI/config/env/default precedence + unsupported-flag hard error + dedupe) 28; config file precedence + legacy loaders 43; gpg password hygiene (fd-only, no bare token, no secret in argv, artifact cleanup on enc/verify failure) 14; systemd unit generation (ExecStart quoting, environment/deps/secrets lines, `systemd-analyze verify`) 11; telegram/matrix authz fail-closed gates 8+8; ai hf download stub network behavior 10; llama detection stub 9; gen/lint gates (positive + planted-violation negative) 4+5; uninstall manifest symmetry + XDG scan tier + POS_PLUGIN marker 18; unsupported-flag matrix 19.
- **What is not covered (deliberately):** real network/sudo/docker paths (stubbed only); `pos entertainment send` live-plugin e2e (requires Telegram token); anything requiring root. These are outside the sandbox contract of this suite and remain manual checks.
- **Suite hygiene:** deterministic sorted order, per-test sandbox auto-clean, per-file logs, no network/sudo/system mutations, skip contract, total < 90s.

[PASS]