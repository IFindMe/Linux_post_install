# Failure: suite runtime budget terminal blocker (2026-09-24)

## Context
The repository documents a sub-90-second full regression-suite budget. The
rclone integration was functionally green, but the runtime-budget work required
bounded file-level scheduling evidence before any runner implementation.

## Final evidence
- Gate P cap 4 prototype: 93.30s external, safe/contract-preserving but over budget.
- Cap-extension cap 6 prototype: 84.48s external and exact 27 files / 962 checks /
  0 failures / 1 skip, but Architect rejected the evidence because D fallback,
  signal/abort cleanup, private-temp removal, and verifier provenance were incomplete.
- Corrected prototype and fresh-repair campaigns exposed disposable harness defects:
  reserved `GROUPS`, unbound signal state, duplicate completed-index relaunch, and
  incomplete signal cleanup.
- Final allowed Task 22 iteration passed static/preflight/history checks and the D
  case (20/20), but SIGINT returned `-9` through launcher fallback SIGKILL instead
  of expected `130`; wait/reap evidence was incomplete and the SIGINT temp root
  remained until post-stop cleanup. SIGTERM, full cap-6, and verifier replays were
  correctly suppressed. Architect issued `REJECT_GATE_I / TERMINAL_BLOCKED`.

## Rule
Do not start another disposable repair loop for this objective. Preserve the
final root/reports as terminal evidence. Do not implement the runner scheduler,
weaken protected waits/controls/counts, change the budget, or dispatch Builder
without a new explicit requirements/architecture decision outside this closed
planning effort.

## Evidence
`AgentsReport/tester/2026-09-24_suite-runtime-budget-final-disposable-iteration.md`;
`AgentsReport/architect/2026-09-24_suite-runtime-budget-final-disposable-iteration-review.md`;
raw root `/tmp/suite-runtime-budget-final-disposable-iteration.fQIho3`.
