# How-To: `pos media`

Download audio and video from the web via `yt-dlp`, and sync your library to a
USB stick. Tools: `mp3`, `mp4`, `sync`.

| Tool | What it does |
|------|--------------|
| `pos media mp3` | Download audio, convert to MP3 |
| `pos media mp4` | Download video with smart/interactive format selection |
| `pos media sync` | Incrementally copy `~/Music` onto a USB stick (mp3/mp4) |

Requires `yt-dlp` and `ffmpeg` (`sudo apt install yt-dlp ffmpeg`); the tools
fail with a clean error message instead of a raw `command not found` if either
is missing.

---

## `pos media mp3` — audio as MP3

```bash
pos media mp3 <url>
```

Extracts and converts the audio track to MP3 in `~/Music/`. With `--by-artist`
files land in `~/Music/<artist>/<title>.mp3` (falls back to the uploader name
when there's no artist tag), so a library stays organized.

```bash
pos media mp3 https://youtube.com/watch?v=dQw4w9WgXcQ
pos media mp3 --by-artist https://youtu.be/dQw4w9WgXcQ
```

MP3s are encoded at best quality with title/artist/album/date/chapters embedded
(`--embed-metadata --embed-chapters`, artist falls back to uploader) plus the
cover art as a JPEG thumbnail. Existing files are never overwritten.

| Flag | Meaning |
|------|---------|
| `-o, --output <dir>` | Output directory (default `~/Music`) |
| `--by-artist` | Organize as `<dir>/<artist>/<title>.mp3` |
| `--no-playlist` | Download only the single video, not the playlist |
| `--cookies <file>` | Netscape cookies.txt for age-gated content |
| `--dry-run` | Print the yt-dlp command without running it |

**Recipe:** batch — loop over a list of URLs:
```bash
while read -r url; do pos media mp3 --by-artist "$url"; done < urls.txt
```

---

## `pos media mp4` — video with smart format choice

```bash
pos media mp4 <url>
```

Without a format flag, the available formats are shown as a **short curated
list** (grouped `[audio]` / `[video]` / `[combo]`, with the raw dump's clutter
dropped) and you pick one — the id is validated before downloading. Entering
nothing (or `best`) picks the best video+audio automatically.

Non-interactive (scripting-friendly):

| Flag | Meaning |
|------|---------|
| `-f, --format <id>` | Download that format id directly (no prompt) |
| `--best` | Best video + audio, no prompt |
| `--worst` | Lowest quality, no prompt |
| `-o, --output <dir>` | Output directory (default `~/Videos`) |
| `--no-playlist` | Download only the single video |
| `--cookies <file>` | Netscape cookies.txt for age-gated content |
| `--dry-run` | Print the yt-dlp command without running it |

```bash
pos media mp4 --best https://youtube.com/watch?v=dQw4w9WgXcQ
pos media mp4 -f 22 https://youtube.com/watch?v=dQw4w9WgXcQ
```

Videos merge to MP4 with metadata, chapters, subtitles (all languages) and the
thumbnail embedded (`--embed-metadata --embed-chapters --embed-subs
--sub-langs all --embed-thumbnail`); existing files are never overwritten.

**Recipe:** grab a 4K stream for later — `--best` already picks the best
video+audio and merges them.

---

## `pos media sync` — music onto a USB stick

```bash
pos media sync          # copy everything (mp3 + mp4) from ~/Music to the stick
pos media sync --mp3    # only the .mp3 files
pos media sync --mp4    # only the .mp4 files
```

Detects connected USB storage exactly like `pos system backup` (same shared
`lib/usb-lib.sh`): a plugged-in but unmounted stick is offered a mount first
(`/media/<label>`, world-writable, mirrors `usb-automount`), multiple sticks
are listed for you to pick, and if nothing is plugged in it re-scans after you
press Enter. Files are mirrored into `<usb>/Music/` (change with
`MEDIA_SYNC_DEST`) preserving the artist/album tree.

**Sync semantics — add/update only, never delete.** Files missing on the stick
are copied; files whose size or mtime changed are overwritten; everything
identical is skipped. Files on the stick that are no longer in the source are
**left alone** — a playback stick can never lose files to a mirror mistake.
Copies keep the source timestamps (`cp --preserve=timestamps`), so a re-run is
a no-op. Preview before copying with `--dry-run`:

```bash
pos media sync --mp4 --dry-run   # shows "would copy" list + counts, copies nothing
```

The source folder may be a symlink to a library elsewhere
(`~/Music -> /mnt/data/music`) — it is followed, the artist/album tree is
mirrored under the symlink's target.

**Target picking.** Mounted USB partitions are listed with size, label and
filesystem (single candidate → confirm prompt; several → numbered picker, one
row per partition). EFI system partitions (e.g. a Ventoy stick's `VTOYEFI`,
32 MB) are **never** offered as a target — they are boot machinery, not
storage. Before any copy the tool verifies the payload fits (`df` vs the
exact bytes to copy) and fails fast with `Not enough free space on …` instead
of dying mid-copy with `No space left on device`.

| Flag | Meaning |
|------|---------|
| `--mp3` | Sync only `*.mp3` (neither flag = both) |
| `--mp4` | Sync only `*.mp4` (neither flag = both) |
| `--source <dir>` | Source folder (default `~/Music`) |
| `--dry-run` | Preview what would be copied, copy nothing |

When it finishes it announces the result via `lib/notify.sh`
(`Music sync completed: N added, M updated → <usb>/Music`).

**Recipes:**
```bash
pos media sync                    # keep the car stick up to date (both formats)
pos media sync --mp3 --dry-run    # check what a new batch will bring first
pos media sync --source /data/Music   # sync a library that lives elsewhere
```

Config (all in `~/.config/linux_post_install/system.env` or exported):
`MEDIA_SYNC_SOURCE` (default `$HOME/Music`), `MEDIA_SYNC_DEST` (default
`Music`), plus the shared `USB_MOUNT_BASE` / `USB_BYID` seams.

---

## Troubleshooting

- Format list is empty / download fails → the site or age-gate requires
  cookies; pass `--cookies ~/cookies.txt` (export it from your browser), or
  update yt-dlp (`sudo apt upgrade yt-dlp`).
- Error about a missing postprocessor → `sudo apt install ffmpeg`.
- `--by-artist` leaves files loose → the source has no artist/uploader tag;
  it falls back to the uploader name in the artist slot.
- Very large downloads: ensure free space; files land in `~/Music`/`~/Videos`
  (or your `-o` directory).

---

## Related

- Reference: [DOC/POS.md → media](../POS.md)
