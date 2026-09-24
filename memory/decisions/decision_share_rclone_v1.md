# Decision: `pos share rclone` v1 scope — paste-model, no serve/sync (2026-09-23)

## Decision
New `bin/pos-share-rclone` manages user-PASTED rclone INI at the rclone-native
default `~/.config/rclone/rclone.conf` (chmod 600, temp-then-rename, no-clobber
without `--force`/confirm). v1 subcommands: `remotes/show/status/ls/check/copy/
import/export`. `copy` is the sole write op.

## Why
- INI `[remote]` sections cannot survive the KEY=VALUE `pos config`
  (`load_env_file`/`cfg_write`/`cfg_ui`) pipeline → `pos config rclone` scope
  DEFERRED; no `rclone.env` (would be a second source of truth).
- `serve`/`mount` stay OUT: `pos share webdav` remains the only serve path
  (systemd-unit namespace entanglement otherwise).
- `sync`/`move` stay OUT: upstream data-loss warning + zero
  destructive-remote precedent; v2 contract reserved (dry-run preview or
  `--force` + negative-control test).
- `postinstall.sh` `config/rclone.conf` flow converges on the same target as
  bootstrap-only + no-clobber guard; `import` owns runtime.

## Consequences
- `RCLONE_CONFIG` is the test/override seam; `--config` forwarded verbatim.
- `import` parse-validates offline (`rclone config show`); connectivity proven
  by separate `ls`/`check` (preserves zero-network test culture).
- Revisit `serve`, `sync`/`move`, `pos config rclone` scalars only on concrete
  user demand with evidence.

## Evidence
`AgentsReport/{explorer,architect,designer,builder,tester,reviewer}/2026-09-23_*rclone*.md`;
Reviewer APPROVE_WITH_NOTES. Orchestrator verification on 2026-09-24:
`make gen` twice byte-identical, `make check` OK, `make lint` 0 FAIL/0 WARN,
and full `make test` 27 files / 962 checks pass / 0 fail / 1 skip. The suite
completed in 130s, exceeding the documented under-90s budget due to deliberate
pre-existing daemon timeout tests; this is a separate test-performance follow-up,
not a rclone regression.
