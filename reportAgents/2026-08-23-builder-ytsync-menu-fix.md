# Builder — ytsync menu fix (3 sites)

## TL;DR

- Status: **IMPLEMENTED** — 3/3 approved sites fixed in `bin/pos-media-ytsync`; all gates green; probe passed.
- Sites: :292 (`last_sync_of`: multibyte `cut -d'·'` → grep capture + `${last%% ·*}`), :302 (`last_run_overall`: same technique), :1054 (`menu_render`: `printf '%s\n' '---…'`).
- Gates: `bash -n` OK · `make check` OK · `make lint` **0 FAIL, 0 WARN**. `make gen` ran (see Step 7 drift note).
- Probe: ALL_ASSERTIONS_PASSED — `· last run …` suffix renders, bottom separator renders, LAST SYNC column populates, zero `cut:`/`printf:` stderr noise, empty-state edges silent.
- Installed copy `/usr/local/bin/pos-media-ytsync`: **NOT refreshed** — `sudo -n true` fails non-interactively; per brief I skipped instead of hanging on a password prompt. User action needed: `sudo install -m 755 bin/pos-media-ytsync /usr/local/bin/`.
- Nothing committed (out of scope).

## Step 1: Pre-edit confirmation

- Read Detective report; confirmed all 3 target lines byte-for-byte as reported.
- `git status --porcelain bin/pos-media-ytsync` → empty (file git-clean pre-edit).
- HIST_FILE override seam found: `YTSYNC_STATE_DIR` env var (:51) → `HIST_FILE="$YTSYNC_STATE_DIR/history.log"` (:55). Writers :280/:286 untouched — no state migration.

[DONE]

## Step 2: Edit site 1 — `last_sync_of` (~:292)

Replaced:
```bash
        last="$(grep -F " · $name · " "$HIST_FILE" 2>/dev/null | tail -n 1 | cut -d'·' -f1 || true)"
        last="${last% }"
```
with:
```bash
        # grep may rc=1 on no match (pipefail) — || true keeps empty-string semantics
        last="$(grep -F " · $name · " "$HIST_FILE" 2>/dev/null | tail -n 1 || true)"
        last="${last%% ·*}"
```
Notes: kept `|| true` — under `set -o pipefail` a no-match grep would otherwise abort the assignment under strict mode; `${last%% ·*}` subsumes the old trailing-space strip. Return semantics preserved (empty → caller prints `-` via `${last:--}` at :296).

[DONE]

## Step 3: Edit site 2 — `last_run_overall` (~:301, now :302)

Replaced:
```bash
        last="$(tail -n 1 "$HIST_FILE" | cut -d'·' -f1 || true)"
        last="${last% }"
```
with:
```bash
        last="$(tail -n 1 "$HIST_FILE" || true)"
        last="${last%% ·*}"
```
Notes: `-f` HIST_FILE guard retained; `|| true` retained for exact prior failure semantics (any read problem → empty string, not abort); "empty string = no last run" preserved for the menu-suffix logic at :1048.

[DONE]

## Step 4: Edit site 3 — `menu_render` separator (~:1053, now :1054)

`printf '--------------------------------------------\n'` → `printf '%s\n' '--------------------------------------------'`

[DONE]

## Step 5: Gate verification

| Gate | Command | Result |
|---|---|---|
| Syntax | `bash -n bin/pos-media-ytsync` | OK |
| Gen | `make gen` | ran clean (`gen-docs: write OK`) — see Step 7 |
| Check | `make check` | `check-sync: OK` |
| Lint | `make lint` | `0 FAIL, 0 WARN (convention lint)` |

[DONE]

## Step 6: Smoke probe (throwaway state, cleaned up after)

Harness: `YTSYNC_STATE_DIR=/tmp/opencode/ytsync-probe/state`; `history.log` written in exact writer format (:280), e.g. `2026-08-22 10:00 · testname · 2 new · 1 skipped · 0 failed`; registry `\x1f` record with subdir basename `testname`. Menu driven through a pty (`script -qec`) because `interactive_menu` requires a tty (`require_tty` :1120, `read </dev/tty` :1129) — plain stdin piping can't reach it; `0\n` sent to exit.

```
== Probe A: interactive menu render ==
5:  1) Sync all channels now   (1 tracked · last run 2026-08-22 10:00)
A1: last-run suffix PRESENT
A2: bottom separator PRESENT
A3: no cut:/printf: errors
A4: exit rc=0 (menu exited on '0')

== Probe B: 'list' subcommand table (site last_sync_of) ==
  NAME      TYPE      VIDEOS  LAST SYNC   DESTINATION
  testname  playlist       0  2026-08-22  ~/Videos/YouTube/testname
B1: LAST SYNC date rendered
B2: stderr clean (0 bytes)
B3: exit rc=0

== Probe C: empty-state edges (no history.log) ==
C1: empty-list message OK   C2: runs silent   C3: rc=0

PROBE_RESULT: ALL_ASSERTIONS_PASSED
```

Temp dir removed afterwards.

[DONE]

## Step 7: Scope / necessary-dependency disclosure (generated files)

Approved scope was `bin/pos-media-ytsync` ONLY; that is exactly what I hand-edited. The mandated `make gen`, however, rewrote two **machine-generated** files:

- `DOC/AGENT_Context_Project.md` (GEN docmap/filetable blocks)
- `completions/pos.bash` (GEN flags/subcmds blocks)

Analysis of that diff: the working tree already contained another track's uncommitted WIP (share-suite refactor: `bin/pos-share-*`, untracked `lib/share-lib.sh`, `install.sh`, docs…). HEAD still has the old code (`git show HEAD:bin/pos-share-nfs-client | wc -l` → 138 vs 343 on disk), so HEAD's GEN blocks were already stale against the tree. My regen made them truthful again. Of that diff, exactly **one hunk is mine**: the filetable row `` `bin/pos-media-ytsync` | 1190 → 1191 `` (+1 line = my comment). The rest reflects pre-existing WIP, not my doing.

Why kept rather than reverted: reverting would guarantee `make check` failure (doc-sync regenerates and compares), i.e. it would break the brief's own hard gate requirement. GEN blocks are declared never-hand-edit machine output, generators are deterministic, and nothing is committed — the share track's eventual `make gen` produces byte-identical results. Classified as necessary dependency, not scope expansion. No out-of-scope *hand* edits were made.

[DONE]

## Step 8: Final diff of the three sites

```diff
diff --git a/bin/pos-media-ytsync b/bin/pos-media-ytsync
@@ -289,8 +289,9 @@ append_history_failed() {
 last_sync_of() {   # newest history line naming <display name>, date field only
     local name="$1" last=""
     if [ -f "$HIST_FILE" ]; then
-        last="$(grep -F " · $name · " "$HIST_FILE" 2>/dev/null | tail -n 1 | cut -d'·' -f1 || true)"
-        last="${last% }"
+        # grep may rc=1 on no match (pipefail) — || true keeps empty-string semantics
+        last="$(grep -F " · $name · " "$HIST_FILE" 2>/dev/null | tail -n 1 || true)"
+        last="${last%% ·*}"
     fi
     printf '%s' "${last:--}"
 }
@@ -298,8 +299,8 @@ last_sync_of() {
 last_run_overall() {
     local last=""
     if [ -f "$HIST_FILE" ]; then
-        last="$(tail -n 1 "$HIST_FILE" | cut -d'·' -f1 || true)"
-        last="${last% }"
+        last="$(tail -n 1 "$HIST_FILE" || true)"
+        last="${last%% ·*}"
     fi
     printf '%s' "$last"
 }
@@ -1050,7 +1051,7 @@ menu_render() {
         printf '  3) List channels\n'
         printf '  4) Remove a channel\n'
         printf '  0) Exit\n'
-        printf '--------------------------------------------\n'
+        printf '%s\n' '--------------------------------------------'
     } >&2
 }
```

[DONE]

## Handoff

Status: IMPLEMENTED
Approved scope: fix 3 error sites in `bin/pos-media-ytsync` (:292/:301 cut-delim, :1053 printf-format); nothing else hand-edited.
Completed: all 3 fixes + full gate budget + smoke probe.
Verification performed: bash -n OK · make check OK · make lint 0 FAIL, 0 WARN · probe ALL_ASSERTIONS_PASSED.
Remaining uncertainty / user action: installed copy NOT refreshed (`sudo -n` unavailable) — run `sudo install -m 755 bin/pos-media-ytsync /usr/local/bin/` when convenient. GEN-block regeneration touched `DOC/AGENT_Context_Project.md` + `completions/pos.bash` (mostly reflecting pre-existing share-suite WIP; only ytsync line-count row is from this task) — committer should be aware both tracks' changes will land together whenever the tree is committed.
Recommended next agent: Orchestrator (task complete; coordinate with the share-suite track before any commit).
Out-of-scope changes made: none by hand (generated-file regen disclosed in Step 7).

REPORT_PATH: ./reportAgents/2026-08-23-builder-ytsync-menu-fix.md
