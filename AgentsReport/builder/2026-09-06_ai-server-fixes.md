# Builder Report — llama-server breakage fixes (F1-F7)

**Date:** 2026-09-06
**Builder:** Implementation of Architect DQ1-DQ6 ratified scope F1-F7.
**Bindings:** `AgentsReport/architect/2026-09-06_ai-server-fix-design.md` (FACT), `AgentsReport/detective/2026-09-06_ai-server-breakage.md` (FACT root-cause evidence).

## TL;DR

Status: **IMPLEMENTED** (all F1-F7)

Files changed:
- `bin/pos-ai-server` (F1, F2, F3, F4, F5, F6)
- `lib/common.sh` (F4 — new `ensure_user_bus`)
- `bin/pos-communication-matrix-listener` (F4 — inline + call)
- `bin/pos-network-download` (F4 — call)
- `apps/ai/llamacpp.sh` (F7 — post-install sanity)
- `DOC/POS.md` (minimal — `--no-unit` documented)
- generated docs via `make gen` (`DOC/AGENT_Context_Project.md`, `completions/pos.bash`)

Verification: `bash -n` all touched; probes 1-8 = **63/63 PASS, rc=141 count 0**; `make gen` idempotent x2; `make check` green; `make lint` `0 FAIL, 0 WARN`.

Probe workspace: `/tmp/opencode/ai-probes/` (stubs, fixtures, `run-probes.sh`, `PROBES-RESULT.txt`).

---

## Step 1: F1 — `detect_llama_version` stderr capture + broadened regex

`bin/pos-ai-server:82-90`. Real llama.cpp prints `version: 0.4.0-dev (build 10822, commit …)` to **STDERR**; the old code captured only stdout and regexed `[0-9]+\.[0-9]+\.[0-9]+` alone.

- Both streams captured: `"$bin" --version 2>&1`.
- Regex accepts `X.Y.Z` OR `build [0-9]+` OR `b[0-9]+` (old builds).
- `"${version#build }"` strips the phrase so `build 10822` displays as `10822`.
- Guarded: missing binary / unreadable output → `unknown` (no errexit).

Evidence (P1): stderr semver → `0.4.0`; `build 10822` (stderr) → `10822`; `b10822` → `b10822`; missing binary → `unknown`. [DONE]

## Step 2: F2 — pipe-less flag validation (no rc=141 race)

`bin/pos-ai-server:97-124` (`validate_requested_flags`), `:135-170` (`validate_default_flags`). Old form `printf '%s' "$help_text" | grep -qE ...` died of SIGPIPE (rc=141) when the >64KB pipe-adjacent grep exited at the first match — valid flags sporadically judged unsupported. New form: non-quiet `grep -E -- "(^|[[:space:]])${flag}([[:space:]]|=|$)" <<<"$help_text" >/dev/null` (herestring needs no pipe; non-q grep consumes the whole input; same word-boundary regex and guard shape).

Evidence (P2): on the 58,362-byte/732-line fixture help, 25 runs of `validate_default_flags` → all 5 defaults kept every run, `rc=141` count **0**; requested-flag path: supported `--port` rc 0, unsupported flag rc 1 with version-aware err. [DONE]

## Step 3: F3 — `resolve_model` directory expansion (never silently pick)

`bin/pos-ai-server:213-264` + helper `resolve_gguf_in_dir` (`:196-210`). DQ2 precedence: absolute file → absolute dir with exactly one `.gguf` → `$HF_DOWNLOAD_DIR/<name>/<file>.gguf` (slug/file form) → `$HF_DOWNLOAD_DIR/<name>.gguf` (flat file) → relative-as-is. A dir with multiple `.gguf`s errors listing each as `<dirname>/<file>` + "pick one"; zero `.gguf`s falls through to the today's `Model not found:` err.

Evidence (P3): single-gguf dir resolves; slug/file form resolves; multi-gguf errors listing both files + "pick one"; empty dir → rc 1 with today's `Model not found: empty-dir` text. [DONE]

## Step 4: F4 — `ensure_user_bus` + `--no-unit` escape hatch

`lib/common.sh` (new `ensure_user_bus`, after `confirm()`): `systemctl --user show-environment` reachability probe; on failure `err` with BOTH remediation lines (`export XDG_RUNTIME_DIR=/run/user/$(id -u)` and `sudo loginctl enable-linger $(id -un)`) + "no unit was written". Called:

- `bin/pos-ai-server` `cmd_start` (before DRY_RUN return; only when `--no-unit` not given). `--no-unit` flag: added to `# POS_FLAGS:`, parse case, usage; direct run via `eval "nohup $exec_cmd >'$NO_UNIT_LOG' 2>&1 &"`, pidfile/log under `${XDG_RUNTIME_DIR:-/tmp}`; `cmd_stop`/`cmd_status` pidfile-aware (`kill -0`, `^[0-9]+$` guard).
- `bin/pos-communication-matrix-listener` — **factually does NOT source `lib/common.sh`** (inline `err`/`log`/`warn` at lines 19-21); got an inline `declare -F ensure_user_bus`-guarded duplicate + call in `enable_service` (architect's "all three source common.sh" premise was wrong; sourcing it would redefine helpers with colors and change output).
- `bin/pos-network-download` `cmd_start` else-branch (first statement before unit write).

Evidence (P4): with `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` unset and a failing `systemctl` stub: pos-ai-server DRY_RUN start rc 1 with both remediation lines and **no unit written**; matrix-listener `--enable` rc 1, no unit; network-download `start` rc 1, no unit. [DONE]

## Step 5: F5 — `find_llamacpp` candidate narrowing

`bin/pos-ai-server:56-61`. Candidates narrowed to `("llama-server" "llama-server-cuda")` (dropped bare `server` and `llama.cpp/server` which had previously matched unrelated binaries). Stale-unit overwrite warn added in start; user unit state never deleted.

Evidence (P5): PATH containing only an unrelated binary named `server` → `find_llamacpp` returns nothing, rc 1; stub `llama-server` → rc 0, returns `llama-server`. [DONE]

## Step 6: F6 — port pinning preserved (no change needed, verified)

Verified via P6: DRY_RUN start with the b10822-shaped stub help → ExecStart contains all 5 defaults (`--host 127.0.0.1`, `--port 8088`, `--n-gpu-layers`, `--ctx-size 4096`, `--threads`) and the version resolves to `0.4.0` (not `unknown`). [DONE]

## Step 7: F7 — llamacpp.sh post-install sanity

`apps/ai/llamacpp.sh`: new `llamacpp_sanity()` (seam `LLAMACPP_BIN_DIR="${LLAMACPP_BIN_DIR:-/usr/local/bin}"`), called after install `spawn`. Verifies: `[ -e "$bin" ]` (catches dangling symlink), `command -v llama-server`, `llama-server --version >/dev/null 2>&1`, `llama-server --help >/dev/null 2>&1`; on success logs `llama.cpp sanity OK`.

Evidence (P7): normal fixture → rc 0 + OK log; dangling-symlink fixture → rc 1 with "dangling symlink"; missing-shared-lib fixture → rc 1 with the binary's stderr text. [DONE]

## Step 8: E2E user scenario

Evidence (P8): positive (bus env set, `systemctl` stub succeeds): `pos ai-server start Qwen-Qwen3-1.7B-GGUF` rc 0, unit written with `--port 8088`, all 4 other defaults, model path expanded from dir, **no "unknown" version anywhere in start output**. SSH-shaped (no bus env, failing stub): rc 1 with both remediation lines, **no orphan unit**. [DONE]

## Gates

| Gate | Result |
|---|---|
| `bash -n` on 5 touched scripts | pass (pos-ai-server, common.sh, matrix-listener, network-download, llamacpp.sh) |
| `make gen` x2 | rc 0 both; `git diff` identical → **idempotent** |
| `make check` | `check-sync: OK` |
| `make lint` | `0 FAIL, 0 WARN (convention lint)` |
| Probes 1-8 | **63 PASS / 0 FAIL / rc=141 count 0** |

## Scope compliance

- Touched exactly the in-scope files (pos-ai-server, common.sh, matrix-listener, network-download, llamacpp.sh, DOC/POS.md, gen output). `tests/`, `scripts/lint-conventions.sh`, `bin/pos-system-uninstall`, `lib/config-ui.sh` untouched.
- Unrelated pre-existing dirty file `AgentsReport/architect/2026-09-06_stabilization-design.md` NOT modified by Builder.
- No commits made.

## Residual risks / known deviations

1. `--no-unit` direct run uses `eval "nohup $exec_cmd … &"` — tool-generated string; only binary (validated by `command -v`) and model (validated path) tokens are interpolated, both quoted; matches the namespace's bash DNA.
2. F1 displays `build 10822` as `10822` via `"${version#build }"` — slight deviation from the architect's literal regex output wording, required to match probe 1's `10822` expectation; behavior documented at `bin/pos-ai-server:75-81`.
3. `matrix-listener` carries an inline duplicate of `ensure_user_bus` (guarded by `declare -F` so the shared one wins if ever sourced) — the file deliberately does not source common.sh (would change helper output). If a future task refactors matrix-listener to source common.sh, the inline copy can be deleted.
4. E2E positive run writes/overwrites a unit under `$USER_SYSTEMD_DIR` only inside the probe workspace — no real system units touched, no processes spawned (stubs only).
5. Runtime flags validated by grep use `>`-redirected non-quiet grep instead of `grep -q`: a 58KB fixture costs ~1-2ms per flag — negligible for a unit-write path.

Recommended next agent: **Reviewer** (independent adversarial review of the F1-F7 diff before acceptance).