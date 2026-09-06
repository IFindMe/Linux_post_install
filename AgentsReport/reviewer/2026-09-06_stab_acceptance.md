# Stability Pass Acceptance Review — 2026-09-06

## TL;DR

- **Status: CHANGES_REQUIRED** (reject with block list).
- **Reviewed:** uncommitted stabilization pass (`git status` 33 modified + untracked `AgentsReport/`, `apps/ai/`, `config/{telegram,matrix}.env`, `tests/`) against architect `AgentsReport/architect/2026-09-06_stabilization-design.md` (D-A…D-F), explorer audits (V1-V7, D1-D4, M1-M4, H-002/H-003, dup-loaders), and llamacpp-app REQUIRED items.
- **Defects: 2 BLOCKING, 1 REQUIRED, 1 SUGGESTED, 3 NOTE** (below).
- **BLOCKING 1:** neither chat bridge passes `--no-command-execution` to `pos ai` (D-B criteria 5/6 fail; docs falsely claim the bridges rely on it).
- **BLOCKING 2:** D-A contract not implemented — owner/room unset must `err` + exit (acceptance criteria 1/5 fail); implemented as run-degraded fail-closed; needs per-contract fix **or** explicit Architect amendment.
- **Gates:** static verification only — **all empirical gate runs (make gen×2, make check, make lint, make test, bash -n, probes, `git diff --check`) are UNVERIFIED** from this sandbox (bash execution denied); Orchestrator must execute before merge.
- **Recommended next agent: Builder** for F1+F3 (and F2 if the per-contract `err` path is chosen); **Architect** if F2's soft-fail model is to be ratified instead.

---

## Step 1: Scope and diff inventory

Checked `git status --short`, `git diff --stat` (33 files, +685/−403), per-file diff mapping, and untracked files.

- All 17 modified `bin/pos-*` trace to an approved decision area (D-A listeners/sender + templates; D-B pos-ai + `# POS_FLAGS:`/usage/completions + M4 adapter headers; D-D nine migrated tools + media-grab; D-E uninstall; V3 backup; V5 checkport/download/smb-client).
- `bin/pos` **not** modified (dispatcher/INTERACTIVE_CMDS untouched — `pos-ai` already listed at `bin/pos:269`).
- `bin/pos-docker-*` not modified → docker-compose loader **not** migrated (consistent with the accepted "no compose change" boundary).
- No accidental deletions, no stray files. Untracked files all expected (report dirs, `apps/ai/llamacpp.sh`, env templates, `tests/`).

[PASS]

## Step 2: D-A — owner/room AND-gates

- `TELEGRAM_OWNER_ID` present in sender `# POS_CONFIG:` registry (`bin/pos-communication-telegram-sender:6`) and `config/telegram.env`; `pos config telegram` scope wired (sender line 46; template).
- Actual auth logic: telegram checks both chat and owner (`bin/pos-communication-telegram-listener:761,790`); matrix checks owner + room (`bin/pos-communication-matrix-listener:511`).
- **FAIL:** architect D-A required *refuse to start* on unset (`err` in `run_daemon`, decision lines 31/38; acceptance criteria 1/5 at lines 59/63). Implementation instead starts the daemon, warns, and ignores commands. Fail-closed security property holds (no unauthorized execution), but the approved contract is not met — **Finding 2 (BLOCKING)**.

[FAIL]

## Step 3: D-B — AI eval posture (`--no-command-execution`)

- Flag implemented in `bin/pos-ai`: `# POS_FLAGS:` line 5, usage lines 43/78/83, parser 666-669 (last-wins vs `--trust`), guard in `_prompt_run_command` 370-404; completions/pos.bash:26 regenerated.
- **FAIL:** D-B acceptance criteria 5/6 (decision lines 137-138) — bridge invocations must include the flag. `grep -c "no-command-execution"` = **0** in both `bin/pos-communication-telegram-listener` and `bin/pos-communication-matrix-listener`; both call `pos ai gemini ask` without it (telegram:731, matrix:466). Security still holds today only via the non-tty guard (`pos-ai:376`), which is exactly the defense-in-depth the decision required to be made explicit — **Finding 1 (BLOCKING)**.
- **FAIL (minor):** criterion 4 ("no output of the command block") — implementation prints the block + "command execution disabled" before returning (`pos-ai:377-382`) — **Finding 3 (REQUIRED)**.
- Docs (DOC/POS.md `Command execution posture`; DOC/howto/ai.md same section) describe the print behavior and claim the bridges rely on the flag — the claim is false against the working tree (folded into F1).

[FAIL]

## Step 4: D-C — test suite

Read `tests/run-tests.sh`, `tests/test-lib.sh`, `tests/README.md`, and 4 of the 12 t-*.sh files.

- Harness: strict-mode runner in per-test subshell; `test_run`/`test_run_env` capture rc without triggering errexit; SKIP counted separately; **aborted test without FAIL is itself FAIL**; zero-assertion file → FAIL ("no assertions run — harness broken").
- Tests are genuine behavioral tests (real production scripts, stub PATH/curl/llama-server/nvidia-smi/gpg, exact rc/output asserts) — not tautologies.
- `t-ai-server-flags.sh`: dedupe (`--ctx`+`--ctx-size` → one token), precedence, default+requested emission — meaningful.
- `t-matrix-auth.sh`: owner+room gating, exactly-one-reply (reply-loop detection), fail-closed no-exec — meaningful.
- `t-uninstall-manifest.sh`: install.sh ↔ POS_LIBS set-equality + every lib exists; XDG_CONFIG_HOME scan_tier1 extraction + behavioral run — meaningful.
- Makefile `test:` target added.

[PASS] statically. Execution results (counts/timing/red-green) **UNVERIFIED** — Orchestrator must run `make test`.

## Step 5: D-D — config loader migration

- `lib/config-ui.sh:336-357` `load_env_file`: env-wins export, CRLF strip, quote-pair trim, quiet on missing file, `LOADED_ENV_KEYS` append, bare-basename resolution under CONFIG_DIR; precedence CLI > env > file > defaults documented and implemented (file only when env var unset/empty).
- Exactly 9 tools migrated (pos-ai, pos-ai-hf, pos-ai-server, telegram sender+listener, matrix sender+listener, scrcpy, media-grab); `load_secret` via loader in network-download; entertainment-lib thin wrappers `config_value`/`write_config_key` → `cfg_value`/`cfg_write` (`lib/entertainment-lib.sh:35-43`, CONFIG_FILE set at line 6).
- Legacy `load_system_env` remains in common.sh:146 with exactly the 3 unchanged callers (pos-system-backup, pos-system-health, pos-media-sync) — matches the accepted note.
- `cfg_write`/`cfg_value` semantics verified (env-file source of truth, grep-v+append value-safe writes, chmod 600).

[PASS]

## Step 6: D-E — uninstall manifest

- `POS_LIBS` matches `install.sh` phase-2 lib list byte-for-byte (12 libs; `bin/pos-system-uninstall`; also asserted by `t-uninstall-manifest.sh`).
- ScaleTail path `/usr/local/share/linux_post_install/scale-tail` matches `install.sh:237`; flags dir matches `lib/flags.sh`; user-unit scan_tier1 honors XDG_CONFIG_HOME + `pos-*` prefix only; plugin removal stays POS_PLUGIN-marker driven; tier structure documented in DOC/POS.md.

[PASS]

## Step 7: D-F — llama-server flag validation

Read `bin/pos-ai-server` end-to-end (743 lines):

- Parse loop records `REQUESTED_FLAGS` (canonical tokens), `requested_from_env_config` captures config/env-sourced flags pre-parse (lines ~56-68), merged + deduped at 476-483, hard error for unsupported requested flags (validate_requested_flags) vs warn+omit for unsupported defaults (validate_default_flags; DEFAULT_*_OK gates in exec_cmd 527-574).
- Behavior matrix matches decision: readable `--help` → word-boundary version-aware matching; unreadable → warn + accept-all; unsupported default → one warning + omitted, never in the unit; unsupported requested → hard error naming flag+version.
- `LLAMACPP_HOST` honored (HOST default 127.0.0.1, used by health probe + exec line); dry-run prints exact ExecStart; systemd_quote for binary+model tokens.
- Docs (DOC/POS.md ai-server row, usage) updated to describe requested-vs-default semantics.

[PASS]

## Step 8: Security sweep (V1-V7, D1-D4, M1-M4, NET_PROBE, gpg, /dev/tcp)

- NET_PROBE: `NET_PROBE="${NET_PROBE:-timeout 3 bash -c 'exec 3<>/dev/tcp/\$1/\$2' _ 8.8.8.8 53}"` — host/port escaped in default (`bin/pos-network-download:31`); all other `/dev/tcp` uses positional-arg composition (network-checkport 135/159/168/170 incl. udp fix, share-smb-client:94, share-lib.sh:61).
- gpg: only `--passphrase-fd 3` + `3<<<"$PASS"` in backup (197/207) with failure cleanup; **no** `--passphrase <value>` anywhere in bin/lib/scripts/apps/install.sh.
- D1 (`failed_files` init 624, single-file failure 706, meta suppressed 733, rc 1 738-742), M1 (`# POS_SUBCMDS:` incl. new verbs), M2/M4 (pos-ai subcmds + adapters), D2 (llamacpp provider honors LLAMACPP_HOST) — all present.
- Secrets: runtime token masking by `pos config`; templates carry no real secrets; `config/telegram.env`/`matrix.env` tracked by convention (like ai.env), no secret material.

[PASS]

## Step 9: llamacpp app REQUIRED items

- `apps/ai/llamacpp.sh` mode 100755 (`git diff --no-index --summary` → create mode 100755); DOC/APPS.md row present + count 18; `apps/install.sh` CAT_NAMES has `[ai]`; `templates/app.sh` categories comment += ai; pos-ai-server install-hint strings present in help + both err lines (start/status).

[PASS]

## Step 10: Gates

- `make gen` ×2 byte-identical, `make check`, `make lint` (0 FAIL/0 WARN on current repo), `make test` results, `bash -n` of changed scripts, planted-violation lint negative, test-mutation failure probes, `systemd-analyze` skip-path, `git diff --check`: **cannot be executed from this sandbox (bash denied). All UNVERIFIED — Orchestrator must run before merge.**
- Static lint comparison (HEAD vs working `scripts/lint-conventions.sh`): 23 fail/warn messages, 21 byte-identical; **two WARN messages lost the `:num` location** (secret-literal-assignment; system-path write) → "byte-identical output" claim holds only vacuously on a clean repo (0 WARN) — **Finding 4 (SUGGESTED)**.
- Deterministic generators: completion reorder observed (`llamacpp` moved in `_pos_subcmds[ai]`) consistent with LC_ALL=C sort.

[BLOCKED: empirical gate execution requires Orchestrator]

---

## Findings

### Finding 1 — BLOCKING — chat bridges missing `--no-command-execution`; docs falsely claim they use it

- Severity: BLOCKING · Certainty: FACT
- Evidence: `grep -c "no-command-execution"` = 0 in `bin/pos-communication-telegram-listener` / `bin/pos-communication-matrix-listener`; bridge invocations `timeout 120 pos ai gemini ask --session … --system … "$prompt"` at telegram:731 and matrix:466 carry no flag. Architect decision `AgentsReport/architect/2026-09-06_stabilization-design.md:112-113,126-127` and acceptance criteria 5/6 (lines 137-138) require the flag in the actual command string. DOC/POS.md and DOC/howto/ai.md state "this is the structural guard the chat bridges rely on" — false against the implementation.
- Why it matters: the approved D-B deliverable is not implemented; the accepted defense-in-depth (explicit flag so a future refactor cannot introduce bridge execution) does not exist; documentation misrepresents the implementation.
- Remediation: add `--no-command-execution` to both `pos ai gemini ask` invocations (telegram:731, matrix:466) and re-run `make check`.

### Finding 2 — BLOCKING — D-A unset-owner/room contract not implemented (err+exit) — soft-fail substituted without amendment

- Severity: BLOCKING · Certainty: FACT
- Evidence: architect decision lines 31/38 require `err` in `run_daemon` and acceptance criteria 1/5 (lines 59/63) require `--run` to exit with an error naming the key. Implementation: daemon starts, `warn` at telegram-listener:761/790 and matrix-listener:511, commands ignored. Docs (DOC/POS.md, howto/communication.md, config/telegram.env, config/matrix.env) and `t-matrix-auth.sh` consistently describe the soft-fail model — the whole round silently implements a different accepted decision. Security property (fail-closed, no unauthorized execution) is preserved by both designs.
- Why it matters: an approved, testable acceptance criterion is not met; the implementer changed design without a decision; unset-owner upgrades now keep the daemon alive (operator may not notice commands are dead).
- Remediation (either):
  1. Implement per contract: `[ -n "${TELEGRAM_OWNER_ID:-}" ] || err …` in run_daemon next to the token/chat-id guards; same for MATRIX_ROOM_ID; update docs/tests, or
  2. Architect formally amends D-A to the soft-fail model (then this finding downgrades and F2's code is accepted as-is).

### Finding 3 — REQUIRED — `--no-command-execution` prints the command block (D-B criterion 4 not met)

- Severity: REQUIRED · Certainty: FACT
- Evidence: `bin/pos-ai:377-382` prints "Command detected:" + cmd + "command execution disabled" before returning under NO_EXEC; decision line 136 ("no prompt, no output of the command block"). Docs document the print behavior (no doc bug); the deviation is the accepted criterion.
- Why it matters: contract mismatch on output semantics; per criterion the flag should return without printing. Harmless informationally, but violates the letter of the accepted decision.
- Remediation: in `_prompt_run_command`, check NO_EXEC before the "Command detected:" print and return 0; align DOC/POS.md/howto text.

### Finding 4 — SUGGESTED — lint rewrite dropped `:num` locations from two WARN messages

- Severity: SUGGESTED · Certainty: FACT
- Evidence: working `scripts/lint-conventions.sh` vs HEAD — `warn_ "$f: secret-like literal assignment (…)"` and `warn_ "$f: writes to a system path (…)"` lost `:num`; all other 21 messages byte-identical; no FAIL rule changed. Claim "byte-identical output" holds only when the repo has 0 WARNs.
- Why it matters: the two least-actionable warnings become file-only; brief's "output is actionable (file:line)" requirement degrades for those classes.
- Remediation: restore `:num` in those two messages; update the rewrite's verification claim to "identical on clean repo".

### Notes

- **N1 (NOTE):** `t-matrix-auth.sh` run 1 has no explicit `check_rc` after `timeout 5` — a daemon-hang regression (TERM trap broken, rc 124) would not fail the test. Add `check_rc` for run 1 and the matrix-room-unset run.
- **N2 (NOTE):** AGENT_TODO.md new Done entry says "DOC/APPS.md 15→16" — stale; the llamacpp bump was 17→18 (current count 18). Also the stabilization pass itself has no Done entry yet (acceptable pre-commit; add it in the commit per AGENTS.md).
- **N3 (NOTE):** `git diff --check` (whitespace) unobtainable here — folded into Step 10 UNVERIFIED.

---

## Verification verified (static, fact-level)

- D-B flag fully wired in pos-ai (header/usage/parser/last-wins guard) and completions; absent in bridges (F1).
- D-A registry + templates present; auth logic checks both gates; unset behavior deviates (F2).
- D-D loader/migration complete incl. legacy caller boundary; entertainment wrappers correct.
- D-E manifest/flags/ScaleTail/scan_tier1/plugin-marker; D-F full validation matrix; V1-V7 panels; D1/D2/M1/M2/M4; NET_PROBE + /dev/tcp positional hygiene; gpg fd-only passphrase; llamacpp app REQUIRED items; test-suite strictness (skip contract, aborted=Fail, zero-assertion=Fail).
- Scope: 33 modified + untracked files all trace to approved areas; no out-of-scope change found; bin/pos and docker-compose untouched.

## Verification unverified (needs Orchestrator execution)

- `make gen` ×2 byte-identical; `make check`; `make lint` (0 FAIL / 0 WARN); `make test` (12 files, counts, elapsed); `bash -n` on changed scripts; planted-violation lint negative; test-mutation failure probes; `systemd-analyze verify` skip-path; live bridge/`pos ai` behavioral probes; `git diff --check`.

## Scope compliance

- In-scope confirmed: all D-A..D-F areas, explorer audits, llamacpp REQUIRED items.
- Out-of-scope found: none (F1/F2 are *missing* accepted scope, not additions).
- Deviations from approved decisions: F1 (criterion 5/6 unmet), F2 (criterion 1/5 unmet, design substituted), F3 (criterion 4 unmet).

## Remaining uncertainty

- All empirical gate and behavioral results (Step 10). Whether F2 resolves to code (err+exit) or Architect amendment. Whether F3's print is acceptable after amendment.

## Recommended next agent

**Builder** (primary) — F1+F3 are well-understood scoped fixes (add flag to two invocations; move the NO_EXEC check before the print); F2 fix per contract also Builder. If the Orchestrator prefers to keep the soft-fail design, route F2 to **Architect** to amend D-A explicitly (then F2 downgrades and the round can be accepted after gates).

## Changes made by Reviewer

none