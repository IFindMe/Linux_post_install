# tests/ — regression test suite

Zero-dependency Bash regression tests for the Linux_post_install repository.

## Run

```bash
make test          # discover tests/t-*.sh, run everything
./tests/run-tests.sh                     # same
./tests/run-tests.sh t-telegram-auth.sh  # run one file
```

Exit code is non-zero if any check failed. The suite is designed to be
deterministic: tests stub every external dependency they touch (curl, gpg,
sudo, systemctl, llama-server, nvidia-smi…) and run against sandbox temp
dirs. No network, no sudo, no system changes.

## Adding a test

1. Create `tests/t-<what>.sh` with a `run_test()` function. `set -euo pipefail`
   is already active (the runner re-asserts it); `$ROOT` is the repo root,
   `$TEST_TMP` a per-test temp dir that is cleaned automatically.
2. Use the helpers in `tests/test-lib.sh` for every assertion:
   `check`, `check_eq`, `check_rc`, `check_contains`, `check_not_contains`,
   `check_file_exists`, `check_file_absent`, `test_run` / `test_run_env`,
   `mksandbox`, `tracked_tree_copy`, `count_token`.
3. If a case cannot run in the current environment (missing binary, missing
   analyzer), call `skip_case "<desc>" "<reason>"` — never fake a pass and
   never silently return.
4. Keep total suite runtime under 90 seconds.

## Skip contract (hard)

A test that cannot run must say `[SKIP] reason`. The runner counts skips in
the summary and a file whose `run_test()` produced zero checks and zero skips
is reported as FAIL ("no assertions") — a broken harness can never pass
silently.

## Suite contents

| File | What it verifies |
| --- | --- |
| `t-ai-server-flags.sh` | `pos-ai-server` ExecStart flag set: defaults, CLI, config, dedupe, one-token-per-flag |
| `t-ai-hf-download.sh` | `pos ai hf download` success + failure honesty (no `.hf-meta` on partial failure, rc != 0) |
| `t-ai-key-resolution.sh` | `pos ai` API-key contract: provider key > legacy `AI_API_KEY` fallback > error; leakage guard, env-wins, providers status sync |
| `t-ai-llama-detect.sh` | `pos ai-server status` version detection, "unknown", missing-binary failure |
| `t-unsupported-flags.sh` | unsupported-option handling: CLI/config/env hard errors, dropped defaults, word-boundary match |
| `t-systemd-unit.sh` | generated unit: one ExecStart, quoted paths, `systemd-analyze verify` |
| `t-telegram-auth.sh` | Telegram listener chat+owner gate and owner-unset fail-closed |
| `t-matrix-auth.sh` | Matrix listener room+owner gate and room-unset fail-closed |
| `t-gpg-password.sh` | backup passphrase on fd 3 (never argv), plaintext/corrupt cleanup |
| `t-config-precedence.sh` | `load_env_file` contract + CLI > env > file > defaults across tools |
| `t-uninstall-manifest.sh` | install.sh ↔ POS_LIBS symmetry, user-unit discovery, marker-driven plugin removal |
| `t-gen-docs-drift.sh` | `make gen` idempotence on a pristine tracked tree (CI drift gate) |
| `t-lint-gate.sh` | `make lint` green on the real tree; planted violations are caught and named |
| `t-install-version.sh` | install.sh version gate: match→skip, mismatch→proceed, --force bypass, dry-run variant, flag write, numeric comparison |
| `t-share-mountpoint.sh` | share-client `ask_mountpoint` UX: existing/new/declined/rejected paths, confirm gate, mkdir side effects, non-TTY stdin contract, static `n`→`t` guards |
| `t-pos-media-yt.sh` | unified `pos media yt` suite: dispatcher + forwarder resolution, shared yt-lib helpers, yt-mp3/mp4/grab/subtitles flags, dry-run deps, `YT_OUT_DIR` seam, `GRAB_DEFAULT` config, negative controls (unsafe-URL no-expansion, `--lang en,ar` single arg, txt timestamp-stripping) |
| `t-telegram-listener-singleton.sh` | Telegram listener single-instance guard: first `--run` acquires the flock, second `--run` fails fast with the exact message, lock auto-releases so the next start is clean, `--status` reports the lock state |
| `t-telegram-listener-reap.sh` | Telegram listener crash-loop regression: non-zero (254) child exit no longer kills the daemon, reply carries the real exit code + output, negative control proves the old `wait`-under-`set -e` idiom dies, getUpdates offset persists across restarts (resume, invalid-state fallback, empty-batch no-write) |
| `t-bank.sh` | Command Bank: bank-lib.sh unit tests (add/remove/update/find/get/list/count/valid/extract_params/substitute_params, multiline `\n` storage round-trip, literal-`\n` escape round-trip, v1 backward compat) + pos system bank CLI integration (help, list, add, show, run, remove, params, invalid name, multiline show/run) + `alias` subcommand (managed `~/.bashrc` block, exact line format, idempotent create, retarget, list, remove, block cleaned when empty, outer collision refused w/ file untouched, PATH-shadow warn, invalid alias name, unknown command, `bank remove` drops aliases, unrelated bashrc content preserved byte-identically, malformed block, empty-block message) |
| `t-share-webdav.sh` | `pos share webdav` (rclone): dispatch/deps/paths/flag/auth failures, DRY_RUN share/enable happy paths, addr precedence, TLS advisory matrix, masked status/list, webdav.env origin, ufw advisory, 644 unit + 600 env persistence, bus pre-flight orphan guard, idempotent unshare/disable, live spawn+list (restart + unshare-stop asserted live), sentinel-leak tripwire + fail-closed guards |