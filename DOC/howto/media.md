# How-To: `pos media`

Download audio and video from the web via `yt-dlp`. Tools: `mp3`, `mp4`.

| Tool | What it does |
|------|--------------|
| `pos media mp3` | Download audio, convert to MP3 |
| `pos media mp4` | Download video with interactive format selection |

Requires `yt-dlp` (`sudo apt install yt-dlp`); the tools fail with a clean
error message instead of a raw `command not found` if it's missing.

---

## `pos media mp3` — audio as MP3

```bash
pos media mp3 <url>
```

Extracts and converts the audio track to MP3 in the current directory.

```bash
pos media mp3 https://youtube.com/watch?v=dQw4w9WgXcQ
```

**Recipe:** batch — loop over a list of URLs:
```bash
while read -r url; do pos media mp3 "$url"; done < urls.txt
```

**Troubleshooting:** MP3 conversion needs `ffmpeg`; if the tool errors about a
missing postprocessor, `sudo apt install ffmpeg`. Single-song playlists: use the
video URL directly, or a playlist entry.

---

## `pos media mp4` — video with format choice

```bash
pos media mp4 <url>
```

Lists the available formats (`yt-dlp -F`) and lets you pick interactively, then
downloads to the current directory.

```bash
pos media mp4 https://youtube.com/watch?v=dQw4w9WgXcQ
```

**Recipe:** grab a 4K stream for later — pick the highest `video only` format +
best audio; yt-dlp merges them (again needs `ffmpeg`).

**Troubleshooting:**
- Format list is empty → the site/age-gate requires cookies/auth; yt-dlp can't
  access it — use a URL yt-dlp supports, or update yt-dlp (`sudo apt upgrade yt-dlp`).
- Very large downloads: ensure free space; files land in the current directory.

---

## Related

- Reference: [DOC/POS.md → media](../POS.md)
