# AI Server Start Breakage — Root Cause + Fix Design Decisions

**Date:** 2026-09-06
**Architect:** Design pass over the Detective report `AgentsReport/detective/2026-09-06_ai-server-breakage.md` (root cause classified **FACT**).
**Constraint:** No code changes in this pass; decisions + ratified fix scope (F1-F7) for the Builder; test-fixture requirements for the Tester. Preserve the existing Bash tool architecture and the D-A..D-F stabilization decisions.

---

## TL;DR

1. **DQ1 — Validation stays help-gated.** The SIGPIPE race (F2) is the only validation defect; help-based validation is binary-reality-based and correct once deterministic. Version is cosmetic. "unknown" means: validate against real `--help` regardless, message without the version. NO version→capability map. [DECIDED]
2. **DQ2 — `resolve_model` gains file-inside-dir expansion.** `$HF_DOWNLOAD_DIR/<name>`/dir → exactly-one `*.gguf` resolves to it; multiple → list + err ("pick one"); zero → err as today. Also accept `<name>/<file>.gguf`. Precedence: absolute path > dir-with-exactly-one-gguf > `$HF_DOWNLOAD_DIR/<name>.gguf` flat file > `$HF_DOWNLOAD_DIR/<name>/<file>` > relative-as-is. Existing bare-file behavior unchanged (backward compatible). [DECIDED]
3. **DQ3 — User-bus pre-flight by default, plus `--no-unit` direct-run escape hatch (option c).** Pre-flight aborts BEFORE writing the unit (no orphan); `--no-unit` runs the server directly under nohup+pidfile for headless/SSH boxes. Shared helper `ensure_user_bus` lives in `lib/common.sh` (all three tools source it). Matrix-listener + network-download get the same pre-flight. Remediation text includes `export XDG_RUNTIME_DIR=/run/user/$(id -u)` and `sudo loginctl enable-linger $(id -un)`. [DECIDED]
4. **DQ4 — `find_llamacpp` drops bare `server` and `llama.cpp/server`.** Keep `llama-server`, `llama-server-cuda`. Do NOT add `llama-server-mtl` (Mac-only; out of target). Stale-unit: start F4 pre-flight WARNS about an existing unit, does not delete it (never gratuitously remove user state). [DECIDED]
5. **DQ5 — Always pin `--port $PORT`.** Once F2 makes validation reliable, ExecStart always carries `--port $PORT` (help-gated, so a build without `--port` omits it). No adapter probing fallback change needed (deferred). [DECIDED]
6. **DQ6 — Installer sanity IS in scope.** `apps/ai/llamacpp.sh` post-install runs `llama-server --version` (2>&1) + `--help` and errs if the binary doesn't execute; verifies the symlink target exists. [DECIDED]

---

## DQ1: Validation posture when version is unknown

### Decision
**Keep help-based validation as the single source of truth. Do NOT add a version→capability map.** "unknown" means: still validate against the real `--help` output; only the version string in log/error messages is dropped (message proceeds without version).

### Rationale
Help-based validation reflects what the actual installed binary supports — it is always correct once the SIGPIPE race (F2) is fixed, because it peers at real capability output. Adding a version→capability table would introduce a second, version-coupled source of truth that drifts the moment llama.cpp adds/renames flags; its only benefit would be to decorate messages with a version string, which is cosmetic. The version is useful for *debugging* ("which build am I running") but must never gate validation. "unknown" therefore degrades only to "no version in messages", not to "no validation".

### How "unknown" behaves
- `detect_llama_version` returns "unknown" only when `--version` is genuinely unreadable (no binary) — after F1, stderr is captured and the output IS readable for real builds.
- With "unknown", `validate_*_flags` still fetch `--help` and judge flags normally; error texts simply omit the version token.
- F1's broadened regex handles both semver and build-only strings, so "unknown" becomes rare (only truly missing binary/--version).

[DELIVERY: F1 capture-2>&1 + broadened regex; F2 race fix. No capability map.]

---

## DQ2: `resolve_model` directory expansion

### Decision
Extend `resolve_model` (`bin/pos-ai-server:230-264`) to resolve a directory-typed explicit argument when it contains a usable model file, with exact precedence. Interactive `pick_model` stays recursive (already lists flat `.gguf` files one level up via `find -type f`; confirmed at `:210` — it lists each dir's files, so no F3 change needed there).

### Precedence (highest → lowest)
1. **Absolute path** that is a file (`[ -f "$explicit" ]`) — unchanged; if the absolute path is a directory, treat as directory case below.
2. **`$HF_DOWNLOAD_DIR/<name>` is a DIRECTORY** containing exactly one `*.gguf` → resolve to that file. If multiple `*.gguf` → print all and `err "pick one: <name>/<file>"`. If zero → fall through / err (never silently pick).
3. **`$HF_DOWNLOAD_DIR/<name>.gguf` flat file** — unchanged (`[ -f "$candidate" ]`).
4. **`$HF_DOWNLOAD_DIR/<name>/<file>.gguf`** (slug/file form) — resolve to `$HF_DOWNLOAD_DIR/<name>/<file>.gguf`.
5. **Relative-as-is** — unchanged (`[ -f "$explicit" ]`).

### Backward compatibility
Bare existing behavior (flat file path, absolute file path, relative path) is fully preserved — the new directory-expansion branches only fire where the current code would have errored with "Model not found". No silent picking: multiple matches always err with the disambiguating list.

### Exact rule (multiple-gguf dir)
```
if a dir contains >1 *.gguf: print each as "<dirname>/<file>" and err "model dir contains multiple — pick one"
```
This matches the fixture expectation (multi-gguf dir case errors with the file list).

[DELIVERY: F3 resolve_model expansion; no pick_model change.]

---

## DQ3: User-bus failure handling (scope across tools)

### Decision
**Option (c): pre-flight err by default, `--no-unit` direct-run as escape hatch.**

- `ensure_user_bus` helper in **`lib/common.sh`** (the base lib already sourced by all three tools via the fallback chain; it is the natural shared home for a user-bus guard — the alterative, config-ui.sh, is a config/validation lib, not an execution helper, and would be a semantic misfit).
- Wired into the unit-install paths of `bin/pos-ai-server:605`, `bin/pos-communication-matrix-listener:341`, and `bin/pos-network-download:191` — all three call it BEFORE `systemctl --user daemon-reload` and BEFORE the unit is written, so a failure leaves no orphaned unit.
- On failure, `ensure_user_bus` `err`s with remediation text:
  - `export XDG_RUNTIME_DIR=/run/user/$(id -u)` (if the dir exists)
  - `sudo loginctl enable-linger $(id -un)`
  - plus the general "connect to the user's systemd bus" guidance.

### Why nohup/pidfile for `--no-unit` (direct-run)
Headless/SSH boxes may lack a working user bus permanently; being unable to serve a model at all is worse than a supervisor-less process. `--no-unit` on `pos ai server start` execs `llama-server` directly under `nohup ... >$log 2>&1 &`, writes a pidfile under `$RUN_DIR`/`$HF_DOWNLOAD_DIR` sibling (e.g. `$RUN_DIR/pos-ai-server.pid`), and prints the log path + `kill $(cat pidfile)` hint. This is a thin escape hatch, NOT a second supervisor; supervision stays systemd when available.

### Why the helper lives in common.sh (not config-ui)
- All three tools source `lib/common.sh` already (via the `$(dirname)/../lib/common.sh` fallback chain). Config-ui.sh is not guaranteed present in the standalone communication tools' spirit, and it is semantically a *config* lib. An *execution pre-flight* guard belongs with the other `run`/`spawn` execution helpers in common.sh.
- Same one-line helper (declared with a `declare -F` guard like user-timers-lib.sh does) so all three tools share remediation text and behavior, and it can be unit-tested once.

### Minimal viable behavior for THIS pass
- `ensure_user_bus` in common.sh.
- Pre-flight wired into pos-ai-server, matrix-listener, network-download before unit write.
- `--no-unit` direct-run flag on **pos-ai-server only** (the reported tool, and the only one whose unit manages llama-server). matrix-listener and network-download get the pre-flight but NO direct-run escape hatches this pass (their stateful daemons genuinely need systemd; a direct-run fallback would be a larger design change and is deferred).

[DELIVERY: F4 pre-flight + `--no-unit` on pos-ai-server.]

---

## DQ4: `find_llamacpp` candidates

### Decision
New candidate list: **`llama-server`, `llama-server-cuda`** only. Drop bare `server` and `llama.cpp/server`. Do NOT add `llama-server-mtl`.

### Rationale
- Bare `server` is an unrelated-generic-name hazard (fixture-proven: picks an unrelated binary, then ALL defaults rejected) — genuinely dangerous, drop it.
- `llama.cpp/server` is a relative path-like token that `command -v` can only match as a literal filename `llama.cpp/server` — not a real on-PATH name for the archive's `/usr/local/bin/llama-server` layout; it provides no value, drop it.
- `llama-server-cuda` is a genuine distinct binary name for some CUDA-series builds — keep it.
- `llama-server-mtl` is the Apple Metal (macOS) binary name; this repo targets Debian/Ubuntu Linux only (`apps/ai/llamacpp.sh` errors on non-x64/arm64) — out of scope.
- If `llama-server` and `llama-server-cuda` are both absent, the existing `find_llamacpp`-failure `err` already carries the installer hint (unchanged).

### Stale-unit handling on start (F4 interaction)
`cmd_start` pre-flight: if `$USER_SYSTEMD_DIR/$SERVICE` already exists, **warn** that a unit is present (it may be stale/orphaned from a prior failed start) and that it will be overwritten; proceed to write. **Do NOT delete it.** `cmd_stop` (`:628-641`) is the only stated removal path and remains the exclusive way user state is removed. Rationale: deleting on start would gratuitously discard user state (a running, working unit) and would blur the unit's ownership. The pre-flight bus check (DQ3) already prevents NEW orphans, so an existing unit is either intentional or stale-legacy — warn, never auto-remove.

[DELIVERY: F5 candidate list + start stale-unit warning.]

---

## DQ5: Port pinning

### Decision
**Always pin `--port $PORT` in ExecStart** (help-gated). Confirmed: the adapter probes and health check already use `$PORT` (default 8088; llama.cpp default is 8080 per `common/common.h:620`). After F2 makes default-flag validation reliable, `--port` is never spuriously omitted, so the server always binds the port the adapter and health check expect.

### Mechanics
- `--port $PORT` is a DEFAULT flag already emitted at `bin/pos-ai-server:528` guarded by `DEFAULT_PORT_OK`. Once F2 removes the race, `DEFAULT_PORT_OK` is reliably 1 for real builds (which advertise `--port` in `--help`), so `--port $PORT` is pinned.
- Strictly ancient llama-server builds without `--port` in `--help` omit it (help-gated); in that (degenerate) case the adapter's 8088 probe would not match the server's 8080 default. Since such builds are not the supported real release (b10822 ships `--port`, default 8080), this residual path is accepted and documented as the "ancient build" degradation.

### Explicitly deferred
- **Adapter probing fallback** (probe both 8088 and 8080, or derive port from the unit): NOT in scope this pass. With F2+F5, the server and adapter agree on 8088 by construction. Adding a dual-port adapter probe would mask (not fix) a genuine port disagreement and complicate the adapter for a non-path that F5 removes. Deferred with reason.

[DELIVERY: F6 port pinning — achieved via F2+F5; no adapter fallback.]

---

## DQ6: Installer sanity (F7)

### Decision
**In scope.** `apps/ai/llamacpp.sh:46-57` post-install adds a sanity check after the symlink loop:
- Run `llama-server --version` capturing `2>&1` — `err` if the binary doesn't execute (non-zero exit).
- Run `llama-server --help` similarly — `err` if unreadable.
- Verify the symlink target exists: for each `/usr/local/bin/llama*` symlink created, `[ -e "$link" ]` (resolves target) — `err` if broken.

### Rationale
This catches a genuinely broken install (missing shared lib → binary won't run; truncated/empty archive → symlink dangling) at install time with one clear `err`, instead of surfacing as a confusing "version unknown / flags rejected" on the first `pos ai server start`. It is cheap and self-contained in the installer; it is the front door to the whole tool chain and is the natural place to fail fast.

[DELIVERY: F7 installer post-install sanity.]

---

## Ratified Fix Scope (F1-F7)

| # | File:line | Decision | 1-line change |
|---|-----------|----------|---------------|
| **F1** | `bin/pos-ai-server:71` | **KEEP** | Capture `2>&1` and broaden regex to `[0-9]+\.[0-9]+\.[0-9]+|build [0-9]+|b[0-9]+`. |
| **F2** | `bin/pos-ai-server:101,145` | **KEEP** | Replace `printf|grep -q` pipeline with `grep -E -- … >/dev/null <<<"$help_text"` (non-q, no pipe → no SIGPIPE); apply identically to `validate_requested_flags` and `validate_default_flags`. |
| **F3** | `bin/pos-ai-server:230-264` | **KEEP** | `resolve_model` dir-expansion per DQ2 precedence (exactly-one-gguf → resolve; multiple → list+err; commit `$HF_DOWNLOAD_DIR/<name>/<file>` form). |
| **F4** | `bin/pos-ai-server:605` + `:461-626`; `bin/pos-communication-matrix-listener:341`; `bin/pos-network-download:191`; **new** `lib/common.sh` | **KEEP (adjusted)** | Add `ensure_user_bus` to `lib/common.sh`; call before unit write in all three tools (abort, no orphan); plus `--no-unit` direct-run flag on `pos-ai-server`; start pre-flight warns on existing unit (DQ4). |
| **F5** | `bin/pos-ai-server:56` | **KEEP** | `find_llamacpp` candidates → `("llama-server" "llama-server-cuda")`. |
| **F6** | `bin/pos-ai-server:528` (+ no adapter change) | **KEEP** | Confirm `--port $PORT` always pinned (reliably emitted once F2 fixed); no adapter probing fallback. |
| **F7** | `apps/ai/llamacpp.sh:46-57` | **KEEP (in scope)** | Post-install sanity: `llama-server --version` (2>&1) + `--help` execute, symlink targets exist, else `err`. |

## Explicitly deferred (NOT this pass)

1. **Adapter probing fallback** (probe 8088+8080 / derive port from unit) — F6 makes the adapter agree with the server by construction; a dual-port probe would mask (not fix) disagreement. Deferred with reason.
2. **Direct-run escape hatch for matrix-listener and network-download** — stateful daemons genuinely need systemd; a direct-run supervisor is a larger design change. Deferred; only pos-ai-server gets `--no-unit` this pass.
3. **Multi-user / TELEGRAM_GROUP_MODE and DQ-adjacent chat features** — unrelated to this breakage; tracked separately in the stabilization design.
4. **D1 (pos-ai-hf single-file download failure recording)** and **LLAMACPP_HOST coherence (D2)** — separate defects already tracked in the stabilization open-items; not part of this fix map.
5. **`--no-mmap`-style substring false positives beyond the current word-boundary regex** — D4 (already implemented in this file at `:101`); no change needed unless F2 rewrites it, which uses the identical word-boundary pattern.

---

## Test-Fixture Requirements (for Tester)

Per fix from the Detective's fixture spec, deterministically:

- **F1 (version):** fake `llama-server` printing `version: 0.4.0-dev (build 10822, commit …)` **to stderr**, help to stdout → assert `detect_llama_version` returns `0.4.0` (not "unknown"). Also a fixture printing only `version: b10822`/`build 10822` to stderr → assert broadened regex returns the build token.
- **F2 (race + determinism):** fake `llama-server` whose `--help` emits a 59 KB body with `--threads`@line 7, `--ctx-size`@25, `--n-gpu-layers`@140, `--host`/`--port` near end (real llama.cpp layout). Run `validate_default_flags` **N≥20 times under `set -euo pipefail`** → fixed code reports all 5 supported on EVERY run (zero omissions). Regression tail: pre-fix code must fail at least once in the same loop (proves the race existed).
- **F3 (model dir):** fixture `$HF_DOWNLOAD_DIR/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf` (+ `.hf-meta`). Assert `DRY_RUN=1 pos ai server start Qwen-Qwen3-1.7B-GGUF` resolves to the file; multi-gguf dir case errors listing each as `dirname/file`; zero-gguf dir errors as today.
- **F4 (bus):** env with `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` unset (or stub `systemctl` failing with the dbus message) → assert pre-flight `err`s with remediation text (both `export XDG_RUNTIME_DIR=…` and `sudo loginctl enable-linger …`), and **no unit file is written** (no orphan). Assert `--no-unit` path execs the direct command via a stub `llama-server` recording argv + writes pidfile.
- **F5 (server fallback):** PATH containing ONLY an unrelated fake `server` (its own --help/--version), no llama-server → assert `find_llamacpp` does NOT return `server`.
- **F6 (port):** with F2 fixed, `DRY_RUN=1` generate a unit → assert ExecStart always contains `--port 8088` (and `--host`, `--n-gpu-layers`, `--ctx-size`, `--threads`).
- **F7 (installer):** run `apps/ai/llamacpp.sh` against a fixture tar containing a broken binary (missing shared lib) → assert post-install sanity `err`s.
- **E2E regression (reported user scenario):** with stubs (fake `llama-server` b10822-shaped stderr + help, fake systemctl that succeeds only with `XDG_RUNTIME_DIR` set), run install→`pos ai server start Qwen-Qwen3-1.7B-GGUF`→assert the written unit is correct (ExecStart carries all 5 flags + `--port 8088`, no orphan unit, version resolvable).

---

*Deliverables complete. See `AgentsReport/architect/2026-09-06_stabilization-design.md` (appended post-merge section) for the consolidated record.*
