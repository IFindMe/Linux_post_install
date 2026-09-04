# ytsync channel handle bug — root cause investigation

Date: 2026-09-04
Agent: Detective (read-only)
Status: ROOT_CAUSE_ESTABLISHED

## TL;DR

- **Confirmed root cause:** `run_probe()` probes the user's channel URL verbatim; yt-dlp `--flat-playlist -J` on a bare channel URL (`@handle`, `/c/`, `/user/`, `/channel/<ID>`, `music.youtube.com/channel/<ID>`) returns the channel's **TAB structure** (Videos/Live/Shorts: `_type:"playlist"`, `url:null`, `id==channel_id`) instead of videos. `collect_entries()` records **every** entry unfiltered, so the three tabs become three "new videos" that `download_video()` tries to fetch as `watch?v=<channel_id>` → `[youtube] <channel_id>: This video is unavailable`.
- **Fix (validated, not implemented):** (a) probe-time canonicalization — new helper `canonical_channel_url()` appends `/videos` to bare channel URLs, called at the top of `run_probe()` (fixes both `add` and `sync` of already-stored bare-handle registry entries, no migration); (b) defense-in-depth filter in `collect_entries()` keeping only watchable entry URLs (`watch?v=`, `youtu.be/`, `/shorts/`), plus a `_type=="video"` guard on the single-object fallback (handles empty channels gracefully).
- **Artifacts:** probes under `/tmp/opencode/*.json`; validated stub harness at `/tmp/opencode/ytsync-test/run-tests.sh` (17 assertions; 5 fail on the unfixed script, all must pass after the fix).
- **Classification:** FACT (reproduced live + function-level).

## Step 1: Read evidence + code
Read `/tmp/opencode/ytsync-probe.json`, `/tmp/opencode/ytsync-vtab.json`, and all of `bin/pos-media-ytsync` (1191 lines). Key code facts:
- `run_probe()` line 316: `yt-dlp --flat-playlist -J --no-warnings -- "$url"`.
- `collect_entries()` lines 374-392: records `.id`+`.title` of **every** `.entries[]` element; no `_type`/`url` filter; fallback to single object when no entries.
- `is_signin_skipped()` line 401: only skips empty ids / `[Private`/`[Deleted`/`[Unavailable` titles — tab entries pass.
- `classify_url()` line 157: video / playlist / channel.
- Registry stores the **original** URL (`finish_add` line 773-774). `sync` re-probes the stored URL verbatim (`run_sync_set` line 923 → `pass_prepare` line 559 → `run_probe "$S_URL"`).

[DONE]

## Step 2: Probe channel URL forms (my own reproductions)
All probes: `yt-dlp 2026.08.19 --flat-playlist -J --no-warnings`. Summarized as `shapes → outcome`:

| Probe URL | Probe shape | Verdict |
|---|---|---|
| `https://www.youtube.com/@3blue1brown` | `_type:playlist`, `id:@3blue1brown`, `playlist_count:3`; entries = 3 tabs (`_type:"playlist"`, `url:null`, `id==channel_id`) | **TABS — the bug** |
| `https://www.youtube.com/@3blue1brown/videos` | `playlist_count:151`; entries = 151 real videos (`_type:"url"`, `url:watch?v=…`) | canonical target OK |
| `https://www.youtube.com/@3blue1brown/shorts` | `playlist_count:81`; real entries, `url:youtube.com/shorts/<id>` | OK (needs `/shorts/` in filter) |
| `https://www.youtube.com/@3blue1brown/streams` | `playlist_count:10`; real entries `watch?v=` | OK |
| `https://www.youtube.com/@3blue1brown/live` | **rc=1**, stdout `null`, stderr `The channel is not currently live` | probe-fail path (unchanged) |
| `https://www.youtube.com/@3blue1brown/playlists` | `playlist_count:24`; entries `_type:"url"` **but `url:playlist?list=…`** | false-positive if unfiltered |
| `https://www.youtube.com/@3blue1brown/featured` | title "… - Home", 7 entries, `id:null`, playlist/tab urls | false-positive if unfiltered |
| `https://www.youtube.com/c/3Blue1Brown` | **tabs** (`playlist_count:3`) | needs canonicalization |
| `https://www.youtube.com/c/3Blue1Brown/videos` | 151 real videos | OK |
| `https://www.youtube.com/user/3Blue1Brown` (+`/videos`) | **rc=1, HTTP 404** | `user/` dead for this channel |
| `https://www.youtube.com/user/pewdiepie` | **tabs** (`playlist_count:2`) | works → needs canonicalization |
| `https://www.youtube.com/user/MarquesBrownlee` | **tabs** (`playlist_count:3`) | works → needs canonicalization |
| `https://www.youtube.com/channel/UCYO_…` | **tabs** | needs canonicalization |
| `https://www.youtube.com/channel/UCYO_…/videos` | 151 real videos | OK |
| `https://www.youtube.com/playlist?list=…` | `_type:playlist`; entries real `watch?v=` | OK — must stay untouched |
| `https://www.youtube.com/watch?v=…` / `https://youtu.be/…` | `_type:"video"` single object, no entries | OK — fallback path |
| `@3blue1brown` (no domain) | **rc=1** `[generic] not a valid URL` | latent ytsync wart (is_youtube_url accepts `@*`) |
| `youtube.com/@3blue1brown` (no proto) | tabs | works; canonicalizable |
| `youtube.com/@3blue1brown/videos` | 151 real videos | OK |
| `…/@3blue1brown/videos/` (trailing slash) | 151 real videos | OK — suffix check must strip slash |
| `…/@3blue1brown/videos?view=0&sort=dd` | 151 real videos | OK — suffix check must strip query |
| `…/@3blue1brown/VIDEOS` (uppercase) | **rc=1** `channel does not have a VIDEOS tab` | yt-dlp suffix is case-sensitive |
| `https://music.youtube.com/channel/UCYO_…` | tabs | needs canonicalization |
| `https://music.youtube.com/channel/UCYO_…/videos` | 151 real videos | OK |

Live functional reproduction (read-only, `--dry-run` writes nothing — registry write is behind `DRY_RUN -eq 0`, history only in non-dry runs):
```
$ bin/pos-media-ytsync sync --dry-run
Source   : https://www.youtube.com/@3blue1brown          ← stored URL re-probed verbatim
Resolved : 3Blue1Brown (channel · 3 videos)              ← the 3 TABS
New      : 3 would be downloaded (0 already present)
  3Blue1Brown - Videos.mp4 / - Live.mp4 / - Shorts.mp4   ← tab titles as "videos"
```
Matches the reported `add` output exactly (first divergence: `parse_probe`+`collect_entries` treating tab entries as videos).

[DONE]

## Step 3: Trace the call surface (who probes what URL)

`run_probe()` callers:
1. `cmd_add` line 876 — `run_probe "$url"` (user-supplied add URL; explicit mode).
2. `ask_url_interactive` line 839 — `run_probe "$u"` (interactive add; `finish_add` stores `$ASKED_URL`).
3. `pass_prepare` line 559 — `run_probe "$S_URL"`; `S_URL` comes from the registry line (read at `run_sync_set` line 923).

Mandatory conclusion: **the stored registry URL is re-probed verbatim on every sync** (confirmed by code trace AND the live dry-run above). Therefore canonicalization **inside `run_probe()`** fixes both flows at once — the existing machine registry entry (`3blue1brown … https://www.youtube.com/@3blue1brown`) needs **no migration**; it simply re-canonicalizes each probe.

`parse_probe`/`P_KEY` impact: both the bare-handle and `/videos` probe shapes carry `uploader_id:"@3blue1brown"` → `P_KEY="@3blue1brown"` → slug `3blue1brown` (matches existing registry slug). `P_TITLE` changes cosmetically (`3Blue1Brown` → `3Blue1Brown - Videos`); it is stored as the registry `S_TITLE` field but never displayed by `cmd_list`/digests. No functional impact.

[DONE]

## Step 4: Fix spec (validated, Builder-executable)

Recommended combination: **canonicalization (primary) + entry filter + fallback guard (defense-in-depth)**. Canonicalization alone fixes the report end-to-end; the filter alone would degrade a bare-handle add to "0 videos" (graceful but useless). Both are needed; both validated by simulation below.

### 4.1 New helper — insert after `classify_url()` (after line 176), before `sanitize_component()`

```bash
# ── Channel URL canonicalization ─────────────────────────────────────
# yt-dlp --flat-playlist on a bare channel URL returns the channel's
# TAB list (Videos/Live/Shorts; _type "playlist", url null, id==channel_id),
# not videos. Appending /videos makes the probe return the real videos.
canonical_channel_url() {   # add /videos to bare channel URLs; echo canonical
    local u="$1"
    case "$u" in
        @*) u="https://www.youtube.com/$u" ;;   # bare 'handle' → full URL
    esac
    [ "$(classify_url "$u")" = "channel" ] || { printf '%s' "$u"; return 0; }
    local path="${u%%\?*}"
    path="${path%%\#*}"
    path="${path%/}"
    case "${path##*/}" in
        videos | shorts | streams | live | playlists | featured | releases | podcasts | search)
            printf '%s' "$u" ;;
        *)
            printf '%s/videos' "$u" ;;
    esac
}
```

Behavior (all 16 cases tested PASS in the harness): bare `@handle` full URL → `…/videos`; bare `@3blue1brown` (no domain, fixes the latent generic-error failure) → `https://www.youtube.com/@3blue1brown/videos`; `youtube.com/@…` no-protocol → `+ /videos`; `/c/NAME`, `/user/NAME`, `/channel/ID` → `+ /videos`; `music.youtube.com/channel/ID` → `+ /videos`; already-suffixed `/videos` `/shorts` `/streams` `/live` `/playlists` `/featured`, with trailing slash or query → untouched; `?list=` / `watch?v=` / `youtu.be/<id>` → untouched.

### 4.2 `run_probe()` — one line, after `local url="$1"` (line 317)

```bash
    url="$(canonical_channel_url "$url")"
```

That is the whole integration point: `add` (both modes) and `sync` (stored URLs) now probe the Videos tab. Nothing downstream changes (S_URL stays the original; display is cosmetic).

### 4.3 `collect_entries()` — two edits (lines 374-392)

(a) Line 381 — add a `select` so only watchable entries are collected (exact in-file quoting verified):

```bash
        mapfile -t pairs < <(jq -r '.entries[] | select((.url // "") | test("watch\\?v=|youtu\\.be/|/shorts/")) | ((.id // "") + "\u001f" + (.title // ""))' "$PROBE_JSON")
```

(b) Lines 388-391 — guard the single-object fallback so empty tab/playlist probes never become one bogus video:

```bash
    elif [ "$(jq -r '._type // ""' "$PROBE_JSON")" = "video" ]; then
        ENTRY_IDS+=("$(jq -r '.id // ""' "$PROBE_JSON")")
        ENTRY_TITLES+=("$(jq -r '.title // ""' "$PROBE_JSON")")
    fi
```

Filter counts (validated): tab probe → 0; videos → 151; shorts → 81; streams → 10; playlists-tab → 0; featured → 0; playlist `?list=` → 16; video `?v=` → 1 (fallback). Empty channel (`entries:[]`, `_type:"playlist"`) → 0 → `pass_execute` line 624 prints `Sync complete: 0 new, 0 already present, 0 failed` (no 3-failure spam).

### 4.4 Error behavior — empty channel / not-live channel
- Channel with zero videos: `/videos` probe → `entries:[]` → 0 valid → graceful "0 new" summary (verified with `empty-videos.json` fixture).
- Explicit `/live` when not live: probe rc=1 → existing `notfound`/`unreachable` handling (sync: skip + `FAILED (probe)` history; add: retry prompt). Unchanged.
- Explicit `/playlists` / `/featured` URLs: untouched by canonicalization; filter now drops all playlist-URL entries → 0 new / 0 failed (previously N failed downloads). Graceful improvement, no new error path.

### 4.5 Things deliberately NOT changed
- `parse_probe`, `P_KEY`, registry line format, download loop, `classify_url` — untouched.
- Registry migration — none required (probe-time canonicalization covers stored URLs).
- Storing the canonical URL in the registry for new adds — optional cosmetic enhancement, NOT needed for correctness; recommended to skip to keep the change minimal.

[DONE]

## Step 5: Test plan

Harness (new, stub-based — no ytsync harness exists in repo): `/tmp/opencode/ytsync-test/run-tests.sh`
- Self-contained: generates 6 inline fixture JSONs (tab-probe, videos+shorts-tab, playlist, playlists-tab, single-video, empty-videos), stub `common.sh`/`notify.sh`, a recording fake `yt-dlp`; truncates `bin/pos-media-ytsync` at the `# ── Argument dispatch ──` marker and sources it (function-level tests, no network/state).
- 17 assertions: 7× `classify_url` regression; 16× `canonical_channel_url` matrix; 8× `collect_entries` fixture behavior; 1× `run_probe` URL recording.
- Baseline on the unfixed script: **12 PASS / 5 FAIL** (exactly the fix-specific assertions fail — proves the harness discriminates the bug). After the fix: all 17 must pass.

Recommended Builder self-verification (in order):
1. `bash -n bin/pos-media-ytsync`
2. `bash /tmp/opencode/ytsync-test/run-tests.sh` → 0 failed
3. `./bin/pos-media-ytsync sync --dry-run` → `Resolved : 3Blue1Brown (channel · 151 videos)`, real titles, `151 would be downloaded`
4. Real limited download into temp dirs (never the real `~/Videos`):
   `YTSYNC_STATE_DIR=/tmp/yts-state YTSYNC_VIDEOS_DIR=/tmp/yts-vids ./bin/pos-media-ytsync add https://www.youtube.com/@3blue1brown`
   then interrupt after the first videos (safe: temp dir; yt-dlp renames atomically, archive records completed ones); verify `archive/3blue1brown.txt` grows and flat `<title>.mp4` layout.
5. `make check` and `make lint` (must end `0 FAIL, 0 WARN`); commit with conventional prefix + AGENT_TODO.md Done move.

Edge-case matrix (URL form → after-fix behavior):
- bare `@handle` / `/c/` / `/user/` (resolvable) / `/channel/ID` / `music.…/channel/ID` → canonicalized to `/videos` → real videos.
- `@handle` (no domain) → full canonical URL → real videos (fixes latent failure).
- `/videos`, `/shorts`, `/streams`, `/live`, `/playlists`, `/featured` explicit suffixes → untouched; shorts/streams pass filter; playlists/featured yield graceful 0; live fails gracefully if not live.
- `?list=`, `?v=`, `youtu.be/<id>` → untouched, behave as today.
- `/user/` URLs that 404 → unchanged notfound failure path (pre-existing; `/user/` is deprecated by YouTube).
- Uppercase suffix (`@h/VIDEOS`) → untouched → yt-dlp error (pre-existing; suffix check is intentionally case-sensitive).
- Existing stored bare-handle registry entries → work without migration; archive has no stale ids (the 3 broken downloads never reached the archive).

[DONE]

## Handoff

Status: ROOT_CAUSE_ESTABLISHED

Symptom: `pos media ytsync add https://www.youtube.com/@3blue1brown` (and `sync` of the stored URL) resolves the channel's 3 tabs as videos and fails each download with `[youtube] UCYO_jab_es: This video is unavailable`.

Expected: resolve the channel's actual videos and download new ones incrementally.

Actual: probe returns tab entries (Videos/Live/Shorts); `collect_entries` records them unfiltered; 3 failed downloads; summary "0 new … 3 failed".

Root cause: `run_probe` probes the bare channel URL verbatim; yt-dlp flat-playlist on channel URLs returns channel tabs (`_type:"playlist"`, `url:null`, `id==channel_id`), not videos; `collect_entries` has no non-video entry filter, so tabs are downloaded as `watch?v=<channel_id>` and fail.

Classification: FACT (live reproduction: sync dry-run shows the 3 tab titles; function-level reproduction: tab fixture yields 3 entries; probe evidence table).

Evidence: probe JSONs `/tmp/opencode/ytsync-{probe,vtab}.json` + my additional probes; filter counts above; harness baseline 12/17.

Tests performed: 24 URL-form probes (matrix above); jq filter validation on 6 shapes; fallback guard validation on 4 fixtures; live `sync --dry-run` reproduction; harness mechanics + baseline run.

Alternatives eliminated:
- "yt-dlp version regression" — no; current yt-dlp behavior is inherent for channel URLs (tabs), `/videos` suffix returns videos (probed).
- "URL should be classified as playlist" — no; channel classification is correct; the probe target is the problem.
- "Filter `_type=="url"` only" — rejected: `/playlists`-tab entries are `_type:"url"` with playlist IDs; the watch-URL test is the correct discriminator (validated).
- "Registry migration needed" — no; probe-time canonicalization covers stored URLs (traced + live dry-run).

Affected components: `bin/pos-media-ytsync` — `run_probe` (line 316), `collect_entries` (lines 374-392); new helper `canonical_channel_url`; no change to registry format.

Scope / decision boundary: none — pure bug fix within the tool; no architectural decisions required.

Recommended next agent: Builder

Reason: root cause and the exact code-level fix (validated by simulation and the stub harness) are established; implementation + `make gen/check/lint` + harness green are Builder work.

Changes made by Detective: none (repo untouched; scaffolding + harness in `/tmp/opencode/` only).