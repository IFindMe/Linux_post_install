# Builder Report — `pos media ytsync` (2026-08-22)

**Status: IMPLEMENTED_WITH_RISKS** (risks are documented YouTube-side unknowns, not implementation defects)

---

## Objective

Implement the approved `pos media ytsync` tool per the binding contracts
`reportAgents/2026-08-22-architect-ytsync.md` (decisions D1–D9) and
`reportAgents/2026-08-22-designer-ytsync.md` (verbatim UX copy), plus the D8
documentation checklist, green gates, and a stub-PATH verification suite —
without touching out-of-scope files and without committing anything (the
working tree carries unrelated, pre-existing share-suite work).

## Approved scope

- New: `bin/pos-media-ytsync`, `tools-docs/ytsync.md`
- Doc edits (D8): `DOC/POS.md`, `DOC/HOWTO.md`, `DOC/howto/media.md`,
  `DOC/AGENT_Context_Project.md` §14, `AGENT_TODO.md`, optional `bin/pos` EXAMPLES line
- Gates: `make gen && make check && make lint` → 0 FAIL / 0 WARN
- Verification: PATH-stub yt-dlp suite via env seams; real `$HOME` untouched

## What was built

### `bin/pos-media-ytsync` (1179 lines, mode 755)

Subcommands `add [url] / sync [name] / list / remove <name>` + `--dry-run`;
bare invocation = interactive menu (`/dev/tty` reads, EOF-safe, deliberately NOT
in `INTERACTIVE_CMDS`; empty state goes straight to the URL prompt). Verbs never
prompt — scheduler/timer safe by construction.

Key mechanics:

- **Probe**: one `yt-dlp --flat-playlist -J --no-warnings` call parsed with jq;
  name chain `.channel // .uploader // .uploader_id // .title`;
  `list=` w/o `v=` ⇒ playlist, `v=` ⇒ video (+`--no-playlist`), else channel;
  single-video objects (no `.entries`) handled as one-entry lists.
- **Diff-before-download**: new list computed against the per-source
  `--download-archive` BEFORE any download ⇒ exact counts, exact dry-run plans,
  zero speculative downloads.
- **Download skeleton** (D4 flag order): `yt-dlp --quiet --no-warnings --ignore-config
  --no-playlist? --format bestvideo*+bestaudio/best --merge-output-format mp4
  --embed-metadata --embed-chapters --embed-thumbnail --convert-thumbnails jpg
  --download-archive ARCH --retries 3 --no-overwrites --windows-filenames
  --trim-filenames 120 [--progress if tty] EXTRA_ARGS -o TPL URL`.
- **State** (machine-owned, outside ~/Videos):
  `$YTSYNC_STATE_DIR/{registry(\x1f-delimited slug/type/url/subdir/title/ts),
  archive/<slug>.txt, history.log}`; all writes atomic temp+mv.
- **Failure semantics**: per-video failure ⇒ counted + continue (rc stays 0);
  ENOSPC ⇒ prominent warning + stop that source mid-run (other sources continue);
  wholesale probe failure ⇒ history variant line `<date> · <name> · FAILED (probe)`,
  rc 1 only when an explicitly requested source fails.
- **Notify**: digest only when new>0 or failed>0; ≤5 titles + "…and M more";
  single-source dest vs videos root; ERR-trap alarm armed ONLY around download loops.
- **Config scope** `ytsync`: `YTSYNC_VIDEOS_DIR`, `YTSYNC_EXTRA_ARGS`
  (`pos config ytsync`); env > file > default; deps guards before `-h|--help`
  (yt-dlp+jq active under `--dry-run`, ffmpeg skipped there).

### Docs

- `tools-docs/ytsync.md` — research notes (probe mechanics, why probes don't use
  spawn(), classification table, download invocation, state layout, edge cases).
- `DOC/POS.md` — media table row + detail block (watch-link rule, remove/resume,
  sign-in note + cookies escape hatch).
- `DOC/HOWTO.md` + `DOC/howto/media.md` — row wording, full ytsync section
  (usage, layout, command table, notes), configurable-interval
  `pos system schedule` recipe (`COMMAND=pos media ytsync sync`, `NOTIFY=never`),
  troubleshooting bullets.
- `DOC/AGENT_Context_Project.md` §14 Common-Tasks row.
- `AGENT_TODO.md` Done entry (2026-08-22).
- `bin/pos` usage() EXAMPLES: one line under the media block.

## Contract deviations (all justified, none silent)

1. **Custom probe runner instead of `spawn()`**: spawn exits the process on
   failure; probes must be recoverable (interactive re-prompt ×3, per-source
   continue). Built `run_probe()` with the same spinner/LF-log UX, but returning rc.
2. **Collision accounting folded into "already present"**: a video yt-dlp reports
   as already-downloaded increments R_EXISTS and is added to R_PRESENT in the
   summary rather than double-counted as new+failed.
3. **`FAILED (probe)` history variant**: wholesale probe failures append their own
   history line so `last run` info reflects reality even when nothing downloaded.
4. **Post-verb flag positions accepted** (`add <url> --dry-run`, `sync <name>
   --dry-run`): required by Designer §UX case 5; initial single-pass-break parser
   rejected them — caught by the stub suite, fixed before handoff.
5. **Add-path present/sign-in counters bug** (caught by stub suite): `finish_add`
   bypassed `pass_prepare`, so add summaries showed `0 already present` and
   dropped the sign-in count when the archive already had ids (remove→re-add
   resume). Fixed by mirroring pass_prepare's two counter lines; covered by test.

## Verification performed

Gates (after final edits):

    make gen   → gen-docs: write OK
    make check → check-sync: OK
    make lint  → 0 FAIL, 0 WARN (convention lint)

Stub-PATH battery `/tmp/opencode/run-ytsync-suite.sh` (fake yt-dlp emitting canned
`-J` JSON + fake telegram sender; seams `YTSYNC_STATE_DIR`, `YTSYNC_VIDEOS_DIR`,
`CONFIG_DIR`, `HOME` pointed into /tmp/opencode/ytsync-test):

    RESULT: PASS=71 FAIL=0

Coverage: dep-guard copy exactness (--help and --dry-run) · non-tty guard rc0 +
verbatim hint · verb-less --dry-run hint rc1 · empty-state sync/list messages ·
add --dry-run real-probe plan copy + zero state writes · explicit add registry
row (\x1f fields) · archive exactly-valid-ids (private skipped) · progress header/
per-video start lines · summary grammar verbatim · notify digest on new>0 (+ dest)
· idempotent second sync (0 new / all present / no notify spam) · history per run ·
sync NAME --dry-run zero mutation · incremental upstream delta (exactly 1 call,
[1/1]) · per-video failure counted + continues + not archived + failure notify ·
ENOSPC stops source mid-run (no further calls) · playlist NNN literal index
injection (001 - %(title)s.%(ext)s) · v=&list= ⇒ type=video + --no-playlist ·
list table + State footer · remove by display name drops registry row, KEEPS
archive · re-add resumes against surviving archive (2 new, 6 already present) ·
unknown-source rc1 · remove-without-arg rc1 · zero CR bytes piped AND in
dispatcher tee log file · dispatcher integration rc0 through bin/pos ·
`pos help media ytsync` smoke · real $HOME (~/.local/share/linux_post_install/
ytsync + ~/Videos) byte-identical before/after (md5 snapshot).

Also verified: `git status` shows only my scoped files added/modified on top of
the pre-existing share-suite dirt; no commits made.

## Files changed

    bin/pos-media-ytsync                (new, 1179 lines, 755)
    tools-docs/ytsync.md                (new)
    reportAgents/2026-08-22-builder-ytsync.md (this file)
    DOC/POS.md                          (media row + detail block)
    DOC/HOWTO.md                        (line 15 wording)
    DOC/howto/media.md                  (intro row, ytsync section, schedule recipe, troubleshooting)
    DOC/AGENT_Context_Project.md        (§14 Common-Tasks row)
    AGENT_TODO.md                       (Done entry 2026-08-22)
    bin/pos                             (EXAMPLES line only)

Out-of-scope changes: none. Unrelated dirty share-suite files untouched.

## Known limitations

- **Slug stability**: derives from probed uploader_id; if YouTube ever changes it,
  re-add computes a fresh slug whose empty archive triggers collision-spam on
  existing files. Manual fix documented (rename old archive txt). Accepted v1
  limitation (Architect §Remaining uncertainty #4).
- Sign-in-gated videos are skipped with a count; cookies only via
  `YTSYNC_EXTRA_ARGS` (documented escape hatch).
- Playlist insertion mid-list shifts future numbering only (existing filenames
  kept); documented.

## Remaining uncertainty

- The battery exercises yt-dlp through a FAKE (canned JSON). Real-network behavior
  (rate limits, mixed member/public entries, live streams, region blocks) is
  untested here — first real-world run should start with `--dry-run`.
- Interactive menu flows were exercised only at the guard level (non-tty path);
  full /dev/tty interaction needs a human or a pty harness.
- Notify delivery tested via a stubbed sender binary (interface-conformant);
  real Telegram delivery depends on user config, unchanged territory.

## Recommended next agent

Tester — for adversarial edge coverage beyond the happy-path battery: malformed
probe JSON, duplicate titles, concurrent sync invocations, pty-driven interactive
menu flows, and (optionally) a supervised real-network dry-run.

Reason: implementation is complete, gates green, and my functional suite passes
71/71; independent adversarial testing is the remaining gap before acceptance.

## Changes made by Builder

In-scope implementation only, as listed under "Files changed".
