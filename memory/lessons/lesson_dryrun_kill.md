# Lesson: DRY_RUN guards must precede every mutation, including stop/kill paths

Date: 2026-09-18 · Repo: Linux_post_install · Source: WebDAV review round (F3)

A `DRY_RUN=1` simulation destroyed a running share: `cmd_share` killed existing
daemons (restart path) BEFORE reaching the DRY_RUN check on the spawn, and
`cmd_unshare` had no DRY_RUN branch at all. The primary-action guards existed
(share-spawn, enable, disable) — the stop/kill paths were simply never audited.

Rule for future tools: when adding DRY_RUN support, enumerate EVERY mutating
call (spawn, kill, stop, rm, cp, systemctl, reload) and guard each one — audit
the stop/teardown paths with the same rigor as the create paths. A simulation
flag must never destroy live state.

Prevention: regression cases that start a stub daemon, run the dry-run path,
and assert daemon count/pid unchanged (pattern: tests/t-share-webdav.sh F3a/F3b).
