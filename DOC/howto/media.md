# How-To: `pos media`

Download audio and video from the web via `yt-dlp`, auto-classify URLs,
sync your library to a USB stick, and keep YouTube channels incrementally
up to date.
Tools: `yt mp3`, `yt mp4`, `yt grab`, `yt subtitles`, `sync`, `ytsync`.

The YouTube download tools live under `pos media yt` (`mp3`, `mp4`, `grab`,
`subtitles`, `ytsync`). The legacy standalone names `pos media mp3`, `pos media
mp4` and `pos media grab` still work — they are thin forwarders to the `yt`
forms.

| Tool | What it does |
|------|--------------|
| `pos media yt mp3` | Download audio, convert to MP3 |
| `pos media yt mp4` | Download video with smart/interactive format selection |
| `pos media yt grab` | Auto-classify URL and download as audio or video |
| `pos media yt subtitles` | Extract subtitles/captions from a URL |
| `pos media yt ytsync` | Forwarder → `pos media ytsync` |
| `pos media sync` | Incrementally copy `~/Music` onto a USB stick (mp3/mp4) |
| `pos media ytsync` | Track YouTube channels/playlists and download only new videos into `~/Videos` |

Requires `yt-dlp` and `ffmpeg` (`sudo apt install yt-dlp ffmpeg`) for `mp3`/
`mp4`/`grab`; `subtitles` needs only `yt-dlp` (no ffmpeg). The tools fail with a
clean error message instead of a raw `command not found` if a dependency is
missing.

---

## `pos media yt mp3` — audio as MP3

```bash
pos media yt mp3 <url>        # or the legacy: pos media mp3 <url>
```

Extracts and converts the audio track to MP3 in `~/Music/`. With `--by-artist`
files land in `~/Music/<artist>/<title>.mp3` (falls back to the uploader name
when there's no artist tag), so a library stays organized.

```bash
pos media yt mp3 https://youtube.com/watch?v=dQw4w9WgXcQ
pos media yt mp3 --by-artist https://youtu.be/dQw4w9WgXcQ
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
while read -r url; do pos media yt mp3 --by-artist "$url"; done < urls.txt
```

---

## `pos media yt mp4` — video with smart format choice

```bash
pos media yt mp4 <url>        # or the legacy: pos media mp4 <url>
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
pos media yt mp4 --best https://youtube.com/watch?v=dQw4w9WgXcQ
pos media yt mp4 -f 22 https://youtube.com/watch?v=dQw4w9WgXcQ
```

Videos merge to MP4 with metadata, chapters, subtitles (all languages) and the
thumbnail embedded (`--embed-metadata --embed-chapters --embed-subs
--sub-langs all --embed-thumbnail`); existing files are never overwritten.

**Recipe:** grab a 4K stream for later — `--best` already picks the best
video+audio and merges them.

---

## `pos media yt grab` — auto-classify URL and download

```bash
pos media yt grab <url>       # or the legacy: pos media grab <url>
```

Smart URL classifier that routes to `pos media yt mp3` or `pos media yt mp4`
automatically based on the domain. Send a URL from your phone via Telegram and
the bot downloads it to the right place without you thinking about it.

**Classification rules:**

| Domain | Routes to | Why |
|--------|-----------|-----|
| `music.youtube.com` | mp3 | Audio streaming |
| `soundcloud.com` | mp3 | Audio-first platform |
| `bandcamp.com` | mp3 | Audio-first platform |
| `youtube.com` / `youtu.be` | mp4 | Video content |
| `vimeo.com` / `twitch.tv` | mp4 | Video platforms |
| Everything else | mp4 (default) | Safe fallback |

Override the classification with `--audio` or `--video`. The default for
unrecognized domains is `video` — change it with `pos config grab` or set
`GRAB_DEFAULT=audio` in `~/.config/linux_post_install/grab.env`.

```bash
pos media yt grab https://music.youtube.com/watch?v=abc          # → ~/Music
pos media yt grab https://youtube.com/watch?v=xyz                # → ~/Videos
pos media yt grab --audio https://vimeo.com/123                  # force mp3
pos media yt grab --worst https://youtu.be/abc                   # lowest quality
pos media yt grab --dry-run https://soundcloud.com/artist/track  # preview only
```

Non-interactive by design — `pos media yt mp4` receives `--best` by default so
it never prompts for a format (critical for Telegram bot context where there's
no TTY). Pass `--worst` if you want the smallest file.

| Flag | Meaning |
|------|---------|
| `--audio` | Force audio (mp3) download |
| `--video` | Force video (mp4) download |
| `--best` | Best quality for video (default) |
| `--worst` | Lowest quality for video |
| `-o, --output <dir>` | Output directory (passed to mp3/mp4) |
| `--no-playlist` | Download only the single video |
| `--cookies <file>` | Netscape cookies.txt for age-gated content |
| `--dry-run` | Print the command that would run, don't execute |

---

## `pos media yt subtitles` — extract subtitles/captions

```bash
pos media yt subtitles <url>
```

Downloads subtitles/captions from a URL via yt-dlp. Fetches manual captions and
auto-generated captions by default (`--write-subs --write-auto-subs
--sub-langs best` — "best" picks the manually-created track when available,
otherwise the auto one). Output files land in the current directory as
`<title>.<lang>.<ext>`.

```bash
pos media yt subtitles https://youtube.com/watch?v=dQw4w9WgXcQ
pos media yt subtitles --lang en https://youtu.be/dQw4w9WgXcQ
pos media yt subtitles --lang en,ar --format txt https://youtube.com/watch?v=dQw4w9WgXcQ
```

| Flag | Meaning |
|------|---------|
| `--lang <list>` | Subtitle languages, comma-separated (default `best`) — `en,ar` is passed as ONE `--sub-langs` arg |
| `--format <fmt>` | `srt` (default) / `vtt` / `txt` — `txt` converts srt→txt (timestamps, seq numbers and HTML tags stripped) |
| `--auto-only` | Only auto-generated captions (no manual subs) |
| `-o, --output <dir>` | Output directory (default: current directory) |
| `--list-subs` | List available subtitles for the URL and exit (probe only, no download) |
| `--no-playlist` | Download only the single video |
| `--dry-run` | Print the yt-dlp command without running it |

If a video has no available subtitles the tool reports
`unavailable subtitles for this video (try --list-subs to check)`.

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

## `pos media ytsync` — incremental YouTube channel sync

```bash
pos media ytsync                                  # interactive
pos media ytsync add https://youtube.com/@SomeChannel
pos media ytsync sync                             # fetch new videos from every source
pos media ytsync list
pos media ytsync remove "Some Channel"
```

The first run asks for a channel or playlist URL, shows what was resolved
(`Resolved : Linus Tech Tips (channel · 2140 videos)` + the target library path),
and downloads everything. Every later run probes the same URL, diffs it against a
per-source download archive, and fetches **only new videos** — one yt-dlp call per
video (`bestvideo*+bestaudio/best` merged to MP4 with metadata, chapters and the
thumbnail embedded; existing files are never overwritten).

Where files land:

```
~/Videos/<channel>/<title>.mp4                              # channels & single videos
~/Videos/<channel>/<playlist>/<NNN> - <title>.mp4           # playlist sources (playlist order)
```

| Command | Meaning |
|---------|---------|
| `add [url]` | Register a source + first download (asks for the URL if omitted) |
| `sync [name]` | Incremental pass — all tracked sources, or one by slug/display name |
| `list` | Tracked sources table: type, archived count, last sync date, destination |
| `remove <name>` | Stop tracking. Downloaded files AND the archive are kept |

Notes:

- A watch link with **both** `?v=` and `&list=` downloads only that single video,
  never the whole playlist; `youtu.be/<id>` short links count as watch links too.
- Retitled/renamed videos keep their local filenames (the archive is keyed by video
  id); inserting a video mid-playlist shifts future numbering only.
- Members-only / age-gated videos are skipped with a count ("N videos require
  sign-in"). Escape hatch: put `YTSYNC_EXTRA_ARGS=--cookies-from-browser firefox`
  (or `--cookies <file>`) into the config file below.
- State lives outside `~/Videos`, in `~/.local/share/linux_post_install/ytsync/`
  (registry, per-source archives, run history) — the media tree stays pure media.

**Recipe: daily automation** — no built-in timers; use the shared scheduler:

```bash
pos system schedule config     # name: ytsync
#   INTERVAL=daily            (or hourly / weekly / OnCalendar=…)
#   NOTIFY=never              # ytsync sends its own digest; don't double-notify
#   MSG="ytSync"
#   COMMAND=pos media ytsync sync
pos system schedule enable ytsync
pos system schedule run ytsync # test once, right now
```

ytsync never prompts on `sync`, so the job is timer-safe by construction. It
notifies via `lib/notify.sh` only when something happened (new videos or failures);
a scheduled no-op run stays silent — hence `NOTIFY=never` on the job to avoid
double alerts.

**Previewing:** `--dry-run` works on `add` and `sync` — real probe + plan block
(`New : 12 would be downloaded (800 already present)` + example filenames), zero
writes anywhere:

```bash
pos media ytsync sync --dry-run
pos media ytsync add https://youtube.com/@SomeChannel --dry-run
```

Config (`~/.config/linux_post_install/ytsync.env`, chmod 600 — materialize/edit via
`pos config ytsync`; exported environment wins):

| Key | Default | Meaning |
|-----|---------|---------|
| `YTSYNC_VIDEOS_DIR` | `$HOME/Videos` | Videos root for synced sources |
| `YTSYNC_EXTRA_ARGS` | *(empty)* | Extra yt-dlp flags appended to every download call (cookies, format overrides, …) |

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
- ytsync: "could not reach YouTube" at add → connectivity/DNS; the interactive
  flow re-prompts up to 3×. "source not found or private" → wrong handle or a
  deleted/private source.
- ytsync: many "exists, kept" warnings after a YouTube-side change → the
  channel's internal id changed, so re-adding computed a new archive. Rename the
  old archive file (`~/.local/share/linux_post_install/ytsync/archive/<old>.txt`)
  to the new slug before syncing (see `tools-docs/ytsync.md`).
- ytsync: "disk full — stopping … mid-run" → free space on the videos volume and
  run `pos media ytsync sync` again; unfetched videos simply stay "new".

---

## Related

- Reference: [DOC/POS.md → media](../POS.md)
