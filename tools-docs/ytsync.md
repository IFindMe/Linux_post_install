# `pos media ytsync` — implementation research notes

Internal reference for maintainers touching `bin/pos-media-ytsync`. The user-facing
docs live in `DOC/POS.md → media` and `DOC/howto/media.md`; the behavioral contract
is `reportAgents/2026-08-22-designer-ytsync.md` + the Architect decisions D1–D9 in
`reportAgents/2026-08-22-architect-ytsync.md`.

## Probe mechanics

One fast call per source per run:

```
yt-dlp --flat-playlist -J --no-warnings -- <url>
```

- `--flat-playlist` keeps entries as stubs, so cost is 1–2 HTTP round trips
  regardless of library size (seconds even for 2000-video channels).
- `-J` dumps a single JSON object. Parsed with `jq`:
  - display name: `.channel // .uploader // .uploader_id // .title`
  - owner (for playlist subdirs): `.channel // .uploader // .uploader_id` — no title
    fallback (avoids `Playlist Title/Playlist Title` doubling when a playlist probe
    has no channel fields)
  - key (slug source): `.uploader_id // .channel_id // .id`
  - entries: `.entries[] | (.id) + "\x1f" + (.title)`; a `?v=` URL returns a bare
    video object with **no** `.entries`, handled as a one-entry list.
- The new-list is computed BEFORE any download by diffing entry ids against
  `archive/<slug>.txt` — exact `[n/N]` counts, exact dry-run plans, zero speculative
  downloads.
- Sign-in-skipped bucket: entries with an empty id OR titles starting with
  `[Private` / `[Deleted` / `[Unavailable`. Reported as "N videos require sign-in —
  skipped"; never counted as failures.

### Why probes don't use spawn()

`lib/common.sh spawn()` **exits the process on failure** and captures output until
completion. ytsync needs recoverable probes (interactive add re-prompts ≤3×; sync
must continue other sources after one bad probe) and never wraps the download batch
(hours of silence behind a spinner). `_probe_run` mirrors spawn's OK/FAIL line UX but
returns rc, and its braille spinner frames are emitted only on a TTY so no `\r`
bytes ever reach the dispatcher's tee'd logs.

## Classification (URL shape, deterministic)

| URL contains | Type | Behavior |
|---|---|---|
| `youtu.be/<id>` path (with or without `list=`) | `video` | short links name one video — treated exactly like `v=` |
| `v=` present (with or without `list=`) | `video` | single video, downloaded with `--no-playlist`; nobody backfills a 500-video playlist by pasting a watch link |
| `list=` without any video-naming part | `playlist` | tracked source; files land as `<videos>/<owner>/<playlist>/<NNN> - <title>.<ext>` |
| neither | `channel` | flat source; `<videos>/<channel>/<title>.<ext>` |

## Download invocation (one yt-dlp call PER NEW VIDEO)

```
yt-dlp -f "bestvideo*+bestaudio/best"
       --merge-output-format mp4        # parity with pos media mp4
       --embed-metadata --embed-chapters --embed-thumbnail
       --convert-thumbnails jpg
       --no-overwrites                  # parity; collisions become "exists, kept" warnings
       --download-archive <state>/archive/<slug>.txt   # crash-safe per-video recording
       --windows-filenames              # USB/Samba/TV-safe names
       --trim-filenames 120             # headroom for the NNN prefix under 255-byte limits
       --retries 3 --fragment-retries 3
       [--no-playlist]                  # only for type=video sources
       ${YTSYNC_EXTRA_ARGS}             # appended last — user override hatch
       -o "<template>" "https://www.youtube.com/watch?v=<id>"
```

- Templates are COMPUTED from stored registry fields (`subdir`), never from yt-dlp
  placeholders like `%(playlist_title)s` — a stored subdir cannot be NA and cannot
  drift mid-library.
- Playlist template gets a LITERAL zero-padded index injected by the tool (from the
  probe's entry position), because standalone watch URLs have no live
  `%(playlist_index)s`. Caveat: inserting a video mid-playlist shifts FUTURE
  numbering; existing files are never renamed.
- Deliberate divergences from mp4: no `--embed-subs --sub-langs all` (library bloat;
  re-add per-source via `YTSYNC_EXTRA_ARGS`, appended-last wins); `--quiet
  --no-warnings` plus `--progress` only on a TTY (yt-dlp auto-simplifies progress
  when piped, keeping `\r` out of logs).
- Sequential downloads; batching is the listed future optimization (accepted v1
  cost: one extra extraction round trip per video).

## State layout (machine-owned, outside ~/Videos)

```
${YTSYNC_STATE_DIR:-~/.local/share/linux_post_install/ytsync}/
├── registry            # \x1f-delimited: slug⇥type⇥url⇥subdir⇥playlist_title⇥added_ts
├── archive/<slug>.txt  # native yt-dlp archive format ("<extractor> <id>"), one per source
└── history.log         # append-only: "<YYYY-MM-DD HH:MM> · <name> · N new · M skipped · K failed"
```

- `slug`: `[a-z0-9][a-z0-9_-]*`, derived from probed uploader_id/handle; numeric
  `-2` suffix on collision, checking registry slugs only.
- Registry/archive writes are atomic (mktemp inside the state dir + mv).
- `remove` drops only the registry line. Keeping the orphaned archive makes a future
  re-add of the same source an incremental resume instead of a full re-download that
  would collide with existing files under `--no-overwrites`.
- History grammar note: a wholesale probe failure appends `<date> · <name> · FAILED
  (probe)` instead of the numeric triple — the pass did not complete, and faking
  zeros would hide it from `grep`.

## Edge cases

- **Mid-playlist inserts** shift future numbering only (see above).
- **Title renames on YouTube** never rename local files — the archive is keyed by
  video id; local files are immutable once written.
- **Same-title collision** (`--no-overwrites` refusal): stderr is matched for
  "already been downloaded" → `[!] exists, kept: <file>`, counted into the
  "already present" tally of the summary (the fixed summary grammar has three
  buckets; tools-docs records this folding).
- **Disk full (ENOSPC)**: stderr matched for "No space left on device"/Errno 28 →
  prominent warning, that source stops mid-run (unfetched videos simply stay "new"
  next run since the archive was untouched), other channels continue.
- **Per-video generic failure**: `[!] unavailable: <title>` + first 3 stderr lines,
  continue, counted as failed. Per-video failures never flip the exit code; rc 1 is
  reserved for missing deps, invalid explicit URL, unknown/ambiguous `<name>`, or
  ≥1 requested source failing wholesale during sync.
- **Slug stability**: the slug derives from the probed `uploader_id`. If YouTube
  ever changes that id for a channel, a re-add computes a different slug whose
  archive starts empty → existing files would be "re-downloaded", hitting
  `--no-overwrites` and spamming `exists, kept` warnings. Manual mitigation if it
  ever bites: rename the old `archive/<old-slug>.txt` to the new slug before
  syncing. Accepted v1 limitation (Architect §Remaining uncertainty #4).

## Testing seams

- `YTSYNC_STATE_DIR`, `YTSYNC_VIDEOS_DIR` — every written path honors them
  (written `VAR="${VAR:-default}"`). Fake `yt-dlp` arrives via stub PATH emitting
  canned `-J` JSON; fake notify via a stubbed sender appending to `sends.log`.
- Interactive reads all come from `/dev/tty` (NOT stdin), so the tool is NOT in
  `bin/pos`'s INTERACTIVE_CMDS and dispatched runs keep full tee logging; non-tty
  interactive entry points print the guard line and exit 0.
