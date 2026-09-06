# Builder Report — 2026-09-06 — D-D Config-Loader Centralization

## TL;DR

Status: IMPLEMENTED

Objective: Canonical `load_env_file` in `lib/config-ui.sh`; migrate 9 hand-rolled loaders; collapse entertainment-lib read/write; decide load_system_env/download/docker-compose adoption; docs; probes.

Files changed (this task): `lib/config-ui.sh` (+loader, +supersession note), 9 migrated tools (`pos-ai`, `pos-ai-hf`, `pos-ai-server`, `pos-communication-{telegram-sender,matrix-listener,telegram-listener,matrix-sender,scrcpy}`, `pos-media-grab`), `pos-network-download` (`load_secret` + inline duplicate), `lib/entertainment-lib.sh` (collapsed helpers + config-ui.sh source), `DOC/DEV.md` (canonical-loader paragraph), `DOC/AGENT_Context_Project.md` (hand-maintained line-count row via `make gen`), this report.

Verification: `bash -n` all touched files OK; `make gen` idempotent (zero diff between runs); `make check` OK; `make lint` 0 FAIL, 0 WARN; behavioral probes: telegram-sender + pos-ai + pos-network-download env-wins/CRLF/comments OK; ai-server D-F tracking survives (hard error names `--ctx-size`); entertainment-lib wrapper smoke OK (read/quote-strip/CR-strip/write/delete/chmod-600); docker-compose confirmed NOT migrated (`source` semantics preserved).

Follow-ups (out of scope, flagged): `bin/pos-network-download` NET_PROBE line (pre-existing, from a parallel uncommitted change) crashes under `set -u` — `$1`/`$2` in a single-quoted default inside `${NET_PROBE:-...}` are expanded by the outer shell; every invocation without the env var set hits "unbound variable". Owner: the parallel track that introduced `exec 3<>/dev/tcp/$1/$2`. Also residual hand-rolled loops remain ONLY in `lib/common.sh` (`load_system_env` — kept per D-D) and `lib/entertainment-plugin-lib.sh` (plugin-only lib, must stay self-contained — by design).

---

## Step 0: Scope confirmation

Read the inputs per AGENTS.md before touching code: `AgentsReport/architect/2026-09-06_stabilization-design.md` (D-D section, esp. the loader contract at ~line 310-350 and the XDG-path replacement rule at line 326-328), `AgentsReport/explorer/2026-09-06_tooling-audit.md` (Task 3) + `AgentsReport/explorer/2026-09-06_ai-audit.md` (M3), plus the current working-tree state of every target file (repo carries uncommitted changes from parallel tracks D-A/D-B/D-F/security — always read before editing).

Rules honored: don't touch `scripts/lint-conventions.sh`, `bin/pos-system-uninstall`, `tests/`, `apps/`, `AGENT_TODO.md`, listeners' authorization logic; `DOC/AGENT_Context_Project.md` generated blocks only through `make gen`; gates = `bash -n` + `make gen`×2 idempotent + `make check` + `make lint` (0 FAIL, 0 WARN); self-contained tools get `source "$(dirname "$0")/../lib/config-ui.sh" 2>/dev/null || source "$(dirname "$0")/config-ui.sh"`.

[DONE]

---

## Step 1: `load_env_file` in `lib/config-ui.sh`

Added the canonical loader immediately before `cfg_value` (now `lib/config-ui.sh:331-356`). Contract, matching the D-D design and every migrated tool's historic behavior:

- `load_env_file <file> [scope]` — `[scope]` is informational/reserved.
- A bare basename (no `/`) resolves under `${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/linux_post_install}/`; full paths used as-is.
- Reads `^[A-Z_]+=` lines; skips blank + `#` comments; strips CR from every value (CRLF-safe); trims one pair of surrounding quotes.
- Exports a key ONLY when `${!k:-}` is empty → env always wins over file (precedence: CLI flags > env > file > defaults — CLI/defaults stay in the tools).
- Appends loaded keys to global `LOADED_ENV_KEYS` (init guarded via `declare -p`, `set -u`-safe).
- Never creates files, never chmods (chmod-600 stays with `cfg_write`); missing/unreadable file = quiet no-op, rc=0.
- Doc comment notes it SUPERSEDES `lib/common.sh`'s `load_system_env()` (kept for its 3 existing callers per D-D §"Deprecate load_system_env"; `common.sh` must NOT source config-ui.sh — circular-dependency risk).

Smoke-tested in `/tmp/opencode/cfg-probe` before wiring tools: env-wins, CRLF strip, comments, XDG basename vs absolute path, missing-file rc=0, `LOADED_ENV_KEYS` content (only actually-loaded keys).

[DONE]

---

## Step 2: Migrate the 9 hand-rolled loaders

Per-tool migration (each = add config-ui.sh source + replace the hand-rolled while-read body with `load_env_file`, preserving tool-specific extras):

| Tool | Before (loader) | After | Tool-specific preservation |
|---|---|---|---|
| `pos-communication-telegram-sender` | inline env-wins loop (no CR strip) | `load_config() { load_env_file "$CONFIG_FILE"; }` | — (self-contained: owns guarded CONFIG_DIR) |
| `pos-communication-matrix-listener` | inline env-wins loop (no CR strip) | `load_config() { load_env_file "$CONFIG_FILE"; }` | — |
| `pos-communication-telegram-listener` | inline env-wins loop (no CR strip) | `load_config() { load_env_file "$CONFIG_FILE"; }` | — |
| `pos-communication-matrix-sender` | inline env-wins loop + CR strip | `load_config() { load_env_file "$CONFIG_FILE"; }` | — |
| `pos-communication-scrcpy` | inline env-wins loop + CR strip; hardcoded `$HOME/.config/.../scrcpy.env` | `load_config() { load_env_file "$CONFIG_FILE"; }`; `CONFIG_FILE="$CONFIG_DIR/scrcpy.env"` | XDG path fix (design line 328) |
| `pos-ai` | `load_config` loop + legacy two-file loop | `load_env_file "$CONFIG_FILE"` + legacy loop stays as second `load_env_file` per legacy path | legacy `LEGACY_GEMINI_CONFIG`/`LEGACY_OPENROUTER_CONFIG` loop structure kept; both legacy vars now `:-`-guarded with `$CONFIG_DIR` defaults; `CONFIG_FILE` gets env-override seam (`${CONFIG_FILE:-$CONFIG_DIR/ai.env}`) |
| `pos-ai-server` | `load_config` loop + CR strip | `load_env_file "$CONFIG_FILE"` | D-F tracking untouched: `CONFIG_REQUESTED_FLAGS`/`requested_from_env_config` is VALUE-based (reads exported LLAMACPP_* after load) → unaffected by loader; `CONFIG_FILE="${CONFIG_FILE:-$CONFIG_DIR/ai.env}"` keeps the env-override seam (`tests/t-ai-server-flags.sh` passes `CONFIG_FILE=…`) and fixes XDG |
| `pos-ai-hf` | `load_hf_config` loop + CR strip | `load_hf_config() { load_env_file "$CONFIG_FILE"; }` | `CONFIG_FILE` `:-`-guarded, `$CONFIG_DIR` default |
| `pos-media-grab` | `load_grab_config` loop (no CR strip); hardcoded `$HOME/.config/.../grab.env` | `load_grab_config() { load_env_file "$CONFIG_DIR/grab.env"; }` | XDG path fix |

Acceptance criterion 1 (D-D): `grep -rn 'while IFS.*read.*k.*v' bin/pos-communication-* bin/pos-ai* bin/pos-media-grab` → **zero matches** (only `lib/config-ui.sh:346` — the canonical loader — and `lib/common.sh:149` `load_system_env` + `lib/entertainment-plugin-lib.sh:25` remain anywhere in bin/+).

[DONE]

---

## Step 3: `pos-network-download` `load_secret` + inline duplicate

- Added config-ui.sh source.
- `load_secret()` now `load_env_file "$CONFIG_FILE"` + `RPC_SECRET="${RPC_SECRET:-}"` normalization (kept) — env-wins identical to the old guard; CR/quote-strips are no-ops for the machine-written unquoted hex file.
- The duplicate inline `grep RPC_SECRET` in `cmd_start` replaced with a `load_secret` call (guarded on `[ -z "$RPC_SECRET" ]` like before).

[DONE]

---

## Step 4: `pos-docker-compose` — NOT migrated (deliberate)

`load_global_config` still `source "$CONFIG_ENV"` (`bin/pos-docker-compose:90`). Converting to `load_env_file` would change behavior: the compose.env file is shell-EXECUTED (variable expansion, file-beats-defaults layering, and `config set` writes unquoted `TS_AUTHKEY=…` values that the loader's quote/CR handling + env-wins would invert). Documented as the deliberate exception in `DOC/DEV.md` (new canonical-loader paragraph). Also noted but NOT changed (out of D-D loader scope): `pos-docker-compose:10` still hardcodes `$HOME/.config/...` for `CONFIG_ENV`.

[DONE]

---

## Step 5: `lib/entertainment-lib.sh` collapse

- `config_value`/`write_config_key` are now thin wrappers over `cfg_value`/`cfg_write` (`lib/entertainment-lib.sh:33-43`) — identical call signatures, chmod-600 preserved, `"-"` delete supported.
- entertainment-lib now sources `config-ui.sh` via a 4-way fallback chain mirroring the user-timers source block.
- Documented minor delta: `cfg_write` emits a stderr-only warning on multi-line paste and truncates to the first line (old `write_config_key` truncated silently); write RESULT identical.
- `config_value` now also strips a trailing CR (old entertainment version did not) — alignment with the other migrated tools.
- Pre-existing contract documented in the lib header: must be sourced AFTER `lib/common.sh` (defines CONFIG_DIR); verified still true.
- Verified callers: `bin/pos-entertainment-config` (1-arg `config_value`, 2-arg `write_config_key`, `"-"` delete at line 77) and `bin/pos-entertainment-status` all match the new signatures.

[DONE]

---

## Step 6: Docs

- `DOC/DEV.md` §"Config files (if needed)": added the canonical-loader bullet (precedence contract, CR/quote handling, LOADED_ENV_KEYS, XDG basename resolution, fallback source pattern, load_system_env supersession, docker-compose exception).
- `DOC/AGENT_Context_Project.md`: hand-maintained `lib/entertainment-lib.sh` line-count row updated (311 → 300); `make gen` regenerated the filetable counts for the migrated tools (byte-order deterministic: second run produced zero diff) and `completions/pos.bash`.

[DONE]

---

## Step 7: Gates

- `bash -n` on all 12 touched code files: OK.
- `make gen`: run 1 vs run 2 diff — zero bytes (idempotent).
- `make check` (`scripts/check-sync.sh`): OK.
- `make lint` (`scripts/lint-conventions.sh`): `0 FAIL, 0 WARN`.

[DONE]

---

## Step 8: Behavioral probes (all PASS)

Stub harness in `/tmp/opencode/cfg-probe/` (XDG_CONFIG_HOME + stub curl/llama-server/systemctl/aria2c; throwaway per DEV.md):

1. **telegram-sender wiring** — telegram.env with `# comment`, blank line, `TELEGRAM_BOT_TOKEN=file-token\r\n`, `TELEGRAM_CHAT_ID=1289`; exported `TELEGRAM_CHAT_ID=env-chat`. Stub curl logged: `botfile-token` in URL (CR stripped, comment skipped) and `chat_id=env-chat` (env wins over file). Zero CR anywhere.
2. **pos-ai wiring** — ai.env with `AI_PROVIDER=gemini` + `AI_GEMINI_API_KEY=file-key\r\n`; `pos ai ask hello` with stub curl → `stub-reply` printed; header `x-goog-api-key: file-key` (CR stripped from file). With `AI_GEMINI_API_KEY=env-key` exported → header `env-key` (env wins).
3. **ai-server D-F survival** — ai.env `LLAMACPP_CTX_SIZE=8192\r\n`; stub `llama-server` whose `--help` lacks `--ctx-size`; `pos-ai-server start whatever.gguf` → `ERROR: installed llama.cpp 1.2.3 does not expose --ctx-size — remove it or upgrade llama.cpp`, exit 1. D-F "hard error on config/env-requested but unsupported flag" contract intact after the loader migration.
4. **network-download load_secret** — download.env `RPC_SECRET=file-secret\r\n`; daemon faked active via stub systemctl; `status` → RPC payload `token:file-secret` (CR stripped, from file); with `RPC_SECRET=env-secret` exported → `token:env-secret` (env wins).
5. **docker-compose** — spot-confirmed `source "$CONFIG_ENV"` unchanged (deliberate).
6. **entertainment-lib wrappers** — direct smoke: `config_value` read (CR strip), quote-stripped read, `write_config_key` overwrite, `"-"` delete, chmod-600 preserved; plus `pos entertainment status` end-to-end (ENABLED `weather,1h` parsed, "every 1h" interval).
7. **residual-loader rate** — only canonical `load_env_file` + kept `load_system_env` + plugin-only `entertainment-plugin-lib` remain.

[DONE]

---

## Step 9: Discoveries (out of scope, flagged — not fixed)

- `bin/pos-network-download` NET_PROBE default `timeout 3 bash -c 'exec 3<>/dev/tcp/$1/$2' _ 8.8.8.8 53` (introduced by a PARALLEL uncommitted change; HEAD has `'</dev/tcp/8.8.8.8/53>'`): under `set -u`, the single quotes inside `${NET_PROBE:-…}` are literal, so the OUTER shell expands `$1`/`$2` (unset) → `line 31: $2: unbound variable` on every run without the env var set. Real blocker for the tool's runtime; owner = the parallel track (likely the retry/healer work). D-D probes bypassed it by exporting a non-empty NET_PROBE — do not fix here (unapproved component boundary, unclear ownership).

[DONE]

---

## Scope compliance

In-scope: loader addition + 9-tool migration + network-download load_secret + entertainment-lib collapse + config-ui.sh supersession note + DOC/DEV.md canonical-loader paragraph + hand-maintained line-count row + report. Out-of-scope changes: none (NET_PROBE bug intentionally NOT fixed; docker-compose NOT migrated; `load_system_env` NOT rewritten).

Remaining risks / follow-ups:
1. NET_PROBE `set -u` crash (see Step 9) — needs the owning parallel track / Architect decision.
2. `pos-docker-compose` `CONFIG_ENV` still hardcodes `$HOME/.config/…` (pre-existing; XDG seam gap for that tool; explorer-flagged, not in D-D's 9).
3. `lib/entertainment-plugin-lib.sh:25` keeps its own read loop (plugin contract: plugins must not source config libs) — an intentional residual, could get a documented rationale later.
4. `load_system_env` remains duplicated logic in `lib/common.sh:146-159` — supersession documented, legacy callers (`pos system health/backup`, `pos media sync`) untouched.

Recommended next agent: **Reviewer** (independent adversarial review of the loader migration + wrapper collapse) — or **Orchestrator** if the NET_PROBE ownership question should be routed to the owning track first. Not handed to Architect: no scope/design boundary dispute remains after the decisions above were recorded.