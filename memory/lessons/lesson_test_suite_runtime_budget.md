# Lesson: Full suite runtime budget is exceeded by intentional daemon tests (2026-09-24)

## Evidence
The final rclone integration run passed `make gen` twice, `make check`, `make lint`, and
`make test` (27 files, 962 checks, 0 failures, 1 skip), but the runner reported
130 seconds. The documented suite budget is under 90 seconds. Isolated timing
showed the main pre-existing consumers were `t-telegram-listener-exec.sh` (~45s,
intentionally keeps a 30-second child alive), `t-lint-gate.sh` (~21s), and
`t-telegram-listener-reap.sh` (~17s). The new `t-share-rclone.sh` was ~3s and
`t-share-webdav.sh` was ~12s.

## Rule
Do not attribute the suite overrun to a newly added feature without per-file
timing. Treat deliberate daemon timeout tests as a separate Tester-owned
performance workstream; shorten them only with behavioral evidence that the
lifecycle regression remains detectable.

## Related
`AgentsReport/tester/2026-09-19_webdav-reprove.md` had already recorded a
pre-existing full-suite timeout before the rclone chain. The rclone decision
memory entry now records the final 130s result explicitly.
