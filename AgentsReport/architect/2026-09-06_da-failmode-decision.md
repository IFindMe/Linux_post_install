# D-A Fail-Mode Decision — Ratify Soft-Fail (2026-09-06)

## TL;DR

- **Decision 1:** D-A is formally **AMENDED** to the soft-fail model (option 2): unset `TELEGRAM_OWNER_ID` / `MATRIX_ROOM_ID` → daemon **starts**, logs a startup warning naming the missing var, and ignores every incoming command (no execution, no hint reply).
- **Decision 2:** No doc/template/test changes required — they already describe soft-fail (`DOC/POS.md:372,402`, `DOC/howto/communication.md`, `config/telegram.env:10`, `config/matrix.env:10-11`, `tests/t-telegram-auth.sh:76`, `tests/t-matrix-auth.sh:78`).
- **Residual caveat (explicit):** soft-fail misconfiguration is **SILENT to senders** — an admin who forgets `TELEGRAM_OWNER_ID` gets a daemon that looks alive (systemd healthy, long-polling) but ignores everyone; the only signal is the warning in the local log. Strict mode would have been LOUD at startup but would crash-loop a systemd `Restart=always` daemon for a non-fatal config gap.
- Files changed: `AgentsReport/architect/2026-09-06_stabilization-design.md` (D-A section amendment, [DECIDED]).

---

## Decision 1: Ratify soft-fail as shipped (amend D-A)

**Problem:** D-A as written required `err`+exit (fail-stop) when `TELEGRAM_OWNER_ID`/`MATRIX_ROOM_ID` are unset. The security-track Builder implemented soft-fail: daemon starts, `warn`s, ignores commands. Reviewer finding F2 (BLOCKING) confirmed fail-closed security is preserved but the approved contract was substituted silently — violating my own decision criteria 1/5.

**Decision:** Formally amend D-A to the soft-fail model as shipped. The strict wording in `AgentsReport/architect/2026-09-06_stabilization-design.md` D-A (Telegram bullet, Matrix guard, acceptance criteria 1/5, Files-affected rows, risk note, TL;DR) is replaced and marked **"AMENDED at review (2026-09-06): soft-fail ratified as shipped"**.

**Rationale:**
1. The entire shipped surface already encodes soft-fail: code (`bin/pos-communication-telegram-listener:758-762,789-791`, `bin/pos-communication-matrix-listener:510-512`), docs (`DOC/POS.md:372,402`), templates (`config/telegram.env:10`, `config/matrix.env:10-11`), and tests (`t-telegram-auth.sh:76`, `t-matrix-auth.sh:78`). Ratifying creates **zero** doc/template/test churn; choosing strict would require rewriting 5+ artifacts against an internally consistent implementation.
2. The security property is **identical in both models**: fail-closed — an unauthorized/unauthored command never executes. The difference is purely operational (startup refusal vs degraded liveness), so there is no security case forcing strict.
3. Strict fail-stop on a systemd-managed daemon with `Restart=always` produces a crash-loop for a non-fatal config gap; soft-fail keeps the daemon alive, diagnosable via its log, and recoverable via `pos config`.
4. Both directions are cheaply reversible (a 2-line guard flip) if future evidence favors strict.

**Security implications of soft-fail (explicit):** misconfiguration is silent to senders — no reply, no error, no hint that commands exist; the only signal is the local-log warning. Weighing that against strict's startup crash-loop, soft-fail is the better operation for a personal toolkit where a missing optional auth key should not take down a supervised unit.

[DECIDED]

---

## Decision 2: No docs/templates/tests changes

`DOC/POS.md` (lines 372, 402), `DOC/howto/communication.md`, `config/telegram.env` (line 10), `config/matrix.env` (lines 10-11), `tests/t-telegram-auth.sh` (line 76), and `tests/t-matrix-auth.sh` (line 78) all describe exactly the ratified behavior. They stay as-is.

[DECIDED]

---

## Handoff

```text
Status: DECISION_READY

Problem:
D-A unset-owner/room behavior conflicted between the written design (fail-stop) and the implemented, documented, template-encoded, and tested behavior (soft-fail).

Decision:
Ratify soft-fail by amending D-A. Unset owner/room → daemon runs, warns (startup + per-message), ignores all commands (no execution, no hint reply). Security property unchanged: fail-closed.

Reasoning:
Evidence (code + 4 doc/template artifacts + 2 test files) consistently describes soft-fail; no security property differs between models; strict would crash-loop systemd units. Reversible either way.

Ownership:
Architect (amendment) — done. Implementations stay as shipped in bin/pos-communication-{telegram,matrix}-listener.

Interfaces:
No CLI/config-facing contract change beyond the ratified D-A text. `TELEGRAM_OWNER_ID`/`MATRIX_ROOM_ID` remain optional config keys whose absence disables command execution, not daemon start.

Approved scope:
- `AgentsReport/architect/2026-09-06_stabilization-design.md` D-A section (amended).
- Reviewer finding F2 is resolved by amendment (downgrades); no code change.

Explicitly out of scope:
- No change to listener code, docs, templates, or tests (they already match).
- No change to F1/F3 (BLOCKING/REQUIRED D-B items) — those remain Builder work.

Constraints:
- D-A acceptance criteria 1/5 now assert soft-fail wording (already updated in the amended doc).
- Fail-closed remains a hard invariant: never execute a command from an unauthorized sender or chat.

Verification:
- Re-read amended D-A section for consistency (no remaining "refuses to start"/`err` strict wording for the unset case).
- Reviewer re-check of F2 against amended criteria.
- Orchestrator runs `make gen && make check && make lint && make test` before merge (Step 10 gates).

Risks:
- Silent misconfiguration (soft-fail caveat): mitigated by actionable warning text naming the missing var and the `listener running (chat X, owner unset)` startup log line.
- Future preference for fail-stop is a 2-line code change + doc/template updates; D-A now records both models' trade-offs.

Recommended next agent:
Builder

Reason:
F1 (missing `--no-command-execution` in both bridge invocations) and F3 (NO_EXEC print semantics) remain BLOCKING/REQUIRED D-B fixes independent of this amendment; F2 no longer blocks. Builder should also add the D-A amendment note to AGENT_TODO.md if not already covered.

Architect changes:
AgentsReport/architect/2026-09-06_stabilization-design.md — D-A section amended only.
```

---

## Files changed (this decision)

| File | Change |
|------|--------|
| `AgentsReport/architect/2026-09-06_stabilization-design.md` | D-A TL;DR item, Telegram bullet, Matrix guard, Files-affected rows, acceptance criteria 1/5, risk note — amended to soft-fail and marked "AMENDED at review (2026-09-06)" |