# Stabilization Pass — Architectural Design Decisions

**Date:** 2026-09-06
**Architect:** Evidence-driven design pass over three Explorer audit reports
**Constraint:** Preserve existing Bash architecture; no framework rewrites; smallest clean fix per issue; no commits; all gates (`make gen`, `make check`, `make lint`) must remain green at `0 FAIL, 0 WARN`.

---

## TL;DR

1. **D-A (Telegram/Matrix auth):** Introduce `TELEGRAM_OWNER_ID` as an AND-gate with `TELEGRAM_CHAT_ID`; Matrix requires `MATRIX_ROOM_ID` before any command runs. Both platforms converge on "sender AND chat authorized" contract; unset owner/room → daemon runs but ignores all commands (soft-fail, ratified at review 2026-09-06).
2. **D-B (AI eval posture):** Flip tty confirmation default to `[y/N]` (deny); keep `--trust` interactive-only; add `--no-exec` flag to `pos-ai` and enforce it in chat bridges. Document the bridge invariant.
3. **D-C (Test framework):** Create `tests/` with a minimal runner, `make test` target, stub-PATH + PTY patterns; first suite covers 14 surfaces.
4. **D-D (Config loader):** Canonical `load_env_file` in `lib/config-ui.sh`; migrate 9 hand-rolled loaders; unify CRLF + XDG; collapse entertainment-lib read/write.
5. **D-E (Install/uninstall manifest):** Extend `pos-system-uninstall` Tier 1 to cover 9 orphaned libs, ScaleTail dir, feature-flag store, and USER systemd units; de-hardcode plugin/binary lists.
6. **D-F (pos-ai-server validation):** Validate ALL flags entering ExecStart (CLI + config + defaults); unsupported DEFAULT → warn + omit; unsupported REQUESTED → hard error.

---

## D-A: Chat Authorization Model (Telegram + Matrix)

### Decision

Adopt a unified "sender AND chat authorized" authorization contract for both Telegram and Matrix listeners. Concretely:

**Telegram:**
- Add `TELEGRAM_OWNER_ID` to the `# POS_CONFIG:` registry in `bin/pos-communication-telegram-sender:6` and to `config/telegram.env` template.
- Replace the OR-gate at `bin/pos-communication-telegram-listener:787` with:
  1. `chat == TELEGRAM_CHAT_ID` (chat must be the configured chat) — fail-continue (skip message silently).
  2. `from_id` must be one of the comma-separated `TELEGRAM_OWNER_ID` values — fail-continue (skip message silently).
- If `TELEGRAM_OWNER_ID` is unset, the daemon **starts in fail-closed degraded mode**: `run_daemon` logs `warn "TELEGRAM_OWNER_ID unset — chat commands WILL BE IGNORED (fail-closed); set it with 'pos config telegram'"` at startup (same location as the token/chat-id guards, line ~761) and a per-message `warn "TELEGRAM_OWNER_ID unset — ignoring command (set it with 'pos config telegram')"`; every incoming command is skipped — **no execution, no hint reply**.

  > **AMENDED at review (2026-09-06): soft-fail ratified as shipped.** The original wording required the daemon to `err`+exit on unset `TELEGRAM_OWNER_ID`. The security-track Builder implemented soft-fail (daemon runs, warns, ignores commands); `DOC/POS.md`, `DOC/howto/communication.md`, `config/telegram.env` and `tests/t-telegram-auth.sh` all consistently describe soft-fail. This is a deliberate deviation ratified at review time (Reviewer finding F2, downgraded). The security property is identical in both models: **fail-closed** — an unauthenticated/unauthorized command never executes. The difference is purely operational: strict = fail-stop (loud misconfiguration, systemd restart loop); soft-fail = degraded-liveness (silent-to-senders misconfiguration, one clean warning in the local log). Soft-fail was chosen because the entire shipped surface already encoded it and it avoids a systemd `Restart=always` crash-loop for a non-fatal config gap.
- Reply on unauthorized messages: **none** (no leak that commands exist). The message is silently dropped.
- Do **not** include a "trusted group" backward-compat mode in this pass. The OR-gate was never a documented feature; it was an implementation gap. Backward compatibility for group operation can be added later via an explicit `TELEGRAM_GROUP_MODE=true` opt-in — that is a separate, larger design decision (requires per-user allowlist, rate limiting, etc.) and explicitly **out of scope** for this stabilization.

**Matrix:**
- Require `MATRIX_ROOM_ID` for command execution. If unset, the daemon **starts in fail-closed degraded mode**: guard in `run_daemon` at `bin/pos-communication-matrix-listener:510-512` logs `warn "MATRIX_ROOM_ID unset — refusing to run commands (fail-closed); set it with 'pos config matrix'"`; the daemon long-polls but runs no commands.

  > **AMENDED at review (2026-09-06): soft-fail ratified as shipped.** The original wording required a hard `[ -n "${MATRIX_ROOM_ID:-}" ] || err "MATRIX_ROOM_ID is required — set it in pos config matrix"` guard. The security-track Builder implemented soft-fail; `DOC/POS.md`, `DOC/howto/communication.md`, `config/matrix.env` and `tests/t-matrix-auth.sh` all consistently describe soft-fail. Deliberate deviation ratified at review time (Reviewer finding F2, downgraded). Security property identical in both models: **fail-closed** — no command runs outside the configured room. Same operational trade-off as the Telegram case above (silent-to-senders vs. startup crash-loop).
- Keep the sender=owner gate (`sender == owner` at line 550) unchanged.
- This makes the Matrix behavior: sender authorized (== owner) AND chat authorized (== configured room) — identical to the Telegram contract.

**Consistency rule:** Both platforms enforce the same conceptual model: a message must come from an authorized sender in an authorized chat. No fallback to "any chat" or "any sender."

### Files affected

| File | Change |
|------|--------|
| `bin/pos-communication-telegram-sender:6` | Add `TELEGRAM_OWNER_ID` to `# POS_CONFIG:` registry |
| `bin/pos-communication-telegram-listener:787-791` | Replace OR-gate with AND-gate (chat + sender) + soft-fail `TELEGRAM_OWNER_ID` unset warning in `run_daemon` and per-message skip |
| `bin/pos-communication-matrix-listener:510-512` | Soft-fail `MATRIX_ROOM_ID` unset warning in `run_daemon` (commands refused) |
| `config/telegram.env` | Add `TELEGRAM_OWNER_ID=` template line |
| `DOC/HOWTO.md` (communication section) | Document new key, explain AND-gate |
| `DOC/POS.md` (telegram listener section) | Document authorization model |

### Acceptance criteria

1. With `TELEGRAM_OWNER_ID` unset, `pos communication telegram listener --run` starts the daemon, logs a startup warning naming `TELEGRAM_OWNER_ID`, and ignores every incoming command (no execution, no hint reply).
2. With `TELEGRAM_OWNER_ID=123` and `TELEGRAM_CHAT_ID=456`, a message from `from_id=123` in `chat=456` is dispatched.
3. A message from `from_id=999` in `chat=456` is silently dropped (no reply, no log of "command not found").
4. A message from `from_id=123` in `chat=789` (wrong chat) is silently dropped.
5. With `MATRIX_ROOM_ID` unset, `pos communication matrix listener --run` starts the daemon, logs a warning naming `MATRIX_ROOM_ID`, and runs no commands (fail-closed).
6. With `MATRIX_ROOM_ID` set, messages from the owner in the configured room are dispatched; messages from other senders or other rooms are dropped.
7. `make gen && make check && make lint` all pass at 0 FAIL, 0 WARN after the change.
8. `TELEGRAM_OWNER_ID` appears in `pos config telegram` output (masked if flagged as `digits` type, same as `TELEGRAM_CHAT_ID`).

### Risks / open questions

- Existing users who have not set `TELEGRAM_OWNER_ID` will find the daemon stays up but ignores every command after upgrade. **Mitigation:** the startup warning is actionable ("set it with 'pos config telegram'"). This is intentional — the previous behavior was a security vulnerability (V1), not a feature. Documented residual caveat (soft-fail): misconfiguration is **silent to senders** — no reply, no error, no hint that commands exist; the only signal is the startup/per-message warning in the local log. Strict mode would have been loud at startup but would crash-loop a systemd-managed daemon for a non-fatal config gap; soft-fail preserves liveness and diagnosability. (Amended 2026-09-06.)
- The `TELEGRAM_OWNER_ID` supports comma-separated values (multi-user). The `digits` flag validation in `cfg_validate` already allows negative IDs (group/supergroup IDs); for `TELEGRAM_OWNER_ID` we should use a `digits` flag that also allows comma-separated positive-only values. **Decision:** use a plain `digits` flag (no comma support) for the initial pass; each `TELEGRAM_OWNER_ID` entry is a single numeric user ID. If multi-user is needed, a future pass adds it. This keeps the validation simple and the AND-gate implementation a direct string comparison.
- The `TELEGRAM_CHAT_ID` comparison already allows negative values (group IDs). The `TELEGRAM_OWNER_ID` should always be a positive user ID. The `cfg_validate` `digits` flag allows leading `-`; for `TELEGRAM_OWNER_ID` use a new `positive-digits` flag or simply document that only positive values are valid for this key.

---

## D-B: Remote AI Command Execution Posture (eval)

### Decision

The `pos ai` command-execution path (`_prompt_run_command`) evaluates AI-generated shell code. The security posture change addresses three concerns: the default confirmation, the `--trust` flag, and the bridge invariant.

**1. Flip the tty confirmation default to DENY:**

Change `bin/pos-ai:391` from `[Y/n]` to `[y/N]`. The rationale: the AI model's output is untrusted external authority. When a user asks "run X", they mean the *task* — the specific command the model proposes is the model's interpretation, and a prompt-injection or model error can produce a harmful command. Defaulting to deny means the user must explicitly opt-in (`y` or Enter is now decline). The `[y/N]` pattern is the standard bash convention for non-destructive defaults. The user's request for help does not imply authorization to execute arbitrary code.

Current line 391:
```bash
printf 'Run this command? [Y/n] ' >&2
```
Change to:
```bash
printf 'Run this command? [y/N] ' >&2
```

And invert the case logic at line 394: `y|Y)` executes; `*` (including Enter) declines and adds to history.

**2. `--trust` flag: keep as-is but document scope:**

The `--trust` flag (`TRUST_MODE=1`, `bin/pos-ai:644`) auto-executes without confirmation on a **tty only** (line 382 `[ -w /dev/tty ] || return 0` — non-tty never executes). This is correct: `--trust` is an explicit operator action on an interactive terminal. No change needed to the flag itself, but:
- Add a `--trust` warning to `usage()` if not already present: note that this bypasses confirmation and should only be used in trusted local sessions.
- Document that `--trust` has **no effect** when invoked from a chat bridge (non-tty → early return at line 382).

Do NOT rename `--trust` to `--trust-no-confirm`; the existing name is clear enough and renaming would break alias wrappers (`pos-ai-alias:433-436`).

**3. Chat bridge invariant: bridges NEVER execute code blocks.**

Both Telegram (`bin/pos-communication-telegram-listener:734`) and Matrix (`bin/pos-communication-matrix-listener:472`) invoke `pos ai gemini ask ...` which runs non-interactively. Inside `_prompt_run_command` (`bin/pos-ai:382`), `[ -w /dev/tty ] || return 0` means code blocks are never executed when the tool runs without a tty — they are printed but not run. This is the correct behavior.

To prevent future regressions if a refactor changes the tty check or adds an auto-confirm path:
- Add `--no-command-execution` as a recognized flag in `pos-ai` (`bin/pos-ai:649` parse block, `# POS_FLAGS:` header).
- When set, `_prompt_run_command` returns 0 immediately without printing or executing (same as current non-tty behavior, but explicit).
- Both chat bridges pass `--no-command-execution` when invoking `pos ai`:
  - `bin/pos-communication-telegram-listener:734`: add `--no-command-execution` to the command.
  - `bin/pos-communication-matrix-listener:472`: same.
- This makes the invariant **structurally enforced**: even if a future refactor removes the tty check, the bridge-parsed flag still prevents execution.

### Files affected

| File | Change |
|------|--------|
| `bin/pos-ai:391` | Change prompt from `[Y/n]` to `[y/N]` |
| `bin/pos-ai:394-405` | Invert case logic: `y|Y` → execute, `*` → decline+history |
| `bin/pos-ai:649-677` | Add `--no-command-execution` to flag parser |
| `bin/pos-ai:380-382` | Check `$NO_EXEC` flag before the tty check |
| `bin/pos-ai:5` (`# POS_FLAGS:`) | Add `--no-command-execution` |
| `bin/pos-communication-telegram-listener:734` | Add `--no-command-execution` to AI bridge call |
| `bin/pos-communication-matrix-listener:472` | Add `--no-command-execution` to AI bridge call |
| `DOC/POS.md` (ai section) | Document new flag and confirmation change |
| `DOC/HOWTO.md` (ai section) | Document the security posture |

### Acceptance criteria

1. On a tty, `pos ai` with a command block in the response shows `[y/N]` and declines on Enter.
2. On a tty, typing `y` or `Y` at the prompt executes the command.
3. `pos ai --trust` still auto-executes on a tty (no prompt).
4. `pos ai --no-command-execution` skips execution entirely (no prompt, no output of the command block).
5. `pos communication telegram listener` → AI bridge invocation includes `--no-command-execution` in the actual command string (verifiable by reading the source).
6. Same for Matrix listener.
7. `make gen && make check && make lint` all pass at 0 FAIL, 0 WARN.
8. The `# POS_FLAGS:` header includes `--no-command-execution` and `completions/pos.bash` updates accordingly after `make gen`.

### Risks / open questions

- Changing the default from ALLOW to DENY is a **behavioral breaking change** for users who are accustomed to pressing Enter to run. This is intentional and justified by the security audit (V2): the model's output is untrusted. Users who want the old behavior can type `y`.
- The `--no-command-execution` flag name is long. Alternatives: `--no-exec`, `--safe-mode`. **Decision:** `--no-command-execution` is preferred because it is self-documenting and unambiguous. The flag is consumed programmatically (by bridges), not by humans typing interactively.
- Non-tty paths (`[ -w /dev/tty ] || return 0`) already prevent execution. `--no-command-execution` adds defense-in-depth for the tty path in case the tty check is ever removed.

---

## D-C: Test Framework Shape

### Decision

Create a committed `tests/` directory with a minimal runner and a `make test` target. The framework follows the repo's established stub-PATH + PTY patterns from `DOC/DEV.md:196-214`.

**Layout:**

```
tests/
  run-tests.sh              # runner (check helper, pass/fail counting, exit code)
  ai-server-flags.sh        # unit: flag validation logic
  ai-hf-download.sh         # unit: single-file failure path
  telegram-auth.sh          # unit: auth gate logic (mocked)
  matrix-auth.sh            # unit: auth gate logic (mocked)
  config-loader.sh          # unit: load_env_file precedence
  systemd-unit.sh           # unit: unit generation + systemd-analyze (skip if unavailable)
  uninstall-manifest.sh     # unit: install/uninstall symmetry
  gen-docs-drift.sh         # integration: make gen && git diff --check
  lint-gate.sh              # integration: make lint exit code
  gpg-backup.sh             # unit: passphrase not in argv (mocked gpg)
  config-precedence.sh      # unit: env-wins-over-file precedence
  unsupported-flags.sh      # unit: pos-ai-server unsupported flag handling
  ai-llama-detect.sh        # unit: llama version detection (mocked binary)
```

**Runner (`tests/run-tests.sh`):**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Minimal test runner — sources test functions, counts pass/fail/skip.
# Usage: tests/run-tests.sh [test-file ...]
# If no args, runs all tests/*.sh files.
PASS=0; FAIL=0; SKIP=0
check() { local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$desc"
  else FAIL=$((FAIL+1)); printf '  FAIL  %s (expected=%s actual=%s)\n' "$desc" "$expected" "$actual"; fi }
skip() { SKIP=$((SKIP+1)); printf '  SKIP  %s (%s)\n' "$1" "$2"; }
# ... file discovery, per-file sourcing, summary ...
```

**`make test` target (Makefile addition):**

```makefile
test:
	./tests/run-tests.sh
```

**Interaction with existing gates:**
- `make check` and `make lint` remain **unchanged** — they are static gates (syntax, exec bits, doc sync, convention).
- `make test` is a **separate** target for behavioral regression tests.
- CI (`.gitea/workflows/lint.yml`) does NOT need to run `make test` in this pass — that is a future CI enhancement. The tests exist for local validation and are committed as the regression baseline.

**Determinism and speed:**
- All tests use stub PATH (temp dir with fake binaries) and env-overridable paths per `DEV.md:198`.
- No network calls, no real systemd, no real llama-server binary.
- Target: all tests complete in < 60 seconds on a typical dev box.
- Tests that need `systemd-analyze` (for real validation) use a skip-if-unavailable pattern:
  ```bash
  command -v systemd-analyze &>/dev/null || { skip "systemd-analyze validation" "systemd-analyze not available"; return 0; }
  ```
- Tests that need `jq` (for JSON assertions) use the same skip pattern.
- Skip means "not applicable in this environment" — **never** "test passed." Tests never lie about pass/fail.

**What is unit-testable with stub PATH vs integration-only:**

| Test | Method | Skip condition |
|------|--------|---------------|
| AI server flag validation | Stub PATH with fake `llama-server` that echoes `--help` text | Never (fake binary is self-contained) |
| AI HF single-file failure | Stub PATH with fake `curl` that returns rc=1 | Never |
| Telegram auth gate | Direct function extraction (source the auth logic, call with test args) — or stub PATH with fake `jq`/`curl` | Never |
| Matrix auth gate | Same as Telegram | Never |
| Config loader | Direct sourcing of `load_env_file` | Never |
| Systemd unit generation | Stub PATH with fake `systemd-escape`, `systemd-quote` output comparison | `systemd-analyze` not available → skip validation step |
| Uninstall manifest | Direct comparison of install list vs uninstall list (grep both scripts) | Never |
| Gen-docs drift | Run `make gen` then `git diff --check` | `git` repo not available → skip |
| Lint gate | Run `make lint` and check exit code | Never |
| GPG passphrase | Stub PATH with fake `gpg` that echoes argv to a log file; assert passphrase not in log | Never |
| Config precedence | Export env var, write config file, call loader, assert env wins | Never |
| Unsupported flags | Stub PATH with fake `llama-server` that echoes specific `--help` text | Never |
| Llama version detect | Stub PATH with fake `llama-server` that echoes `--version` | Never |

### Files affected

| File | Change |
|------|--------|
| `tests/run-tests.sh` (new) | Test runner |
| `tests/ai-server-flags.sh` (new) | Flag validation tests |
| `tests/ai-hf-download.sh` (new) | HF single-file failure tests |
| `tests/telegram-auth.sh` (new) | Telegram auth gate tests |
| `tests/matrix-auth.sh` (new) | Matrix auth gate tests |
| `tests/config-loader.sh` (new) | Config loader precedence tests |
| `tests/systemd-unit.sh` (new) | Systemd unit generation tests |
| `tests/uninstall-manifest.sh` (new) | Install/uninstall symmetry tests |
| `tests/gen-docs-drift.sh` (new) | Gen-docs drift test |
| `tests/lint-gate.sh` (new) | Lint gate test |
| `tests/gpg-backup.sh` (new) | GPG passphrase tests |
| `tests/config-precedence.sh` (new) | Config precedence tests |
| `tests/unsupported-flags.sh` (new) | Unsupported flag handling tests |
| `tests/ai-llama-detect.sh` (new) | Llama version detection tests |
| `Makefile` | Add `test` target |
| `scripts/check-sync.sh` | (Optional) Add `tests/*.sh` to the `bash -n` scan list |

### Acceptance criteria

1. `make test` runs all 14 test files and reports PASS/FAIL/SKIP counts.
2. `make test` exits 0 when all tests pass (or are skipped).
3. `make test` exits non-zero when any test FAILs.
4. No test makes network calls (verified by grepping test files for `curl`/`wget`/`http` without stub wrappers).
5. All tests complete in < 60 seconds (measured on a representative dev box).
6. `make check` and `make lint` are unaffected (0 FAIL, 0 WARN).
7. `make gen` is unaffected.
8. Tests that need `systemd-analyze` skip gracefully when unavailable (exit 0, report SKIP).
9. The test runner does not leave temp files in the working tree (uses `/tmp` for all temp dirs).
10. Each test file starts with `#!/usr/bin/env bash` + `set -euo pipefail` (passes `bash -n` and lint).

### Risks / open questions

- The test framework is **minimal by design**. It does not use bats, shunit2, or any external framework — consistent with the repo's zero-dependency philosophy. If the test surface grows beyond ~20 files, consider bats at that point.
- Some tests (auth gate, config loader) require extracting logic from tools into testable functions or sourcing the tool and overriding variables. This is the established pattern from DEV.md's stub-PATH approach.
- The gen-docs drift test depends on `make gen` being idempotent — which is a project invariant.
- The lint gate test is inherently coupled to `scripts/lint-conventions.sh` behavior — if lint rules change, this test may need updating. Acceptable; it is a regression canary.

---

## D-D: Config Loader Centralization

### Decision

Establish `lib/config-ui.sh` as the canonical config loader. Add a single generic `load_env_file` function and migrate all 9 hand-rolled loaders to it.

**1. Add `load_env_file` to `lib/config-ui.sh`:**

```bash
# Canonical env-file loader. Reads KEY=VALUE lines, strips comments and
# CRLF, applies env-wins precedence (exported env vars are never overwritten).
# Usage: load_env_file <file>
load_env_file() {
    local f="$1" k v
    [ -f "$f" ] || return 0
    while IFS='=' read -r k v; do
        [ -n "$k" ] || continue
        case "$k" in \#*) continue ;; esac
        v="${v//$'\r'/}"
        v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
        if [ -z "${!k:-}" ]; then
            export "$k"="$v"
        fi
    done < <(grep -E '^[A-Z_]+=' "$f" || true)
}
```

**Precedence contract (documented, matches dominant behavior):**
```
CLI flags > exported environment > config file values > defaults
```
This is the existing behavior in all 9 hand-rolled loaders. The `load_env_file` function implements "exported env wins over file" (the `if [ -z "${!k:-}" ]` check). CLI flags are applied later by the tool's own arg parser. Defaults are applied at variable declaration (`${VAR:-default}`). This contract is now explicit and single-sourced.

**2. Deprecate `load_system_env` in `lib/common.sh:146-159`:**

Make `load_system_env` delegate to `load_env_file`:
```bash
load_system_env() {
    load_env_file "$HOME/.config/linux_post_install/system.env"
}
```

This requires `common.sh` to source `config-ui.sh`. However, `common.sh` is the base library sourced by most tools, and `config-ui.sh` is not currently sourced by `common.sh`. **Decision:** do NOT make `common.sh` source `config-ui.sh`. Instead, keep `load_system_env` as-is (it is functionally identical to `load_env_file`) but note in `config-ui.sh` that `load_env_file` supersedes it. New tools use `load_env_file`; existing `load_system_env` callers continue working. This avoids a circular dependency risk and a mass-change to `common.sh` consumers.

The **real migration** targets are the 9 tools that hand-roll their own `load_config()`.

**3. CRLF policy (universal strip):**

`load_env_file` strips `\r` unconditionally (`v="${v//$'\r'/}"`). This resolves the 5-tool vs 5-tool CRLF divergence identified in the audit. All 5 tools that currently strip CRLF will continue to work; the 5 that don't will now strip it too (defensive improvement, no behavioral regression).

**4. XDG honoring:**

`load_env_file` takes an absolute file path — it does not resolve `CONFIG_DIR`. The caller passes the full path. For tools that currently hardcode `$HOME/.config/linux_post_install/...`, the migration replaces the hardcoded path with `${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/linux_post_install}/<file>`. Since `common.sh` defines `CONFIG_DIR` at line 19, tools sourcing `common.sh` already have it; the self-contained communication tools already have their own `CONFIG_DIR` guarded copy.

**Migration list (9 tools):**

| Tool | Current function | Current file | Notes |
|------|-----------------|-------------|-------|
| `bin/pos-communication-telegram-sender` | `load_config:61-74` | `telegram.env` | Already sources `config-ui.sh` for `cfg_value` |
| `bin/pos-communication-telegram-listener` | `load_config:86-98` | `telegram.env` | Standalone |
| `bin/pos-communication-matrix-listener` | `load_config:65-77` | `matrix.env` | Standalone |
| `bin/pos-communication-matrix-sender` | `load_config:44-57` | `matrix.env` | Standalone |
| `bin/pos-communication-scrcpy` | `load_config:14-28` | `scrcpy.env` | Standalone |
| `bin/pos-ai` | `load_config:130-160` | `ai.env` + legacy files | Has extra legacy-file loop |
| `bin/pos-ai-server` | `load_config:21-35` | `ai.env` | Standalone |
| `bin/pos-ai-hf` | `load_hf_config:30-44` | `ai.env` | Standalone |
| `bin/pos-media-grab` | `load_grab_config:10-23` | `grab.env` | Standalone |

For each tool: source `config-ui.sh` (with the existing fallback chain pattern), replace the hand-rolled function body with `load_env_file "$CONFIG_FILE"`, preserve any tool-specific extras (like `pos-ai`'s legacy-file loop — keep that as a second `load_env_file` call on the legacy path).

**5. Collapse entertainment-lib read/write into config-ui:**

`entertainment-lib.sh`'s `config_value` and `write_config_key` (lines 28-54) are functionally identical to `cfg_value` and `cfg_write` in `config-ui.sh` (lines 311-344). **Decision:** add thin wrappers in `entertainment-lib.sh` that delegate to `cfg_value`/`cfg_write`:

```bash
config_value() {
    local k="$1"
    cfg_value "$CONFIG_FILE" "$k"
}
write_config_key() {
    local key="$1" val="$2"
    cfg_write "$CONFIG_FILE" "$key" "$val"
}
```

This preserves the existing `config_value`/`write_config_key` API for the 5 entertainment tools that call them, while the implementation lives in one place. `entertainment-lib.sh` must source `config-ui.sh` (add to its source chain).

### Files affected

| File | Change |
|------|--------|
| `lib/config-ui.sh` | Add `load_env_file` function |
| `bin/pos-communication-telegram-sender` | Replace `load_config` body with `load_env_file` |
| `bin/pos-communication-telegram-listener` | Replace `load_config` body with `load_env_file` |
| `bin/pos-communication-matrix-listener` | Replace `load_config` body with `load_env_file` |
| `bin/pos-communication-matrix-sender` | Replace `load_config` body with `load_env_file` |
| `bin/pos-communication-scrcpy` | Replace `load_config` body with `load_env_file` |
| `bin/pos-ai` | Replace `load_config` body with `load_env_file` + legacy loop |
| `bin/pos-ai-server` | Replace `load_config` body with `load_env_file` |
| `bin/pos-ai-hf` | Replace `load_hf_config` body with `load_env_file` |
| `bin/pos-media-grab` | Replace `load_grab_config` body with `load_env_file` |
| `lib/entertainment-lib.sh` | Delegate `config_value`/`write_config_key` to `cfg_value`/`cfg_write` |
| `DOC/DEV.md` | Update "No shared lib? Inline fallbacks" section to reference `config-ui.sh` as the canonical loader |

### Acceptance criteria

1. `grep -rn 'while IFS.*read.*k.*v' bin/pos-communication-* bin/pos-ai* bin/pos-media-grab` returns **zero** hand-rolled loader matches (all replaced).
2. Each migrated tool passes its existing behavioral expectations: env-wins precedence, CRLF stripping, missing-file graceful return (rc 0).
3. `pos config telegram` and `pos config matrix` display and mask values correctly after migration.
4. `entertainment-lib.sh` `config_value` and `write_config_key` still work (entertainment tools pass their tests).
5. `make gen && make check && make lint` all pass at 0 FAIL, 0 WARN.
6. No tool that previously sourced `common.sh` now additionally sources `config-ui.sh` unless it was already doing so. Tools that were standalone (communication tools) now source `config-ui.sh` via the fallback chain, which is the same pattern used by their existing inline copies.

### Risks / open questions

- **Self-contained tools sourcing config-ui.sh:** The 5 communication tools currently do NOT source any shared lib (they carry inline fallbacks). After migration, they source `config-ui.sh`. This is a net improvement (shared implementation) but changes the "no shared lib" classification of these tools. **Mitigation:** the inline fallback copies of `log`/`warn`/`err` stay in place; only the `load_config` body is replaced. The tools remain self-contained for basic logging; they just share the config loader.
- **pos-ai's legacy file loop:** `pos-ai:130-160` reads `ai.env` plus legacy `gemini.env` and `openrouter.env` files. This is tool-specific logic; keep it as a second pass after `load_env_file "$CONFIG_FILE"`. Do not try to generalize the legacy loop into `load_env_file`.
- **Regression risk:** Each migration touches a working tool's config loading. The test suite (D-C) covers config precedence, which mitigates this.

---

## D-E: Install/Uninstall Manifest

### Decision

Close the install-only gaps in `pos-system-uninstall` with the smallest targeted fixes. Do NOT introduce a full manifest abstraction (like `lib/install-manifest.sh`) — that would be a larger refactor inconsistent with the current "list-based" approach in both `install.sh` and `pos-system-uninstall`.

**1. Add 9 orphaned libs to Tier 1 scan and removal:**

Extend the lib list at `bin/pos-system-uninstall:62-64` (scan) and `:238-239` (remove) from:
```bash
for f in common.sh menu-lib.sh share-lib.sh; do
```
to:
```bash
for f in common.sh menu-lib.sh share-lib.sh flags.sh notify.sh entertainment-lib.sh scheduler-lib.sh config-ui.sh user-timers-lib.sh entertainment-plugin-lib.sh usb-lib.sh registry.sh; do
```

Same change in both `scan_tier1` and `remove_tier1`.

**2. Add ScaleTail directory and feature-flag store to Tier 1 removal:**

After the lib removal block in `remove_tier1`:
```bash
# ScaleTail templates
if [ -d /usr/local/share/linux_post_install/scale-tail ]; then
    rm -rf /usr/local/share/linux_post_install/scale-tail && count=$((count+1))
fi

# Feature-flag store
if [ -d /usr/local/share/linux_post_install/flags ]; then
    rm -rf /usr/local/share/linux_post_install/flags && count=$((count+1))
fi

# Clean up parent dir if empty
rmdir /usr/local/share/linux_post_install 2>/dev/null || true
```

Add corresponding scan entries in `scan_tier1`:
```bash
[ -d /usr/local/share/linux_post_install/scale-tail ] && found+=("/usr/local/share/linux_post_install/scale-tail/")
[ -d /usr/local/share/linux_post_install/flags ] && found+=("/usr/local/share/linux_post_install/flags/")
```

**3. Add USER systemd unit discovery to Tier 1:**

After the system-unit removal block (`:287-311`), add:
```bash
# USER systemd units (pos-* and pos-entertainment-* and pos-schedule-*)
local user_unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [ -d "$user_unit_dir" ]; then
    local ufile
    while IFS= read -r ufile; do
        local uname
        uname="$(basename "$ufile" .service)"
        uname="${uname%.timer}"
        systemctl --user disable --now "${basename "$ufile"}" 2>/dev/null || true
        rm -f "$ufile" && count=$((count+1))
    done < <(find "$user_unit_dir" -maxdepth 1 -name 'pos-*' -type f 2>/dev/null || true)
    systemctl --user daemon-reload 2>/dev/null || true
fi
```

Add corresponding scan in `scan_tier1`:
```bash
local user_unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
if [ -d "$user_unit_dir" ]; then
    while IFS= read -r ufile; do
        found+=("user-unit: $(basename "$ufile")")
    done < <(find "$user_unit_dir" -maxdepth 1 -name 'pos-*' -type f 2>/dev/null || true)
fi
```

**4. De-hardcode entertainment-plugin and prebuilt-binary lists:**

Replace the hardcoded loops for entertainment plugins (`:72-74` scan, `:248-250` remove) with directory-driven discovery (matching `install.sh`'s pattern):
```bash
# Scan: discover plugins by POS_PLUGIN marker
while IFS= read -r f; do
    found+=("$f")
done < <(for ep in /usr/local/bin/*.sh; do
    grep -q '^# POS_PLUGIN:' "$ep" 2>/dev/null && echo "$ep"
done | sort)
```
```bash
# Remove: all installed entertainment plugins (discovered by POS_PLUGIN marker)
while IFS= read -r f; do
    [ -f "$f" ] && { rm -f "$f" && count=$((count+1)); }
done < <(for ep in /usr/local/bin/*.sh; do
    grep -q '^# POS_PLUGIN:' "$ep" 2>/dev/null && echo "$ep"
done | sort)
```

**5. Fix the `.bash_completion` over-broad removal (H-002):**

Replace `sed -i '/pos/d'` at `:333` with marker-based or anchored patterns:
```bash
# Only remove lines the installer added (source pos.bash pattern)
sed -i '/source.*pos\.bash/d' "$HOME/.bash_completion"
```

This is conservative: only lines that `postinstall.sh` would have added are removed. If no such lines exist, nothing is touched.

**6. Fix `.bashrc` removal anchoring (H-003):**

Add word-boundary anchors to the sed patterns at `:320-322`:
```bash
sed -i '/source.*pos-ai-hook\.sh/d' "$HOME/.bashrc"
sed -i '/linux_post_install.*PATH.*pos/d' "$HOME/.bashrc"
sed -i '/source.*pos\.bash/d' "$HOME/.bashrc"
```

**7. Document deliberately surviving artifacts:**

Add a comment block in `pos-system-uninstall`'s `usage()` and in the scan output:
```bash
# Intentionally NOT removed (user-managed):
# - apt packages (system packages)
# - /usr/local/bin/yt-dlp (manually installed)
# - ~/.config/rclone/ (rclone manages its own config)
# - ~/.ssh/authorized_keys additions (user SSH access)
# - pos-owned config files (removed by --config tier)
# - pos-owned data files (removed by --data tier)
```

### Files affected

| File | Change |
|------|--------|
| `bin/pos-system-uninstall:62-64` | Add 9 libs to scan list |
| `bin/pos-system-uninstall:238-239` | Add 9 libs to remove list |
| `bin/pos-system-uninstall:248-250` | De-hardcode entertainment plugins |
| `bin/pos-system-uninstall:260-262` | Keep prebuilt binaries (already correct, keep as-is for now) |
| `bin/pos-system-uninstall` (after 311) | Add ScaleTail dir + flags dir removal |
| `bin/pos-system-uninstall` (after 311) | Add USER systemd unit scan + removal |
| `bin/pos-system-uninstall:72-74` | De-hardcode entertainment plugin scan |
| `bin/pos-system-uninstall:333` | Fix `.bash_completion` over-broad removal |
| `bin/pos-system-uninstall:320-322` | Fix `.bashrc` anchoring |
| `bin/pos-system-uninstall` (usage) | Document deliberately surviving artifacts |

### Acceptance criteria

1. `scan_tier1` shows all 12 libs (3 original + 9 new) when installed.
2. `remove_tier1` removes all 12 libs from `/usr/local/bin/`.
3. After `remove_tier1`, `/usr/local/share/linux_post_install/` is empty or removed.
4. After `remove_tier1`, no `pos-*` user units remain in `~/.config/systemd/user/`.
5. `.bashrc` removal does not remove lines unrelated to pos (verified by test: a `.bashrc` with `source pos.bash` in a comment is not affected).
6. `.bash_completion` removal does not remove lines unrelated to pos (the `sed '/pos/d'` is replaced with anchored patterns).
7. `make gen && make check && make lint` all pass at 0 FAIL, 0 WARN.
8. The install manifest test (D-C `tests/uninstall-manifest.sh`) confirms: every artifact in the install scan has a corresponding removal path.

### Risks / open questions

- **USER systemd unit removal during `remove_tier1`:** This calls `systemctl --user` which may fail if no user session is available (e.g., running uninstall as a scheduled task). **Mitigation:** wrap in `2>/dev/null || true` (idempotent, like the system-unit path).
- **Prebuilt binaries list is still hardcoded** (`wihotspot`, `wihotspot-gui`, `create_ap`). De-hardcoding this would require a marker system similar to POS_PLUGIN, which is overengineering for 3 binaries. Keep as-is for now; document as a known limitation.
- **`/usr/local/share/linux_post_install` parent directory** is only removed if empty after removing `scale-tail` and `flags/`. This is safe because the parent is also the ScaleTail clone destination.

---

## D-F: pos-ai-server Validation Semantics

### Decision

Expand flag validation to cover **every flag** that will appear in `ExecStart`, not just CLI-explicit ones. Distinguish between "requested" (user or config intent) and "default" (tool-emitted) flags with different error behavior.

**1. Expand validation scope to all ExecStart flags:**

Currently, only `REQUESTED_FLAGS` (CLI-parsed at `:295-359`) is validated at `:407-409`. The always-emitted defaults (`--port`, `--host`, `--n-gpu-layers`, `--ctx-size`, `--threads`) and config-sourced optional flags (`--gpu-threads`, `--tensor-split`, `--batch-size`, etc.) are emitted into `exec_cmd` at `:445-490` without validation.

After this change, **all flags in `exec_cmd`** are validated. The validation split:

- **Requested flags** (CLI OR config-sourced): If unsupported, **hard error**. The user explicitly asked for something that doesn't work — fail loudly.
- **Default flags** (emitted without user intent): If unsupported, **warn + omit**. The tool chose a default that this build doesn't support — silently degrade.

**2. How config-sourced flags get marked "requested":**

Add config-sourced flags to `REQUESTED_FLAGS` during config loading. After `load_config` in `cmd_start` (around `:395`), read the config file for keys that map to CLI flags and add them to `REQUESTED_FLAGS`:

```bash
# After load_config, mark config-sourced flags as requested
if [ -n "${LLAMACPP_PORT:-}" ] && [ "$PORT" != "8088" ]; then
    REQUESTED_FLAGS+=("--port")
fi
if [ -n "${LLAMACPP_HOST:-}" ] && [ "$HOST" != "127.0.0.1" ]; then
    REQUESTED_FLAGS+=("--host")
fi
# ... similar for other config keys that map to flags
```

Wait — this is too fragile (needs manual comparison with defaults). **Better approach:** introduce a `CONFIG_REQUESTED_FLAGS` array that is populated during `load_config` when a config key that maps to a flag is actually set in the file:

```bash
CONFIG_REQUESTED_FLAGS=()

load_config() {
    local f="$CONFIG_FILE"
    [ -f "$f" ] || return 0
    while IFS='=' read -r k v; do
        [ -n "$k" ] || continue
        case "$k" in \#*) continue ;; esac
        v="${v//$'\r'/}"
        v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
        if [ -z "${!k:-}" ]; then
            export "$k"="$v"
            # Track config keys that map to flags
            case "$k" in
                LLAMACPP_PORT) CONFIG_REQUESTED_FLAGS+=("--port") ;;
                LLAMACPP_HOST) CONFIG_REQUESTED_FLAGS+=("--host") ;;
                LLAMACPP_CTX_SIZE) CONFIG_REQUESTED_FLAGS+=("--ctx-size") ;;
                LLAMACPP_GPU_LAYERS) CONFIG_REQUESTED_FLAGS+=("--n-gpu-layers") ;;
                LLAMACPP_THREADS) CONFIG_REQUESTED_FLAGS+=("--threads") ;;
                # ... other config-to-flag mappings
            esac
        fi
    done < <(grep -E '^[A-Z_]+=' "$f" || true)
}
```

Then in `cmd_start`:
```bash
# Merge CLI-requested and config-requested flags
ALL_REQUESTED_FLAGS=("${REQUESTED_FLAGS[@]}" "${CONFIG_REQUESTED_FLAGS[@]}")
# Deduplicate
local deduped=()
for flag in "${ALL_REQUESTED_FLAGS[@]}"; do
    case " ${deduped[*]:-} " in *" $flag "*) continue ;; esac
    deduped+=("$flag")
done

# Validate requested flags (hard error on unsupported)
if [ "${#deduped[@]}" -gt 0 ]; then
    validate_requested_flags "$llamacpp_bin" "$version" "${deduped[@]}"
fi

# Validate default flags (warn + omit on unsupported)
validate_default_flags "$llamacpp_bin" "$version"
```

**3. New `validate_default_flags` function:**

```bash
# validate_default_flags <binary> <version> — for every flag that will be
# emitted by default (without user intent), check it exists in --help.
# Unsupported defaults are silently omitted from exec_cmd.
# Sets global flags: DEFAULT_PORT_OK, DEFAULT_HOST_OK, etc.
DEFAULT_FLAGS_VALIDATED=0
validate_default_flags() {
    local bin="$1" version="$2"
    local help_text
    help_text="$("$bin" --help 2>/dev/null)" || {
        warn "Cannot obtain llama-server --help output — skipping default flag validation"
        return 0
    }
    DEFAULT_PORT_OK=1; DEFAULT_HOST_OK=1; DEFAULT_CTX_OK=1
    DEFAULT_GPU_OK=1; DEFAULT_THREADS_OK=1
    local check_flag() {
        local flag="$1" varname="$2"
        if ! printf '%s' "$help_text" | grep -qF -- "$flag"; then
            warn "installed llama.cpp ${version} does not support default flag ${flag} — omitting"
            eval "$varname=0"
        fi
    }
    check_flag "--port" DEFAULT_PORT_OK
    check_flag "--host" DEFAULT_HOST_OK
    check_flag "--ctx-size" DEFAULT_CTX_OK
    check_flag "--n-gpu-layers" DEFAULT_GPU_OK
    check_flag "--threads" DEFAULT_THREADS_OK
    DEFAULT_FLAGS_VALIDATED=1
}
```

Then in `exec_cmd` construction (`:445-490`), wrap each default flag in a validation check:
```bash
exec_cmd="$(systemd_quote "$llamacpp_full") -m $(systemd_quote "$model")"
[ "$DEFAULT_PORT_OK" -eq 1 ] && exec_cmd+=" --port $PORT"
[ "$DEFAULT_HOST_OK" -eq 1 ] && exec_cmd+=" --host $HOST"
[ "$DEFAULT_GPU_OK" -eq 1 ] && exec_cmd+=" --n-gpu-layers $gpu_layers"
[ "$DEFAULT_CTX_OK" -eq 1 ] && exec_cmd+=" --ctx-size $CTX_SIZE"
[ "$DEFAULT_THREADS_OK" -eq 1 ] && exec_cmd+=" --threads $THREADS"
```

**4. `--help` unreadable → single warn + proceed (unchanged):**

The existing `help_text` fetch at `:72-75` already handles this: `warn "Cannot obtain llama-server --help output — skipping flag validation"; return 0`. This behavior is preserved for both `validate_requested_flags` and `validate_default_flags`.

**5. Make detected version inform error messaging (no version branching):**

The version is already interpolated into error strings (`:84`): `"installed llama.cpp ${version} does not expose ${flag}"`. This is correct and sufficient. No version-conditional logic or compat table is added. The version is informational for the user's debugging, not a branching variable.

**6. Fix the substring matching issue (D4, low priority):**

Replace `grep -qF -- "$flag"` at `:83` with a word-boundary match:
```bash
if ! printf '%s' "$help_text" | grep -qE -- "(^|[[:space:]])${flag}($|[[:space:]])"; then
```

This prevents false-positive substring matches (e.g., `--mmap` matching `--no-mmap` if such a flag existed). Low priority but trivial to fix during this pass.

### Files affected

| File | Change |
|------|--------|
| `bin/pos-ai-server:21-35` | Extend `load_config` to populate `CONFIG_REQUESTED_FLAGS` |
| `bin/pos-ai-server:66-87` | Fix `validate_requested_flags` substring matching (D4) |
| `bin/pos-ai-server` (new function) | Add `validate_default_flags` |
| `bin/pos-ai-server:407-409` | Extend validation to merge CLI + config requested flags |
| `bin/pos-ai-server:445-490` | Wrap default flags in `DEFAULT_*_OK` guards |
| `DOC/POS.md` (ai server section) | Document validation behavior: requested → hard error, default → warn+omit |

### Acceptance criteria

1. A config file with `LLAMACPP_PORT=9999` causes `--port` to be added to `REQUESTED_FLAGS` and validated against `--help`.
2. If the binary's `--help` does not list `--port`, the server refuses to start with an error naming the flag and the detected version.
3. If the binary's `--help` does not list `--threads` (a default), `--threads` is omitted from `ExecStart` with a warning.
4. If `--help` cannot be read, all flags are accepted (warn + proceed, unchanged behavior).
5. The `grep -qF` substring issue (D4) is resolved — `--mmap` no longer matches if only `--no-mmap` appears in `--help`.
6. Generated `ExecStart` contains only flags that pass validation.
7. `make gen && make check && make lint` all pass at 0 FAIL, 0 WARN.

### Risks / open questions

- The baseline-compatible flag set (`--port`, `--host`, `--n-gpu-layers`, `--ctx-size`, `--threads`) is assumed universal across modern llama.cpp builds. If a very old build lacks even `--port`, the server would start with `ExecStart` containing only the binary and model — functional but unusual. This is an acceptable degradation path.
- The `CONFIG_REQUESTED_FLAGS` approach requires manually maintaining the config-key-to-flag mapping in `load_config`. If a new config key is added, the mapping must be updated. This is a small maintenance burden; document the mapping clearly.
- The default-flags guard changes the ExecStart generation logic from unconditional to conditional. If `validate_default_flags` has a bug, the ExecStart could be missing expected flags. The test suite (D-C) covers this case.

---

## Recommended Execution Order

The decisions have dependencies and independent tracks. Here is the recommended order:

### Phase 1: Infrastructure (no behavior changes, green gates)

1. **D-C (Test framework)** — Create `tests/` + `make test` + runner. Write skeleton test files with `skip` for features not yet implemented. Verify `make test` runs and exits 0 (all skipped). This establishes the regression safety net for all subsequent changes.
2. **D-D part 1 (Config loader)** — Add `load_env_file` to `lib/config-ui.sh`. Do NOT migrate tools yet. Verify gates green.

### Phase 2: Security fixes (highest priority, isolated files)

3. **D-A (Telegram/Matrix auth)** — The Telegram fix is self-contained in `bin/pos-communication-telegram-listener` + `bin/pos-communication-telegram-sender` POS_CONFIG header + config template. The Matrix fix is a one-line guard in `bin/pos-communication-matrix-listener`. Both are isolated.
4. **D-B (AI eval posture)** — Flip the confirmation default and add `--no-command-execution` flag. Touches `bin/pos-ai` + both listeners' AI bridge calls. Independent of D-A (different lines in the listeners).

### Phase 3: Validation and correctness

5. **D-F (pos-ai-server validation)** — Extends the validation in `bin/pos-ai-server`. Depends on D-D being complete (the config loader migration should happen first so `load_config` in `pos-ai-server` is already migrated — or do D-F's config-requested-flags addition within the hand-rolled loader before migration, then adjust during D-D migration). **Decision:** do D-F first (it modifies the hand-rolled loader in `pos-ai-server`), then D-D migration replaces it. This avoids double-touching.
6. **D-E (Install/uninstall manifest)** — Self-contained in `bin/pos-system-uninstall`. Independent of all others except D-C (the uninstall test depends on the manifest being complete).

### Phase 4: Config loader migration

7. **D-D parts 2-5 (Migrate loaders, collapse entertainment-lib)** — Migrate the 9 tools' hand-rolled loaders to `load_env_file`. This touches many files but each change is mechanical. Do it last so all other changes (D-A, D-B, D-F) are already in place and their config keys are stable.

### Phase 5: Validation

8. Run full gate suite: `make gen && make check && make lint` — verify 0 FAIL, 0 WARN.
9. Run `make test` — verify all tests pass (no more skips for implemented features).

### Builder-track split (parallel-safe groups)

**Group A (communication tools):** D-A Telegram + D-A Matrix → single Builder, one commit
**Group B (AI tools):** D-B (pos-ai) + D-F (pos-ai-server) → single Builder, one commit
**Group C (infrastructure):** D-C (tests) + D-D (config-ui.sh + loader) → single Builder, one commit
**Group D (uninstaller):** D-E → single Builder, one commit
**Group E (migration):** D-D tool migrations (after A+B+D complete) → single Builder, one commit

Groups A, B, C, and D are **parallel-safe** (no file overlap). Group E depends on B and D completing (to avoid merge conflicts in `pos-ai-server` and `pos-communication-*` tools).

---

## Open Items (require future decisions, not in this pass)

1. **Trusted-group mode for Telegram:** Explicit opt-in `TELEGRAM_GROUP_MODE=true` with per-user allowlist. Deferred — the current AND-gate is sufficient for the primary use case (1:1 private chat with the owner).
2. **Lint performance optimization:** The Explorer identified ~17 hotspots in `scripts/lint-conventions.sh` (Task 1). This is a performance improvement, not a correctness fix — separate from the stabilization pass.
3. **LLAMACPP_HOST coherence (D2 from AI audit):** The server honors `LLAMACPP_HOST` but the llamacpp provider adapter and probes hardcode `127.0.0.1`. This is a behavioral coherence issue, not a security issue. Deferred — it requires changes to `lib/ai-providers/llamacpp.sh` and the server's probe paths, which is a feature-level fix.
4. **pos-ai-hf single-file download failure (D1 from AI audit):** The single-file download path does not record failures in `failed_files`, so `.hf-meta` is written for a partially-downloaded model. This is a HIGH defect but is a pure bug fix (not an architectural decision) — belongs in Builder scope directly, not in this design pass.
5. **GPG passphrase in argv (V3 from Security audit):** Fixing this requires `gpg --batch --passphrase-fd` or a temp-file approach. Behavioral change to `bin/pos-system-backup` — defer to a separate fix commit.
6. **H-002/H-003 bashrc/bash_completion over-broad removal:** Partially addressed in D-E (`.bash_completion` fix) but a more thorough marker-based approach would be ideal. The D-E fix is the minimum viable improvement.
