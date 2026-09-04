# Builder Report: ytsync channel-handle fix

Date: 2026-09-04
Agent: Builder
Status: IMPLEMENTED

## TL;DR

- **Scope:** Single-file bug fix in `bin/pos-media-ytsync` — three changes (new helper + probe canonicalization + entry filter)
- **Files changed:** `bin/pos-media-ytsync` (+ `DOC/AGENT_Context_Project.md` line-count bump from `make gen`)
- **Baseline:** 12 PASS / 5 FAIL on unfixed script
- **Result:** 32 PASS / 0 FAIL; `make gen`/`check`/`lint` all green; live dry-run shows 151 real videos; NOT committed
- **Status: IMPLEMENTED**

## Step 1: Implement `canonical_channel_url()` helper

Insert after `classify_url()` (after line 176), before `sanitize_component()`.

[DONE]

## Step 2: Wire canonicalization into `run_probe()`

Add `url="$(canonical_channel_url "$url")"` after `local url="$1"` in `run_probe()`.

[DONE]

## Step 3: Add entry filter in `collect_entries()`

(a) Filter `.entries[]` to watchable URLs only
(b) Guard single-object fallback with `_type == "video"` check

[DONE]

## Step 4: Syntax check

`bash -n bin/pos-media-ytsync`

[DONE]

## Step 5: Test harness — all assertions pass

Baseline was 12 PASS / 5 FAIL. After fix: **32 PASS / 0 FAIL** (Detective's 17 logical checks; harness counts 32 check calls — all green).

[DONE]

## Step 6: Gates — make gen && make check && make lint

`make gen` OK (regenerated `DOC/AGENT_Context_Project.md` — bumped hand-maintained line-count row for `bin/pos-media-ytsync` 1191 → 1213). `make check` OK. `make lint` → `0 FAIL, 0 WARN`.

[DONE]

## Step 7: Live dry-run — 3Blue1Brown sync

Seeded `/tmp/opencode/ytsync-live/` with a copy of the real registry (bare-handle URL). Ran:
`YTSYNC_STATE_DIR=/tmp/opencode/ytsync-live YTSYNC_VIDEOS_DIR=/tmp/opencode/ytsync-live/vids bin/pos-media-ytsync sync --dry-run`

Output (exact match to expected):
```
Source   : https://www.youtube.com/@3blue1brown        ← stored URL unchanged (no migration)
Resolved : 3Blue1Brown (channel · 151 videos)
New      : 151 would be downloaded (0 already present)
  But what is cross-entropy? | Compression is Intelligence Part 2.mp4
  Reinventing Entropy | Compression is Intelligence Part 1.mp4
  ...
  … 146 more
```
Real video titles, not Videos/Live/Shorts tabs. Wrote nothing (archive empty, vids empty, registry unchanged).

[DONE]

## Step 8: One real download proof

Downloaded exactly one entry (`GlYgs6v2YfU` = "But what is cross-entropy?") standalone via
`yt-dlp -o /tmp/opencode/ytsync-live/test.%(ext)s https://www.youtube.com/watch?v=GlYgs6v2YfU --no-playlist`.

yt-dlp resolved the video (not "[youtube] <id>: This video is unavailable"), pulled metadata, and began streaming (~154 MB / 31% of a 471 MiB file before the 180s tool timeout). Partial file cleaned up. This proves the dry-run probe's entry ids are valid and fetchable.

[DONE]
