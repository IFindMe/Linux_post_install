# Stabilization Pass — Final Re-Verification (F1–F4 + test hardening) — 2026-09-06

## TL;DR

- **Status: APPROVE_WITH_NOTES** (all four findings F1–F4 resolved; test hardening present; no BLOCKING/REQUIRED findings remain).
- **Reviewed (read-only):** re-verification of prior `CHANGES_REQUIRED` findings F1/F2/F3/F4 plus the t-matrix-auth test-hardening, against the working tree + architect amendment (`AgentsReport/architect/2026-09-06_da-failmode-decision.md`, `2026-09-06_stabilization-design.md` D-A "AMENDED" blocks).
- **Findings resolved:** F1 (BLOCKING→OK), F2 (BLOCKING→OK via Architect amendment), F3 (REQUIRED→OK), F4 (SUGGESTED→OK). Test hardening (item 5) present.
- **New defects: 0.** New NOTEs: 2 residual-verification notes (N1 rc=2 set-e-in-trap dependency; N2 lint perf-rewrite equivalence).
- **Gates:** static verification only. Empirical `make lint` result, `make test` (incl. rc=2), and behavioral probes of the lint rewrite are **UNVERIFIED-BY-REVIEWER** (bash execution denied in this sandbox) — Orchestrator must run before merge, as in the prior round.

---

## Step 1: F1 — `--no-command-execution` in real bridge invocations

**Evidence (grep of actual command strings, not help text):**
- `bin/pos-communication-telegram-listener:731`:
  `timeout 120 pos ai gemini ask --no-command-execution --session "$session" --system "$AI_SYSTEM" "$prompt"`
- `bin/pos-communication-matrix-listener:466`: identical string with the flag.

**Flag-ordering valid — walked the dispatch/parse chain:**
- `pos ai gemini ask ...` → dispatcher longest-prefix routes `pos ai gemini` → `bin/pos-ai-gemini` (thin forwarder, `bin/pos-ai-gemini:7`: `exec pos ai --provider gemini "$@"`), so `pos-ai` receives `--provider gemini ask --no-command-execution --session … --system … "$prompt"`.
- `bin/pos-ai` parse loop (`bin/pos-ai:645-677`) handles flags at ANY position (case arms; `--no-command-execution` → `NO_EXEC=1; TRUST_MODE=0` at 666-667; non-flag tokens become `cmd`/`args`). So a flag after the `ask` subcommand is accepted. `NO_EXEC` is set globally before `_prompt_run_command` runs.
- Last-wins vs `--trust` unchanged; bridges never pass `--trust` (nothing in the two bridge strings references it).

**Docs now match implementation:**
- `DOC/POS.md:103` and `DOC/howto/ai.md:270` state the flag is "the structural guard the chat bridges rely on" — now true against the working tree (both bridges pass it). No false-claim remains.

[PASS] — F1 resolved.

## Step 2: F2 — D-A soft-fail ratified by Architect amendment

**Inputs:** `AgentsReport/architect/2026-09-06_da-failmode-decision.md` (DECIDED) + `2026-09-06_stabilization-design.md` D-A amended blocks.

**(a) Amendment coherent/self-consistent:** `2026-09-06_stabilization-design.md:33` (Telegram) and `:40` (Matrix) are marked **"AMENDED at review (2026-09-06): soft-fail ratified as shipped"**, present-tense soft-fail rules. TL;DR (`:11`), acceptance criteria (`:59-63`), and risk note (`:70`) all describe soft-fail. The only remaining strict-`err`/"requires" wording sits inside the amendment's past-tense descriptive paragraphs ("The original wording required…") — framed as what changed, not as the operative contract. No contradiction remains.

**(b) No other design decision silently depends on old strict D-A:** the decision report (`da-failmode-decision.md`, Decision 2 + Files-changed) states no doc/template/test change was needed because the entire shipped surface already encodes soft-fail: `tests/t-telegram-auth.sh:5,76-78`, `tests/t-matrix-auth.sh:78-87`, `config/*.env`, `DOC/POS.md`, `DOC/howto/communication.md`. Spot-read confirms those describe soft-fail, not fail-stop. No dependent decision references the strict wording.

**(c) Security property (fail-closed either way) — spot-check confirmed guards don't route around it:**
- Telegram: unset owner → `bin/pos-communication-telegram-listener:789-791` warns + `continue` **before** `handle_message` (line 800). AND-gate at `:796` requires `chat == TELEGRAM_CHAT_ID` AND `from_id == TELEGRAM_OWNER_ID`.
- Matrix: `bin/pos-communication-matrix-listener:510-512` warns on unset room; `:538` skips any room not matching `room_only` (empty when unset → every room skipped → fail-closed); sender gate `:549` (`sender == owner`). Dispatch only reached after both pass.
- Unauthorized/unset → command never executed; no hint reply. Fail-closed invariant holds in both models.

[PASS] — F2 resolved by amendment (no code change required).

## Step 3: F3 — NO_EXEC returns before any print

**Evidence (`bin/pos-ai:370-402`):**
- `:376` tty guard (`[ -w /dev/tty ] || return 0`).
- `:377-379` `if [ "${NO_EXEC:-0}" -eq 1 ]; then return 0; fi` — placed immediately after the guard and **before** the `printf` at `:380-381`.
- So under `NO_EXEC=1` the function returns 0 with zero stdout/stderr (no "Command detected:", no cmd echo).
- Normal path (tty, NO_EXEC=0): `:380-381` prints the command; `y|Y` executes, `*` declines→history. Unchanged.
- Exit semantics: NO_EXEC path returns 0; matches prior behavior (rc 0). Builder probe (PROBE-A/B) claims 0 bytes both streams under NO_EXEC, prints on normal path.

Docs (`DOC/POS.md:103`, `DOC/howto/ai.md:261-273`) updated to "neither printed nor run" — matches. No stale "still printed" text.

[PASS] statically. (Empirical 0-byte probe is Orchestrator/UNVERIFIED.)

## Step 4: F4 — lint WARN messages carry `:num` again

**Evidence (`git diff HEAD -- scripts/lint-conventions.sh`):**
- Secret-literal: `warn_ "$f:$num: secret-like literal assignment (…)"` — working `:247`, and HEAD `:239` => **byte-identical format**.
- System-path: `warn_ "$f:$num: writes to a system path (…)"` — working `:297`, HEAD `:254` => **byte-identical**.
- `num` counter incremented first in-loop (before `continue` gates), so skipped lines still get correct numbers.

**Rule list/count parity vs HEAD (no other lint behavior changed):**
- FAIL rules: 14/14 identical (shebang, set-euo, executable, POS-header, em-dash, -h|--help, deps-guard ordering, stdin-INTERACTIVE, INTERACTIVE_CMDS round-trip, plugin-no-common.sh, POS_PLUGIN, uninstall func, uninstall case, legacy-forward).
- WARN rules: 9/9 identical (POS-header line, local top-level, not-in-POS.md, TimeoutStopSec, WantedBy, legacy-lines, legacy-case, secret-literal, system-path). All message strings match HEAD byte-for-byte.

[PASS] for rule/message parity and the two `:num` fixes.

**NOTE (N2):** this file is a substantial *behavior-equivalence* rewrite (subprocess grep/sed → pure-bash single-pass: `_syspath_outer`, `_reads_stdin` + caller heredoc/depth state, POS.md preload). Rule parity is statically confirmed, but behavioral equivalence of the rewritten scan internals on edge cases needs empirical `make lint` (clean repo → 0 FAIL/0 WARN) plus the planted-violation negative — Orchestrator, UNVERIFIED-BY-REVIEWER.

## Step 5: Test hardening (t-matrix-auth) + no-regression spot-read

**Evidence (`tests/t-matrix-auth.sh`):**
- Run 1 (`:71-72`): `test_run_env … -- timeout --preserve-status -k 2 5 "$listener" --run` + `check_rc "daemon terminated via TERM trap, not killed (no hang)" 2 "$TR_RC"`.
- Run 2 / room-unset (`:82-83`): same `--preserve-status -k 2` pattern + `check_rc … 2`.
- `check_rc` helper exists unchanged (`tests/test-lib.sh:19`, delegating to `check_eq`; `test_run_env` captures `TR_RC` at `test-lib.sh:88-91`).
- rc=2 rationale: listeners run `set -euo pipefail` (`matrix-listener:2`, `telegram-listener:2`) with trap `kill $(jobs -p) 2>/dev/null; exit 0` (`matrix:525`, `telegram:767`). On empty `jobs`, bash `kill` hits a usage error (rc 2) and, under `set -e`, aborts before `exit 0` → rc 2. `--preserve-status` surfaces it; on a true daemon-hang the SIGKILL after `-k 2` yields 137 → the rc-2 assert genuinely fails → the mutation-probe hang claim is credible.

**No-regression spot-read:** `tests/t-telegram-auth.sh` unchanged semantics, aligned with ratified soft-fail (`:5` "unset → fail-closed", `:76-78` assert warning + no marker + no sendMessage; no fail-stop assertion). No test asserts the old strict-D-A behavior.

[PASS] statically. **N1 (NOTE):** the exact rc value 2 depends on bash `set -e` firing inside the TERM trap on the empty `kill`. If a given bash does not errexit-abort in a trap, the trap reaches `exit 0` → rc 0, which would make `check_rc … 2` **false-FAIL** a healthy run (the reverse failure direction). The 137-vs-2 hang discrimination is sound by design; the precise value must be confirmed by `make test` (Orchestrator). UNVERIFIED-BY-REVIEWER.

---

## Findings

### Resolved (prior round)

**F1 (was BLOCKING) — RESOLVED.** `--no-command-execution` present in the actual `pos ai gemini ask` command strings (telegram:731, matrix:466); ordering valid through `pos-ai-gemini` → `pos-ai` parse loop (flag accepted post-subcommand); docs now truthful. Certainty: FACT.

**F2 (was BLOCKING) — RESOLVED via Architect amendment.** D-A soft-fail ratified (decision report + amended design `:33/:40`); coherent and self-consistent; no dependent decision on old strict wording; fail-closed security verified (telegram AND-gate + unset-skip, matrix room-gate + sender gate; no route around). Certainty: FACT.

**F3 (was REQUIRED) — RESOLVED.** `_prompt_run_command` returns 0 before any print under `NO_EXEC` (pos-ai:377-379); zero output; normal path unchanged; rc 0 both ways. Certainty: FACT (empirical 0-byte probe UNVERIFIED).

**F4 (was SUGGESTED) — RESOLVED.** Both lint WARN messages carry `$f:$num:`, byte-identical to HEAD; 14 FAIL + 9 WARN rules and all message strings match HEAD. Certainty: FACT (rewrite behavior-equivalence UNVERIFIED).

### New (this round)

No new BLOCKING / REQUIRED / SUGGESTED findings.

- **N1 (NOTE):** t-matrix-auth rc-2 assert depends on `set -e` aborting inside the TERM trap on empty `kill` (bash-version-sensitive). If errexit does not fire in-trap, healthy run yields rc 0 → check_rc(2) false-FAILs. Design intent (137-hang discrimination) is sound; the exact value is UNVERIFIED → Orchestrator `make test`.
- **N2 (NOTE):** `scripts/lint-conventions.sh` perf-rewrite (subprocess→pure-bash) is rule/message-identical per static diff, but behavior equivalence on edge cases is UNVERIFIED → Orchestrator `make lint` on clean repo + planted-violation negative.

---

## Verification verified (static, fact-level)

- F1 flag in both real bridge command strings (grep); dispatch+parse chain accepts it; docs accurate.
- F2 amendment coherent + no strict leftover + fail-closed guards verified (read of both listeners).
- F3 NO_EXEC early-return before print; rc semantics; docs aligned.
- F4 `$f:$num:` restored byte-identical to HEAD; rule/count parity (14 FAIL, 9 WARN) vs HEAD.
- t-matrix-auth both runs `timeout --preserve-status -k 2` + `check_rc 2`; check_rc unchanged (test-lib.sh:19); t-telegram-auth aligned with soft-fail.

## Verification unverified (needs Orchestrator execution)

- `make gen` ×2 byte-identical; `make check`; `make lint` (0 FAIL/0 WARN) incl. planted-violation negative; `make test` (all files, including the rc=2 asserts in t-matrix-auth and the no-hang 137 discrimination); `bash -n`; NO_EXEC 0-byte probe; `git diff --check`.
- Empirical rc=2 (set-e-in-trap) — N1.
- Lint rewrite behavior-equivalence on edge cases — N2.

## Scope compliance

- In-scope: F1, F2 (amendment), F3, F4, test hardening all trace to approved scope/decisions.
- Out-of-scope found: none. Builder F1/F3/F4 report confirms it touched only those files + literal-contradiction doc lines; D-A/decision-pending code regions untouched.

## Remaining uncertainty

- All empirical gate/test results (Step 5). N1 rc=2 value; N2 lint-equivalence. Whether `make test` passes with the new rc=2 asserts.

## Recommended next agent

**Orchestrator** — all findings statically resolved; this review is APPROVE_WITH_NOTES, and the standing empirical gates (`make test` incl. rc=2, `make lint` incl. negative, `make gen`/`check`) remain for the Orchestrator to execute before merge. If any gate regresses, hand that specific failure back to Builder (or Tester for a coverage fix).

**Reason:** Reviewer is read-only and bash-denied; verdict is final and gated only on Orchestrator's empirical runs, none of which is a known defect.

## Changes made by Reviewer

none (read-only; report written only).
