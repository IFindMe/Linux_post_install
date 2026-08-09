# How-To: `pos media`

Download audio and video from the web via `yt-dlp`. Tools: `mp3`, `mp4`.

| Tool | What it does |
|------|--------------|
| `pos media mp3` | Download audio, convert to MP3 |
| `pos media mp4` | Download video with smart/interactive format selection |

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
