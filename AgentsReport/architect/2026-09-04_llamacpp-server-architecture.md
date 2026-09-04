# Architecture Decision: `pos ai server` — llama.cpp Inference Server

## TL;DR

**Decisions:**
1. New tool `bin/pos-ai-server` with subcommands: `start`, `stop`, `status`, `models`, `logs`
2. Systemd user service generated at runtime (same pattern as `pos-network-download` and `pos-communication-telegram-listener`)
3. Config extends existing `ai` scope in `ai.env` — no new config files
4. Provider adapter `lib/ai-providers/llamacpp.sh` follows the 4-function contract
5. Changes to `bin/pos-ai`: `resolve_key()` accepts `llamacpp` (no key needed), `resolve_model()` falls through to `LLAMACPP_MODEL`, `cmd_providers()` includes llamacpp
6. No static `systemd/` unit file — the service is generated dynamically because model path, port, and GPU flags are user-configurable

**Open items:**
- llama-server binary name varies by build (`llama-server`, `llama.cpp/server`, `server`) — detection logic needs a fallback chain
- ROCm detection deferred (Debian/Ubuntu focus, CUDA-only auto-detect)

---

## Decision 1: Tool Structure

**Problem:** User needs to start/stop/manage a local llama.cpp inference server via `pos`.

**Decision:** Create `bin/pos-ai-server` as a standalone tool under the `ai` category, with subcommands.

**Evidence:**
- Existing pattern: `bin/pos-network-download` is a standalone tool with `start`/`stop`/`status` subcommands for the aria2 daemon
- Existing pattern: `bin/pos-communication-telegram-listener` manages its own systemd user service
- Tool naming: `pos-ai-server` → `pos ai server` (category: `ai`, command: `server`)

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `start [model]` | Install & start the systemd user service (model from arg, config, or interactive pick) |
| `stop` | Stop & remove the service |
| `status` | Show running state, loaded model, port, health endpoint |
| `models` | List available GGUF files from `HF_DOWNLOAD_DIR` |
| `logs [lines]` | Show recent server logs via `journalctl --user` |

**Not interactive:** `pos ai server` does NOT read stdin (no prompts that block under `tee`). It does NOT need to be in `INTERACTIVE_CMDS`.

**Approved scope:**
- `bin/pos-ai-server` — 1 file
- POS header: `# POS: ai server — llama.cpp local inference server (start, stop, status, models, logs)`
- POS_SUBCMDS: `start stop status models logs`
- POS_DEPS: `curl jq` (curl for health check + API, jq for JSON parsing)
- POS_FLAGS: `--port --host --model --ctx --gpu --threads`

[DECIDED]

---

## Decision 2: Systemd User Service (Runtime-Generated)

**Problem:** The llama-server service needs model path, port, GPU layers, and other parameters that are user-configurable. A static unit file can't carry these.

**Decision:** Generate the systemd user service file at runtime (same pattern as `pos-network-download` lines 172-187 and `pos-communication-telegram-listener` lines 481-500).

**Evidence:**
- `pos-network-download`: generates `pos-aria2.service` at `cmd_start()` with `$RPC_PORT`, `$RPC_SECRET`, `$DOWNLOAD_DIR` baked into `ExecStart`
- `pos-communication-telegram-listener`: generates `pos-telegram-listener.service` with the runner path baked in
- Both write to `$USER_SYSTEMD_DIR` (`~/.config/systemd/user/`), then `systemctl --user daemon-reload && enable --now`
- Both use `cat > "$USER_SYSTEMD_DIR/$SERVICE" <<EOF` pattern

**Service name:** `pos-ai-server.service`

**Service content:**

```ini
[Unit]
Description=pos llama.cpp inference server (linux-post-install)
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env llama-server -m <MODEL> --port <PORT> --host <HOST> --n-gpu-layers <GPU_LAYERS> --ctx-size <CTX_SIZE> --threads <THREADS>
Restart=on-failure
RestartSec=5
TimeoutStopSec=10
KillMode=control-group
EnvironmentFile=-%h/.config/linux_post_install/ai.env

[Install]
WantedBy=default.target
```

**Key design choices:**
- `Type=simple` — llama-server runs in foreground by default (no daemonize flag needed)
- `Restart=on-failure` — restart if it crashes, but not on clean exit (`stop` sends SIGTERM, which is clean)
- `RestartSec=5` — give time for model unload/reload
- `TimeoutStopSec=10` — llama-server handles SIGTERM gracefully (unloads model), 10s is generous
- `KillMode=control-group` — ensures the whole process tree is cleaned up
- `EnvironmentFile=-` (dash prefix) — missing file is not an error
- ExecStart is a direct `llama-server` call (not a wrapper script) — systemd handles the lifecycle

**Where config values come from:** `cmd_start()` reads the config file, resolves all values, then bakes them into the generated unit. The `EnvironmentFile` line in the unit is a fallback but the actual arguments are baked in at generation time. This matches the aria2 pattern exactly.

**`start` subcommand flow:**
1. Load config from `ai.env`
2. Resolve model (argument → `LLAMACPP_MODEL` → interactive pick)
3. Resolve port, host, ctx, gpu, threads (flag → config → default)
4. Validate model file exists
5. Auto-detect GPU if `LLAMACPP_GPU_LAYERS` is `-1`
6. Check port availability
7. Generate systemd unit file
8. `systemctl --user daemon-reload`
9. `systemctl --user enable --now pos-ai-server.service`
10. Wait briefly, then check health endpoint

**Linger warning:** Same as existing tools — warn if `loginctl enable-linger` is needed.

[DECIDED]

---

## Decision 3: Config Keys (Extend `ai` Scope)

**Problem:** Server settings need to be persisted alongside existing AI config.

**Decision:** Extend the existing `ai` scope in `ai.env`. No new config file.

**Evidence:**
- `ai.env` already holds `AI_PROVIDER`, `AI_GEMINI_API_KEY`, `HF_DOWNLOAD_DIR`, etc.
- The `# POS_CONFIG:` header on `bin/pos-ai` already declares the `ai` scope
- Adding `LLAMACPP_*` keys to the same file keeps all AI config in one place
- `pos config ai` auto-discovers keys from `# POS_CONFIG:` headers

**Config keys to add:**

| Key | Default | Description |
|-----|---------|-------------|
| `LLAMACPP_PORT` | `8088` | Server listen port |
| `LLAMACPP_HOST` | `127.0.0.1` | Bind address |
| `LLAMACPP_MODEL` | *(empty)* | Default model path (GGUF file) |
| `LLAMACPP_CTX_SIZE` | `4096` | Context window size |
| `LLAMACPP_GPU_LAYERS` | `-1` | GPU layers (`-1` = auto-detect, `0` = CPU only) |
| `LLAMACPP_THREADS` | `$(nproc)` | CPU threads |

**POS_CONFIG header on `pos-ai`:** Extend the existing `# POS_CONFIG:` line to include the new keys. The existing header already uses `ai | ai.env | ...` format — we append `LLAMACPP_*` entries.

**New header addition (appended to existing `# POS_CONFIG:` line):**
```
| LLAMACPP_PORT=:Server port (default 8088) | LLAMACPP_HOST=:Bind address (default 127.0.0.1) | LLAMACPP_MODEL=:Default model path (GGUF) | LLAMACPP_CTX_SIZE:num:Context window size (default 4096) | LLAMACPP_GPU_LAYERS:num:GPU layers (-1=auto, 0=CPU only, default -1) | LLAMACPP_THREADS:num:CPU threads (default: nproc)
```

**Config template update:** Add commented examples to `config/ai.env`.

[DECIDED]

---

## Decision 4: Provider Adapter

**Problem:** `pos ai ask` should work with the local llama.cpp server as a backend, just like gemini/openrouter.

**Decision:** Create `lib/ai-providers/llamacpp.sh` with the 4-function contract.

**Evidence:**
- `lib/ai-providers/gemini.sh` and `lib/ai-providers/openrouter.sh` both implement: `provider_name()`, `provider_default_model()`, `provider_generate()`, `provider_models_list()`
- `pos-ai` loads providers via `load_provider()` which sources `$PROVIDER_DIR/$p.sh`
- The provider adapter pattern is established and stable

**Function signatures:**

```bash
# provider_name → human-readable name
provider_name() { printf 'Local llama.cpp'; }

# provider_default_model → what's loaded on the server
provider_default_model() {
    local port="${LLAMACPP_PORT:-8088}"
    local model
    model="$(curl -sf "http://127.0.0.1:$port/v1/models" 2>/dev/null | jq -r '.data[0].id // empty')"
    [ -n "$model" ] && printf '%s' "$model" || printf '(no model loaded)'
}

# provider_generate($1=model, $2=messages JSON, $3=optional system prompt)
# → POST to /v1/chat/completions, stdout = response text
provider_generate() {
    local model="$1" messages="$2" system="${3:-}" port="${LLAMACPP_PORT:-8088}"
    local body resp code body_out
    # Build messages array with optional system prompt
    if [ -n "$system" ]; then
        body="$(printf '%s' "$messages" | jq -c --arg s "$system" \
            '[{role:"system",content:$s}] + .messages')"
    else
        body="$(printf '%s' "$messages" | jq -c '.messages')"
    fi
    body="$(printf '%s' "$body" | jq -nc --arg m "$model" --argjson msgs "$body" \
        '{model:$m, messages:$msgs, stream:false}')"
    resp="$(curl -sS -m 120 -X POST "http://127.0.0.1:$port/v1/chat/completions" \
        -H "Content-Type: application/json" \
        --write-out $'\n%{http_code}' \
        --data "$body")" || { echo "request failed (curl exit $?)" >&2; return 1; }
    code="${resp##*$'\n'}"
    body_out="${resp%$'\n'*}"
    if [ "$code" != "200" ]; then
        echo "API error $code" >&2
        return 1
    fi
    printf '%s' "$body_out" | jq -r '.choices[0].message.content // ""'
}

# provider_models_list($1=current model) → stdout = formatted list
provider_models_list() {
    local model="$1" port="${LLAMACPP_PORT:-8088}" resp code body
    resp="$(curl -sf "http://127.0.0.1:$port/v1/models" \
        --write-out $'\n%{http_code}')" || { echo "server not running" >&2; return 1; }
    code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
    [ "$code" = "200" ] || { echo "API error $code" >&2; return 1; }
    echo "Local llama.cpp models:"
    printf '%s' "$body" | jq -r '.data[]? | .id' | while IFS= read -r m; do
        [ -n "$m" ] || continue
        if [ "$m" = "$model" ]; then
            printf '  %-48s <- loaded\n' "$m"
        else
            printf '  %-48s\n' "$m"
        fi
    done
}
```

**No API key:** `resolve_key()` in `bin/pos-ai` needs a `llamacpp)` case that succeeds without a key. The local server has no auth.

**Provider detection in `resolve_key()`:**
```bash
llamacpp) return 0 ;;  # No API key needed for local server
```

**Provider detection in `resolve_model()`:**
```bash
llamacpp)
    [ -n "${LLAMACPP_MODEL:-}" ] && printf '%s' "$(basename "$LLAMACPP_MODEL")" && return ;;
```

**Provider detection in `cmd_providers()`:** The existing loop over `$PROVIDER_DIR/*.sh` auto-discovers `llamacpp.sh`. The `configured` check needs updating — llamacpp is "configured" when `llama-server` is available, not when an API key exists.

**POS_CONFIG header on adapter:** Add `# PROVIDER_CONFIG: LLAMACPP_MODEL=:Default model path (GGUF file)` to the adapter so `pos config ai` discovers it.

[DECIDED]

---

## Decision 5: GPU Auto-Detection

**Problem:** Auto-detect NVIDIA CUDA to set `--n-gpu-layers` appropriately.

**Decision:** Simple CUDA detection — check `nvidia-smi` and `/dev/nvidia*`. No ROCm for now (Debian/Ubuntu focus).

**Evidence:**
- `nvidia-smi` is the standard NVIDIA management interface
- `/dev/nvidia*` devices indicate driver presence
- llama.cpp uses `--n-gpu-layers -1` for auto (offload all possible layers to GPU)
- The user's request says "Debian/Ubuntu so mainly CUDA"

**Detection function (in `pos-ai-server`):**

```bash
detect_gpu() {
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
        echo "cuda"
    else
        echo "cpu"
    fi
}
```

**GPU layer resolution:**

```bash
resolve_gpu_layers() {
    local configured="${LLAMACPP_GPU_LAYERS:-}"
    if [ -n "$configured" ] && [ "$configured" != "-1" ]; then
        echo "$configured"
        return
    fi
    # Auto-detect
    local gpu
    gpu="$(detect_gpu)"
    case "$gpu" in
        cuda) echo "-1" ;;
        *)    echo "0" ;;
    esac
}
```

**Behavior:**
- `LLAMACPP_GPU_LAYERS=-1` (default) → auto-detect: CUDA → `-1`, no CUDA → `0`
- `LLAMACPP_GPU_LAYERS=0` → CPU only (override)
- `LLAMACPP_GPU_LAYERS=35` → explicit layer count (for fine-tuning)

**No ROCm:** Explicitly out of scope. The detection function can be extended later.

[DECIDED]

---

## Decision 6: Model Selection

**Problem:** User needs to pick from downloaded GGUF models.

**Decision:** `pos ai server models` scans `HF_DOWNLOAD_DIR` for `.gguf` files, reusing `pos ai hf list` patterns.

**Evidence:**
- `pos-ai-hf` downloads to `$HF_DOWNLOAD_DIR` (default `~/.local/share/linux_post_install/ai/models/`)
- `cmd_list()` in `pos-ai-hf` already scans for model directories with `.hf-meta` files
- GGUF files are the inference-ready format; they're the only files that matter for serving

**`models` subcommand behavior:**

```bash
cmd_models() {
    local dir="${HF_DOWNLOAD_DIR:-$HOME/.local/share/linux_post_install/ai/models}"
    [ -d "$dir" ] || { warn "No models directory — run 'pos ai hf download' first"; return 0; }

    local found=0
    echo "Available GGUF models:"
    while IFS= read -r gguf; do
        [ -f "$gguf" ] || continue
        found=1
        local name size
        name="$(basename "$gguf")"
        local dir_name
        dir_name="$(basename "$(dirname "$gguf")")"
        size="$(stat -c%s "$gguf" 2>/dev/null || echo 0)"
        local human_size
        human_size="$(human_size "$size")"
        printf '  %-50s %s   %s\n' "$dir_name/$name" "$human_size" ""
    done < <(find "$dir" -name '*.gguf' -type f 2>/dev/null | sort)

    [ "$found" -eq 0 ] && warn "No .gguf files found — download with 'pos ai hf download <repo> --gguf'"
}
```

**Model resolution order for `start [model]`:**
1. Explicit argument: `pos ai server start /path/to/model.gguf`
2. Relative path argument: `pos ai server start model.gguf` → search `HF_DOWNLOAD_DIR`
3. Config: `LLAMACPP_MODEL` from `ai.env`
4. Interactive pick: prompt user to select from available models

**Interactive pick (only when on a TTY and no model specified):**
```bash
pick_model() {
    local models=() i
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        models+=("$f")
    done < <(find "$HF_DOWNLOAD_DIR" -name '*.gguf' -type f 2>/dev/null | sort)

    [ ${#models[@]} -gt 0 ] || err "No GGUF models found — run 'pos ai hf download <repo> --gguf'"

    echo "Available models:"
    for ((i = 0; i < ${#models[@]}; i++)); do
        local name size
        name="$(basename "${models[$i]}")"
        size="$(stat -c%s "${models[$i]}" 2>/dev/null || echo 0)"
        printf '  %2d) %-50s %s\n' "$((i + 1))" "$name" "$(human_size "$size")"
    done
    echo
    local choice
    printf 'Pick a model [1-%d]: ' "${#models[@]}"
    IFS= read -r choice </dev/tty || choice=""
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#models[@]}" ] || err "Invalid selection"
    printf '%s' "${models[$((choice - 1))]}"
}
```

[DECIDED]

---

## Decision 7: Health Check & Status

**Problem:** User needs to know if the server is running and healthy.

**Decision:** Use llama.cpp's `/health` endpoint + systemd state.

**`status` subcommand output:**

```
service:   running
model:     mistral-7b-v0.1.Q4_K_M.gguf
port:      8088
host:      127.0.0.1
gpu:       CUDA (-1 layers)
context:   4096
threads:   16
autostart: enabled
endpoint:  http://127.0.0.1:8088
health:    ok (loaded)
```

**Health check function:**

```bash
check_health() {
    local port="${LLAMACPP_PORT:-8088}"
    local resp
    resp="$(curl -sf "http://127.0.0.1:$port/health" 2>/dev/null)" || { echo "not running"; return 1; }
    # llama.cpp /health returns {"status": "ok"} or {"status": "loading model", ...}
    local status
    status="$(printf '%s' "$resp" | jq -r '.status // "unknown"' 2>/dev/null)"
    echo "$status"
}
```

**`logs` subcommand:** Uses `journalctl --user -u pos-ai-server -n <lines> --no-pager`.

[DECIDED]

---

## Decision 8: Changes to `bin/pos-ai`

**Problem:** `pos ai --provider llamacpp` should work, routing through the local server.

**Decision:** Minimal changes to `bin/pos-ai` — 3 touch points.

**Evidence:**
- `resolve_key()` has a `case "$p" in` that checks each provider — add `llamacpp)` case
- `resolve_model()` has a `case "$p" in` for provider-specific fallbacks — add `llamacpp)` case
- `cmd_providers()` checks API key configuration — add llamacpp case
- `require_key()` has provider-specific error messages — add llamacpp case

**Changes:**

1. **`resolve_key()` (line 167):** Add `llamacpp) return 0 ;;` — no key needed
2. **`resolve_model()` (line 193):** Add `llamacpp) [ -n "${LLAMACPP_MODEL:-}" ] && printf '%s' "$(basename "$LLAMACPP_MODEL")" && return ;;`
3. **`cmd_providers()` (line 120):** Add `llamacpp) [ -n "${LLAMACPP_PORT:-}" ] && configured="configured" || configured="configured (default port)" ;;`  — local server is always "configured"
4. **`require_key()` (line 176):** Add `llamacpp) ;;` — no key needed, just return

These are all 1-2 line additions within existing `case` blocks.

[DECIDED]

---

## Decision 9: Error Handling

| Error | Detection | Response |
|-------|-----------|----------|
| `llama-server` not found | `command -v llama-server` fails | `err "llama-server not found — install llama.cpp (https://github.com/ggerganov/llama.cpp)"` |
| Port in use | `ss -tlnp` or `curl` to port | `err "Port $PORT already in use — check with 'ss -tlnp'"` |
| Model not found | `[ -f "$model" ]` | `err "Model not found: $model"` |
| GPU not detected | `detect_gpu` returns `cpu` | `warn "No NVIDIA GPU detected — running in CPU mode"` (continues) |
| Service start fails | `systemctl --user start` returns non-zero | `journalctl --user -u pos-ai-server -n 20 --no-pager` |
| Server unhealthy | `/health` returns non-200 or times out | `warn "Server may not be ready yet — check with 'pos ai server status'"` |
| Model too large | Not reliably detectable pre-load | Skip — llama.cpp will fail with OOM and the error is in journal logs |

**Binary detection fallback:** llama.cpp builds name the binary differently:

```bash
find_llamacpp() {
    local candidates=("llama-server" "llama.cpp/server" "server" "llama-server-cuda")
    for bin in "${candidates[@]}"; do
        command -v "$bin" &>/dev/null && { echo "$bin"; return 0; }
    done
    return 1
}
```

[DECIDED]

---

## Decision 10: File List & Responsibilities

| File | Action | Responsibility |
|------|--------|----------------|
| `bin/pos-ai-server` | **NEW** | Service manager: start/stop/status/models/logs, systemd unit generation, GPU detection, model selection |
| `lib/ai-providers/llamacpp.sh` | **NEW** | Provider adapter: provider_name, provider_default_model, provider_generate, provider_models_list |
| `bin/pos-ai` | **MODIFY** | Add `llamacpp` cases to resolve_key, resolve_model, cmd_providers, require_key |
| `config/ai.env` | **MODIFY** | Add commented LLAMACPP_* key documentation |
| `completions/pos.bash` | **AUTO** | `make gen` picks up new POS headers — no manual edit |

**NOT in scope:**
- No static `systemd/pos-ai-server.service` file (generated at runtime)
- No changes to `postinstall.sh` (service is user-managed, not installed by system)
- No changes to `bin/pos` dispatcher (tool is auto-discovered)
- No changes to `lib/common.sh`

---

## Decision 11: Implementation Constraints

1. **All `LLAMACPP_*` config reads must go through `load_config()`** — the existing config loader in `pos-ai` (line 131). The new tool also needs its own config loader (or sources `pos-ai`'s, which it can't cleanly). **Decision:** `pos-ai-server` uses its own `load_config()` copy (same pattern as `pos-ai-hf` line 26 — every tool that reads `ai.env` has its own loader).

2. **The systemd unit must NOT hardcode HOME.** The existing pattern (`pos-communication-telegram-listener` line 494-496) explains why: "Do NOT pin Environment=HOME here — the systemd user manager already sets the correct HOME."

3. **ExecStart must use full paths for llama-server** — systemd user services don't inherit the user's full `$PATH`. Resolve via `$(command -v llama-server)` at unit generation time.

4. **The service must use `--log-format` flag** if available (llama.cpp) to produce parseable logs. Not a hard requirement.

5. **`make gen` must run after creating `bin/pos-ai-server`** to regenerate the tree, dispatch table, completions, and doc tables.

6. **The tool must pass `make check && make lint`** — bash -n syntax, exec bit, POS header, --help, deps guards before help.

---

## Verification Plan

1. **Unit test (stub PATH):**
   - Fake `llama-server`, `nvidia-smi`, `curl`, `jq` in PATH
   - Assert `cmd_start` generates correct unit file content
   - Assert `cmd_models` finds `.gguf` files
   - Assert `detect_gpu` logic
   - Assert config resolution precedence (flag > env > default)

2. **Integration test (manual):**
   - `pos ai server start model.gguf` with a real llama-server binary
   - `pos ai server status` shows correct info
   - `pos ai server logs` shows journal output
   - `pos ai server stop` cleans up
   - `pos ai --provider llamacpp ask "hello"` routes through local server

3. **Gates:**
   - `make check` — green
   - `make lint` — 0 FAIL, 0 WARN

---

## Explicitly Out of Scope

- Model conversion/quantization
- Multi-GPU support
- Authentication on the API endpoint
- Web UI
- GPU driver installation
- ROCm/AMD detection
- Quantization awareness (context size vs model capability)
- Model memory estimation / pre-flight checks
- Automatic model download on `start` if none present
