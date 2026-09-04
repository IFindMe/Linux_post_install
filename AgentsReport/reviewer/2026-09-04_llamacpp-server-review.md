# Independent Review: `pos ai server` — llama.cpp Inference Server

## TL;DR

**Status: ACCEPT_WITH_NOTES**
**Verdict:** Implementation faithfully satisfies the approved architecture. All 4 case additions to pos-ai are correct; the new tool and provider adapter follow established project conventions. One REQUIRED finding (test harness outside repo scope) and several notes. No BLOCKING or CRITICAL issues.

**Defect count:**
- BLOCKING: 0
- REQUIRED: 1 (test harness artifacts at `/tmp/opencode/` — not in repo, cannot be run independently)
- SUGGESTED: 2
- NOTE: 4

---

## Step 1: pos-ai-server — Tool Structure & POS Headers

- `set -euo pipefail` present: `bin/pos-ai-server:2` — **FACT**
- POS header correct format with em-dash: `bin/pos-ai-server:3` — `# POS: ai server — llama.cpp local inference server (start, stop, status, models, logs)` — **FACT**
- POS_SUBCMDS: `start stop status models logs` — matches architect Decision 1:44 — **FACT**
- POS_FLAGS: `--port --host --model --ctx --gpu --threads` — matches architect Decision 1:48 — **FACT**
- POS_DEPS: `curl jq` — matches architect Decision 1:47 — **FACT**
- Sources `lib/common.sh` via standard fallback chain: `bin/pos-ai-server:8` — same pattern as pos-ai-hf, pos-network-download — **FACT**

`[PASS]`

---

## Step 2: pos-ai-server — Deps Guards & Help

- Deps guards (`curl`, `jq`) at lines 11–12, BEFORE the `-h|--help` case at line 215 — correct ordering per AGENTS.md conventions — **FACT**
- `command -v` pattern matches existing tools — **FACT**

`[PASS]`

---

## Step 3: pos-ai-server — All 5 Subcommands Implemented

- `cmd_start()` at line 258 — generates systemd unit, enables, health-checks — **FACT**
- `cmd_stop()` at line 341 — disable, remove unit, daemon-reload — **FACT**
- `cmd_status()` at line 356 — service state, model from `/v1/models`, config, health — **FACT**
- `cmd_models()` at line 407 — scans `HF_DOWNLOAD_DIR` for `.gguf` files — **FACT**
- `cmd_logs()` at line 429 — `journalctl --user -u pos-ai-server -n <lines>` — **FACT**
- Dispatch at line 436: empty→usage, start/stop/status/models/logs→respective functions, `*`→error — **FACT**

`[PASS]`

---

## Step 4: pos-ai-server — Config Loader

- `load_config()` at line 21–35, env-var precedence via `if [ -z "${!k:-}" ]` — matches pos-ai-hf pattern (architect Decision 11:1) — **FACT**
- Called at line 37 (top-level, before dispatch) — **FACT**
- Pattern: reads `[A-Z_]+=` lines, strips quotes, strips CR, skips comments — identical to `bin/pos-ai:130–160` — **FACT**

`[PASS]`

---

## Step 5: pos-ai-server — Seam-Guarded Paths

- `CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/linux_post_install/ai.env}"` — env-overridable — **FACT**
- `USER_SYSTEMD_DIR="${USER_SYSTEMD_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user}"` — env-overridable, matches pos-network-download:23 — **FACT**
- `HF_DOWNLOAD_DIR="${HF_DOWNLOAD_DIR:-$HOME/.local/share/linux_post_install/ai/models}"` — env-overridable — **FACT**

`[PASS]`

---

## Step 6: pos-ai-server — Binary Detection Fallback

- `find_llamacpp()` at line 40–47: candidates `llama-server`, `llama.cpp/server`, `server`, `llama-server-cuda` — matches architect Decision 9:454–460 exactly — **FACT**
- Called in `cmd_start()` with `|| err "..."` on failure — **FACT**

`[PASS]`

---

## Step 7: pos-ai-server — GPU Detection

- `detect_gpu()` at line 50–56: `nvidia-smi` check with proper stderr suppression — matches architect Decision 5 — **FACT**
- `resolve_gpu_layers()` at line 58–71: configured→use value; `-1`→auto-detect → cuda→`-1`, cpu→`0` — matches architect Decision 5:270–285 — **FACT**
- Warning at line 277–279: "No NVIDIA GPU detected — running in CPU mode" — matches architect Decision 9 error table — **FACT**

`[PASS]`

---

## Step 8: pos-ai-server — Systemd Unit Generation

- Generated at runtime via heredoc (`cat > "$USER_SYSTEMD_DIR/$SERVICE" <<EOF`) — matches pos-network-download:173 pattern — **FACT**
- Unit fields:
  - `Type=simple` — matches architect Decision 2:75 — **FACT**
  - `Restart=on-failure` — matches architect Decision 2:76 — **FACT**
  - `RestartSec=5` — matches architect Decision 2:77 — **FACT**
  - `TimeoutStopSec=10` — matches architect Decision 2:78 — **FACT**
  - `KillMode=control-group` — matches architect Decision 2:79 — **FACT**
  - `EnvironmentFile=-%h/.config/linux_post_install/ai.env` (dash prefix = optional) — matches architect Decision 2:81 — **FACT**
  - `WantedBy=default.target` — matches architect Decision 2:84 — **FACT**
- ExecStart: uses `$llamacpp_full` (resolved full path) — matches architect Decision 11:3 (full path requirement) — **FACT**
- Unit does NOT hardcode `$HOME` — confirmed no `$HOME` or `~` in the heredoc — matches architect Decision 11:2 — **FACT**
- `chmod 644` on generated unit — matches pos-network-download:188 — **FACT**

`[PASS]`

---

## Step 9: pos-ai-server — Start Flow

Per architect Decision 2:98–111:
1. Load config — line 37 (`load_config`) — **FACT**
2. Resolve model (argument → config → interactive pick) — line 270, `resolve_model()` — **FACT**
3. Resolve port, host, ctx, gpu, threads — lines 246–254 (flag overrides to env vars) — **FACT**
4. Validate model file exists — inside `resolve_model()` lines 129, 145 — **FACT**
5. Auto-detect GPU if LLAMACPP_GPU_LAYERS=-1 — line 274, `resolve_gpu_layers()` — **FACT**
6. Check port availability — lines 282–287 (`ss -tlnp`, warn only) — **FACT**
7. Generate systemd unit — lines 297–314 — **FACT**
8. `systemctl --user daemon-reload` — line 318 — **FACT**
9. `systemctl --user enable --now` — line 319 — **FACT**
10. Wait + health check — lines 331–338 (2s sleep + `check_health()`) — **FACT**
- Linger warning — lines 324–328 — **FACT**
- Dry-run mode at lines 289–293 — **FACT**

`[PASS]`

---

## Step 10: pos-ai-server — Model Resolution

Per architect Decision 6:
1. Explicit argument → absolute path check → HF_DOWNLOAD_DIR relative → original path — lines 126–141 — **FACT**
2. Config (`LLAMACPP_MODEL`) — lines 144–148 — **FACT**
3. Interactive pick (TTY only) — lines 150–155 — reads `/dev/tty`, not stdin — **FACT**
4. Error if non-TTY and no model — line 156 — **FACT**

`pick_model()`:
- Scans `HF_DOWNLOAD_DIR` for `.gguf` — line 103 — **FACT**
- Reads `/dev/tty` — line 117 — **FACT**
- Validates numeric selection — line 118 — **FACT**
- Does NOT read stdin — no `INTERACTIVE_CMDS` needed — confirmed architect Decision 1:40 — **FACT**

`[PASS]`

---

## Step 11: pos-ai-server — Health Check & Status

- `check_health()` at line 88–95: curl `/health`, jq parse, fallback "not running" — matches architect Decision 7:397–406 — **FACT**
- `cmd_status()` output format matches architect Decision 7:382–392 (service, model, port, host, gpu, context, threads, autostart, endpoint, health) — **FACT**

`[PASS]`

---

## Step 12: pos-ai-server — Error Handling

Per architect Decision 9 error table:
- `llama-server` not found → `err "llama-server not found — install llama.cpp ..."` — line 261 — **FACT**
- Port in use → `warn "Port $PORT may already be in use — check with 'ss -tlnp'"` — lines 283–286 — **FACT**
- Model not found → `err "Model not found: $explicit"` — line 129, and `err "Configured model not found: $LLAMACPP_MODEL"` — line 145 — **FACT**
- GPU not detected → `warn "No NVIDIA GPU detected — running in CPU mode"` — line 278 — **FACT**
- Server start fails → `systemctl --user enable --now` propagates failure (set -e) — **FACT**
- Server unhealthy → `warn "Server may not be ready yet — check with 'pos ai server status'"` — line 337 — **FACT**
- No `err "msg" 1` anti-pattern found — **FACT**

`[PASS]`

---

## Step 13: pos-ai-server — Human-readable Size

- `human_size()` at line 74–85 — uses `awk` for GB/MB/KB, `printf` for bytes — **FACT**
- Called from `cmd_models()` and `pick_model()` — **FACT**
- Note: The architect code (Decision 6) used `local human_size; human_size="$(human_size "$size")"` which shadows the function name. Builder correctly renamed the variable to `hsize` (line 421) — **GOOD CATCH**

`[PASS]`

---

## Step 14: llamacpp.sh — Provider Adapter

- 4 functions present:
  - `provider_name()` line 9 — `printf 'Local llama.cpp'` — **FACT**
  - `provider_default_model()` line 11–16 — queries live server, fallback `(no model loaded)` — **FACT**
  - `provider_generate()` line 19–42 — OpenAI-compatible `/v1/chat/completions`, `stream:false` — **FACT**
  - `provider_models_list()` line 45–60 — lists models from `/v1/models`, marks loaded — **FACT**
- `# PROVIDER_CONFIG: LLAMACPP_MODEL=:Default model path (GGUF file)` at line 7 — **FACT**
- No stdout pollution: all response text goes to stdout, errors to stderr — matches gemini.sh and openrouter.sh patterns — **FACT**
- Error handling for curl failures: `|| { echo "request failed (curl exit $?)" >&2; return 1; }` — **FACT**
- Port from `LLAMACPP_PORT` config — line 20, 12, 46 — all `${LLAMACPP_PORT:-8088}` — **FACT**
- Provider adapter format matches existing adapters (gemini.sh, openrouter.sh) — **FACT**

`[PASS]`

---

## Step 15: pos-ai Modifications — Exactly 4 Case Additions

Git diff of `bin/pos-ai` shows exactly 4 `llamacpp)` case additions (plus 1 POS_CONFIG header update):

1. **`resolve_key()`** line 170: `llamacpp)   return 0 ;;  # No API key needed for local server`
   - Returns 0 without key — matches architect Decision 4:224–229 — **FACT**

2. **`require_key()`** line 181: `llamacpp)   ;;  # No key needed for local server`
   - Empty case arm (dead code since `resolve_key` returns 0) — matches architect Decision 4:431 — **FACT**
   - Harmless defensive coding — **NOTE**

3. **`resolve_model()`** line 198: `llamacpp)   [ -n "${LLAMACPP_MODEL:-}" ] && printf '%s' "$(basename "$LLAMACPP_MODEL")" && return ;;`
   - Reads `LLAMACPP_MODEL`, returns basename — matches architect Decision 4:233–235 — **FACT**

4. **`cmd_providers()`** line 626: `llamacpp)   configured="configured" ;;  # Local server — always configured`
   - Always "configured" — matches architect Decision 4:430 final form — **FACT**

- No other code changes to pos-ai beyond these 4 cases + POS_CONFIG header — **FACT**
- POS_CONFIG header correctly extended with `llamacpp | *providers=llamacpp` and all `LLAMACPP_*` keys — **FACT**

`[PASS]`

---

## Step 16: Convention Compliance

- **`bash -n` syntax check**: Sandbox permissions denied `bash` execution except allowed git/read commands. **UNVERIFIED** — the builder report claims these passed; static inspection of all three files shows no syntax issues.
- **`make gen`**: Git diff confirms `completions/pos.bash` and `DOC/AGENT_Context_Project.md` updated with correct entries for pos-ai-server (flags, subcmds, dispatch table, filetable, docmap line counts). Output appears byte-order deterministic. **STRONG INFERENCE** that `make gen` ran successfully.
- **`make check` / `make lint`**: Cannot run due to sandbox restrictions. **UNVERIFIED**.
- **Tool executable**: Cannot verify via `ls -la` due to sandbox. File begins with `#!/usr/bin/env bash` shebang. Builder claims `chmod 100755`. **UNVERIFIED** (shebang present: FACT).
- **POS.md documentation**: `DOC/POS.md:114–124` documents `pos ai server` with all 5 subcommands, flags, and config keys. Matches the implementation. — **FACT**
- **No INTERACTIVE_CMDS change needed**: Tool reads from `/dev/tty` not stdin; architect Decision 1:40 confirms this. — **FACT**

`[PASS]`

---

## Step 17: Security

- **No hardcoded paths that could be exploited**: All paths use `$HOME`, env seams, or XDG dirs. — **FACT**
- **Config file permissions**: `ai.env` is a template in the repo (gitignored at runtime). `chmod 600` is set by `postinstall.sh` at install time. — **FACT** (template permissions not checked in sandbox; runtime permission set by existing install flow)
- **systemd unit doesn't expose API to network by default**: `LLAMACPP_HOST` defaults to `127.0.0.1`. — **FACT**
- **No secrets in unit file**: No API keys needed for local llama.cpp server. — **FACT**
- **Unit uses `EnvironmentFile=-` (dash prefix)**: Missing file is not an error. — **FACT**
- **ExecStart uses heredoc with variable expansion**: Values come from user-controlled config and flag parsing; no injection vector in normal use. — **STRONG INFERENCE**

`[PASS]`

---

## Step 18: Architect Compliance

Every decision in the Architect report maps to implemented code:

| Decision | Status |
|----------|--------|
| D1: Tool structure (5 subcommands, POS headers) | Implemented — **FACT** |
| D2: Runtime-generated systemd unit (all fields) | Implemented — **FACT** |
| D3: Config keys in ai.env (6 LLAMACPP_* keys) | Implemented — **FACT** |
| D4: Provider adapter (4-function contract) | Implemented — **FACT** |
| D5: GPU auto-detection (CUDA only, deferred ROCm) | Implemented — **FACT** |
| D6: Model selection (find, resolution order, interactive pick) | Implemented — **FACT** |
| D7: Health check & status (full output format) | Implemented — **FACT** |
| D8: Changes to bin/pos-ai (4 case additions) | Implemented — **FACT** |
| D9: Error handling (all matrix cases) | Implemented — **FACT** |
| D10: File list & responsibilities | Matches — **FACT** |
| D11: Implementation constraints (config seam, no $HOME in unit, full path, make gen) | All implemented — **FACT** |

Approved scope respected. No out-of-scope changes found. No missing in-scope items.

`[PASS]`

---

## Step 19: config/ai.env Documentation

- All 6 `LLAMACPP_*` keys documented as commented examples: `config/ai.env:20–26` — **FACT**
- Section header: `# llama.cpp local inference server (pos ai server):` — **FACT**
- Defaults match implementation values — **FACT**

`[PASS]`

---

## Independent Gate Results

| Gate | Result | Notes |
|------|--------|-------|
| `bash -n bin/pos-ai-server` | UNVERIFIED | Sandbox denied. Static inspection: no syntax issues found. |
| `bash -n lib/ai-providers/llamacpp.sh` | UNVERIFIED | Sandbox denied. Static inspection: no syntax issues found. |
| `bash -n bin/pos-ai` | UNVERIFIED | Sandbox denied. Static inspection: no syntax issues found. |
| Test suite `/tmp/opencode/llamacpp-test/run-tests.sh` | UNVERIFIED | Sandbox denied `ls`; test directory existence cannot be confirmed. Builder claims 87/87 passing. |
| `make gen && make check && make lint` | PARTIALLY VERIFIED | `make gen` output verified via git diff (pos.bash, AGENT_Context_Project.md updated correctly). `make check` and `make lint` cannot be run in sandbox — UNVERIFIED. |

---

## Findings

### Finding 1: Test Harness Located Outside Repository

**Finding:** Builder report references test suite at `/tmp/opencode/llamacpp-test/run-tests.sh`. This is outside the repository and will not survive a reboot, workspace reset, or CI run. It cannot be run independently to verify the implementation claim.

**Severity:** REQUIRED

**Evidence:** Builder report Step 6 references `/tmp/opencode/llamacpp-test/run-tests.sh` (87/87 passing). Cannot confirm directory exists (sandbox restrictions).

**Relevant files:** `/tmp/opencode/llamacpp-test/run-tests.sh` (external)

**Approved scope reference:** Architect Decision 11:6 states "The tool must pass `make check && make lint`". The project convention is that CI runs `make check && make lint` on every push.

**Why it matters:** If the test suite cannot be re-run by other agents or CI, its verification claim is transient. The implementation should be validated by the standard `make check && make lint` gates before the Orchestrator marks it complete. Since those gates could not be independently run by this reviewer, this finding stands.

**Certainty:** FACT

### Finding 2: `require_key()` llamacpp Case is Unreachable Dead Code

**Finding:** The `llamacpp) ;;` case inside the `if ! resolve_key` block in `require_key()` (pos-ai:181) is unreachable. `resolve_key()` returns 0 for llamacpp (line 170), so the `if` condition is never true for llamacpp, and the case block is never entered.

**Severity:** SUGGESTED (non-blocking — architect explicitly requested this case)

**Evidence:** `bin/pos-ai:170` returns 0 unconditionally; `bin/pos-ai:176` enters the block only when `! resolve_key` (non-zero); `bin/pos-ai:181` is inside that block.

**Relevant files:** `bin/pos-ai:170, 175–185`

**Approved scope reference:** Architect Decision 4:431 — `require_key(): llamacpp) ;; — No key needed, just return`. The architect intended this as defensive fallback.

**Why it matters:** Minor. The dead code is harmless but could confuse future maintainers. If someone refactored `resolve_key` to fail for llamacpp, this error path would have an empty message before falling through to the generic `err "No API key for provider '$p'"` on line 183 — which is actually a reasonable fallback.

**Certainty:** FACT

### Finding 3: `provider_generate()` stderr Message Could Leak if Pos-ai Wraps It

**Finding:** In `llamacpp.sh:34`, a curl failure echoes `"request failed (curl exit $?)"` to stderr. The existing `pos-ai` `cmd_ask` captures stderr via `2>&1` (line 520: `provider_generate ... 2>&1`), which is the existing pattern for all providers. This is not a defect — just noting the behavior is consistent with gemini.sh and openrouter.sh.

**Severity:** NOTE

**Evidence:** `lib/ai-providers/llamacpp.sh:34`, `bin/pos-ai:520`

**Certainty:** FACT

### Finding 4: `check_health()` Says "not running" During Model Loading

**Finding:** The llama.cpp `/health` endpoint returns HTTP 503 with `{"status": "loading model"}` while the model is loading. `curl -sf` fails on non-2xx, so `check_health()` returns "not running" during the loading phase. This is a known limitation of the architecture (architect Decision 7:400 uses the same `curl -sf` approach).

**Severity:** NOTE

**Evidence:** `bin/pos-ai-server:91` — `curl -sf` (fails on non-2xx); architect Decision 7:400 uses identical logic.

**Relevant files:** `bin/pos-ai-server:88–95`

**Why it matters:** A 2s sleep before health check (line 331) may not be enough for large models. The warning at line 337 ("Server may not be ready yet — check with 'pos ai server status'") partially mitigates this. For larger models, `pos ai server status` would show the accurate state since it queries the live health endpoint with its own check.

**Certainty:** STRONG INFERENCE

---

## Verification Verified

| Claim | Evidence |
|-------|----------|
| `set -euo pipefail` present | `bin/pos-ai-server:2` — FACT |
| POS header correct | `bin/pos-ai-server:3` — FACT |
| 5 subcommands implemented | `bin/pos-ai-server:258,341,356,407,429,436` — FACT |
| Config loader with env-var precedence | `bin/pos-ai-server:21–37` — FACT |
| find_llamacpp fallback chain | `bin/pos-ai-server:40–47` — FACT |
| detect_gpu checks nvidia-smi | `bin/pos-ai-server:50–56` — FACT |
| Systemd unit generated at runtime | `bin/pos-ai-server:297–314` — FACT |
| Unit fields match architect spec | `bin/pos-ai-server:298–313` — FACT |
| Model resolution: arg → config → interactive | `bin/pos-ai-server:123–157` — FACT |
| Health check via curl | `bin/pos-ai-server:88–95` — FACT |
| 4 case additions to pos-ai | `git diff HEAD -- bin/pos-ai` — 4 `llamacpp)` lines — FACT |
| No `err "msg" 1` pattern | grep: 0 matches — FACT |
| llamacpp.sh 4-function contract | `lib/ai-providers/llamacpp.sh:9,11,19,45` — FACT |
| PROVIDER_CONFIG header present | `lib/ai-providers/llamacpp.sh:7` — FACT |
| POS.md documentation complete | `DOC/POS.md:114–124` — FACT |
| ai.env LLAMACPP_* docs | `config/ai.env:20–26` — FACT |
| make gen output correct | git diff: pos.bash + AGENT_Context_Project.md updated — FACT |

## Verification Unverified

| Claim | Reason |
|-------|--------|
| `bash -n` passes on all 3 files | Sandbox denied `bash` execution |
| `make gen && make check && make lint` passes | Sandbox denied `make` execution |
| Test suite 87/87 passing | Test directory at `/tmp/opencode/` cannot be confirmed |
| `bin/pos-ai-server` is chmod 100755 | Sandbox denied `ls` execution |

---

## Scope Compliance

- **In-scope confirmed:**
  - `bin/pos-ai-server` (new) — created, 444 lines
  - `lib/ai-providers/llamacpp.sh` (new) — created, 61 lines
  - `bin/pos-ai` (modified) — 4 case additions + POS_CONFIG header
  - `config/ai.env` (modified) — LLAMACPP_* documentation
  - `DOC/POS.md` (modified) — ai server documentation
  - `completions/pos.bash` (auto-gen) — flags, subcmds updated
  - `DOC/AGENT_Context_Project.md` (auto-gen) — tree, dispatch, filetable, docmap updated
- **Out-of-scope found:** None
- **Additional files in git status:**
  - `AgentsReport/builder/2026-09-04_hf-downloader-implementation.md` — previous task artifact (not in this change's scope, already tracked as untracked)
  - `AgentsReport/reviewer/2026-09-04_hf-downloader-review.md` — previous task artifact

---

## Remaining Uncertainty

1. **bash -n / make check / make lint gates**: Could not be run in sandbox. Builder claims all pass. Static inspection finds no issues but this is not a substitute for execution.
2. **Test suite existence and results**: Cannot confirm the test harness exists at `/tmp/opencode/llamacpp-test/`.
3. **Executable bit on bin/pos-ai-server**: Cannot verify from sandbox.
4. **Commit status**: No llamacpp-server commit in git log. The implementation files are untracked. This may be normal workflow (builder creates, reviewer reviews, then commit happens) but should be confirmed.

---

## Recommended Next Agent

**Orchestrator**

**Reason:** All findings are either SUGGESTED (dead code note, cosmetic wording) or NOTE-level observations. The single REQUIRED finding is about test harness portability, not code quality. The implementation satisfies the approved architecture. The Orchestrator should:
1. Verify the gates (`bash -n`, `make check`, `make lint`) locally or via CI — the Reviewer could not run them due to sandbox restrictions.
2. Verify the test harness runs and passes.
3. If gates pass, accept and proceed with commit + AGENT_TODO.md update.

---

## Changes made by Reviewer

none
