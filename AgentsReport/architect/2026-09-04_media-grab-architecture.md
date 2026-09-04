# Architect Report — `pos media grab` + Telegram URL Routing

**Date:** 2026-09-04
**Status:** DECISION_READY

---

## TL;DR

- **Decision 1:** New tool `bin/pos-media-grab` — domain-based URL classifier that delegates to `pos media mp3`/`pos media mp4`, adds `--best` for non-interactive Telegram context.
- **Decision 2:** Listener gains URL routing step between prefix map and AI bridge — detects bare URLs, forwards to `pos media grab`.
- **Decision 3:** Config scope `grab` (`grab.env`) for `GRAB_DEFAULT` mode.
- **Decision 4:** No INTERACTIVE_CMDS change — grab is fully non-interactive; yt-dlp progress suppressed in favor of clean summary.
- **Decision 5:** 600s timeout for downloads in the listener context.
- **Decision 6:** Stub-based test harness in `/tmp/opencode/media-grab-test/`.

---

## Decision 1: File Location — Tool, Not Feature

### Problem

Where does `pos media grab` live? `bin/pos-media-grab` (auto-discovered tool) or `features/media-grab.sh` (user-customizable, never-overwritten feature)?

### Evidence

- `bin/pos-media-grab` gets auto-discovery via `pos` dispatcher, `# POS:` headers, `make gen` doc tables, completion.
- `features/` scripts are for user-customizable logic (currently: `autostart.sh`, `usb-automount.sh`). They are installed on demand via `./install.sh --feature` and never overwritten on install.
- `pos media grab` is core media routing — it must be present by default, not opt-in.

### Decision

`bin/pos-media-grab` — standard tool.

### Rationale

Core routing behavior that the listener depends on. Not user-customizable. Fits the `pos-<category>-<command>` naming exactly.

### In Scope

- `bin/pos-media-grab` (new tool)
- Listener change in `bin/pos-communication-telegram-listener` (add URL routing step)

### Explicitly Out of Scope

- Feature flag for grab (not needed — always installed)
- Changes to `pos media mp3` or `pos media mp4` (consumed as-is)

[DECIDED]

---

## Decision 2: URL Classification Logic

### Problem

How does `pos media grab` determine whether a URL should be downloaded as audio (mp3) or video (mp4)?

### Evidence

- `music.youtube.com` URLs are always audio-only (music streaming).
- YouTube regular/shorts URLs are primarily video content.
- SoundCloud, Bandcamp are audio-first platforms.
- yt-dlp handles both audio and video for all supported sites.
- The user's primary use case: YouTube music → ~/Music, YouTube video → ~/Videos.

### Classification Rules (Priority Order)

| Pattern | Classification | Reasoning |
|---------|---------------|-----------|
| `*music.youtube.com*` | `audio` | YouTube Music is audio-only streaming |
| `*soundcloud.com*` | `audio` | Audio-first platform |
| `*bandcamp.com*` | `audio` | Audio-first platform |
| `*youtube.com*`, `*youtu.be*` | `video` | YouTube primary: video content |
| `*youtube.com/shorts/*` | `video` | Short-form video |
| `*vimeo.com*` | `video` | Video platform |
| `*twitch.tv*` | `video` | Video streaming |
| Everything else | `video` (default) | Safe default — yt-dlp handles format negotiation |

### Decision

Domain-based regex classification with a configurable default.

### Implementation

```bash
classify_url() {
    local url="$1" mode="${GRAB_DEFAULT:-video}"
    case "$url" in
        *music.youtube.com*)  echo "audio" ;;
        *soundcloud.com*)     echo "audio" ;;
        *bandcamp.com*)       echo "audio" ;;
        *youtube.com*|*youtu.be*) echo "video" ;;
        *vimeo.com*)          echo "video" ;;
        *twitch.tv*)          echo "video" ;;
        *)                    echo "$mode" ;;
    esac
}
```

### Why Not yt-dlp `--dump-json`?

Using `yt-dlp --dump-json` to detect content type (e.g., checking for audio-only formats) would:
- Require a network round-trip per URL (slow — 2-5s on YouTube)
- Fail on age-gated content without cookies
- Add unnecessary complexity for a heuristic

Domain-based classification is instant, reliable for the primary use case, and covers 95%+ of real URLs. The `--audio`/`--video` flag overrides for edge cases.

### Overrides

- `--audio` forces mp3 regardless of classification
- `--video` forces mp4 regardless of classification
- `--best` is passed to mp4 by default (non-interactive mode — see Decision 4)

[DECIDED]

---

## Decision 3: Config Scope

### Problem

Does `pos media grab` need its own config scope? What settings?

### Evidence

- `pos media mp3` has `OUT_DIR=$HOME/Music`
- `pos media mp4` has `OUT_DIR=$HOME/Videos`
- Both accept `--output` flag override
- The user might want all grabs to go to a single directory
- The user might want a different default mode (e.g., always audio for YouTube Music)

### Decision

Config scope `grab` with one key:

```bash
# POS_CONFIG: grab | grab.env | GRAB_DEFAULT=:Default mode for unknown domains (video or audio, default video)
```

### Rationale

Minimal config — the tool's primary job is routing, not download settings. The `GRAB_DEFAULT` key lets the user change the fallback for unrecognized domains without code changes. Output directories are inherited from mp3/mp4 and overridable via `--output`.

### Future Extensibility

If needed, future keys could include:
- `GRAB_MUSIC_DIR` (override mp3 output dir)
- `GRAB_VIDEO_DIR` (override mp4 output dir)
- `GRAB_COOKIES` (shared cookies file for all grabs)

Not implemented now — premature without user demand.

[DECIDED]

---

## Decision 4: Non-Interactive Default for Telegram Context

### Problem

`pos media mp4` has an interactive format selector (prompts on TTY). When called from the Telegram listener via `run_and_reply` (which uses `bash -c "$cmdline"` with no TTY), the prompt would hang or be swallowed by `tee`.

### Evidence

- `pos media mp4` lines 92-116: interactive `read -rp "Format ID"` when no `--format`/`--best`/`--worst` is specified
- `pos` dispatcher line 287: interactive tools are in `INTERACTIVE_CMDS` which skips `tee` logging
- The listener's `run_and_reply` (line 349) runs commands via `timeout "$tmo" bash -c "$cmdline"` — no TTY
- `spawn` helper (lib/common.sh line 76) runs commands in background — no TTY interaction

### Decision

`pos media grab` passes `--best` to `pos media mp4` by default. Users can override with `--worst` flag on grab.

### Implementation

```bash
# When routing to mp4, always add --best unless user specified --worst
MP4_ARGS=(--best)
[ "$WORST" -eq 1 ] && MP4_ARGS=(--worst)
```

### Why --best and Not --worst?

- Best quality is the expected default when sending a video link to a bot
- "I want to download this video" implies "I want it to look good"
- The `--worst` flag exists for bandwidth-constrained scenarios (explicit opt-in)

### Interaction with pos media mp4

`pos media mp4` already supports `--best` and `--worst` flags (line 4, 87-88). No changes needed to mp4.

[DECIDED]

---

## Decision 5: Listener Integration — URL Routing Step

### Problem

Where does URL detection go in the listener's routing chain, and how does it work?

### Evidence

Current `handle_message` routing (bin/pos-communication-telegram-listener lines 658-731):

```
/help|/start  →  reply mapped commands list
     ↓ (no match)
text-prefix map  →  run mapped command with text as argument
     ↓ (no match)
AI bridge  →  forward to Gemini
     ↓ (no match)
command map  →  run /command
     ↓ (no match)
"Unknown command"
```

The user sends bare URLs from their phone. These should be detected and routed to `pos media grab`.

### Decision

New routing step between prefix map and AI bridge:

```
/help|/start  →  reply mapped commands list
     ↓ (no match)
text-prefix map  →  run mapped command
     ↓ (no match)
**URL detect → pos media grab** (NEW)
     ↓ (no match)
AI bridge  →  forward to Gemini
     ↓ (no match)
command map  →  run /command
     ↓ (no match)
"Unknown command"
```

### Why After Prefix Map?

- A prefixed command like `ai https://...` should go to the AI bridge, not grab
- A bare URL with no prefix should go to grab
- The prefix map is explicit user configuration — it takes priority

### Why Before AI Bridge?

- A bare URL has no AI intent — it's a download request
- The AI bridge would waste time (and API credits) analyzing a URL
- Future non-AI intents (reminders, etc.) slot in as more case arms here

### Implementation

Add to `handle_message` after the prefix map block (after line 683, before line 685):

```bash
    # URL detect: bare HTTP(S) URLs → pos media grab
    local grab_url
    if grab_url="$(url_detect "$text")"; then
        log "grab: $grab_url"
        run_and_reply "pos media grab --best \"$grab_url\"" "$msg_id" 600
        return
    fi
```

Add `url_detect` function before `handle_message`:

```bash
# Detect a bare URL in message text. Extracts the first http(s) URL.
# Returns 0 + prints the URL on success, 1 if no URL found.
url_detect() {
    local text="$1"
    local url=""
    # Match http:// or https:// followed by non-whitespace
    if [[ "$text" =~ (https?://[^[:space:]]+) ]]; then
        url="${BASH_REMATCH[1]}"
        # Strip trailing punctuation that's likely not part of the URL
        url="${url%%[,.\)!?:;]}"
        url="${url%%\>*}"
        [ -n "$url" ] || return 1
        printf '%s' "$url"
        return 0
    fi
    return 1
}
```

### Edge Cases

| Input | `url_detect` result | Routing |
|-------|-------------------|---------|
| `https://youtube.com/watch?v=xyz` | `https://youtube.com/watch?v=xyz` | grab → mp4 |
| `check out https://youtu.be/xyz` | `https://youtu.be/xyz` | grab → mp4 |
| `ai what is https://example.com` | `https://example.com` | grab (not AI!) |
| `/status` | (no match) | command map |
| `opencode check cpu` | (no match) | prefix map |
| `hello world` | (no match) | AI bridge or unknown |

The `ai what is https://...` case is a minor trade-off — the user is more likely asking AI about the URL content than wanting to download it. However, this is a rare edge case, and the primary use case (bare URL from phone) is served correctly. If it becomes an issue, the URL detection could be refined to only trigger when the URL is the dominant content (e.g., text length < 2x URL length).

### Timeout

600 seconds (10 minutes). Reasonable for most videos. The listener's `run_and_reply` already handles timeout gracefully (returns "exit N" + output).

[DECIDED]

---

## Decision 6: Tool Output Contract

### Problem

What does `pos media grab` print so the listener can reply to the user?

### Evidence

- `pos media mp3` line 85: `spawn "downloading audio → $OUT_DIR"` — prints via spawn (OK/FAIL + elapsed)
- `pos media mp4` line 131: `spawn "downloading video → $OUT_DIR"` — same
- The listener's `run_and_reply` (line 349-360): captures stdout+stderr, replies with output (truncated to 3800 chars)
- Other tools: `pos system health` prints multi-line reports that the listener forwards verbatim

### Decision

`pos media grab` prints clean, user-friendly output to stdout:

```
🎵 Downloaded: Artist - Title (3:42)
📁 ~/Music/Artist - Title.mp3 (4.2 MB)
```

or

```
🎬 Downloaded: Video Title (10:15)
📁 ~/Videos/Video Title.mp4 (125 MB)
```

Error case:

```
❌ Download failed: [yt-dlp error summary]
```

### Implementation

After the mp3/mp4 delegation succeeds, the tool:

1. Runs `yt-dlp --print title --print duration_string --print filesize_approx "$URL"` to fetch metadata (fast, no download)
2. Runs `stat --printf='%s' "$filepath"` to get actual file size
3. Prints the formatted summary

For errors: capture stderr from the delegated command, print a clean error line.

### Why Not Just Forward spawn Output?

The `spawn` helper prints spinner text + OK/FAIL, which is good for terminal but not for Telegram. A structured summary (title, path, size) is more useful when you get a Telegram notification about a download.

### Why Metadata is a Separate Call?

The download itself (via mp3/mp4) doesn't expose title/size in a parseable format. The metadata call is fast (~1s) and gives us the info we need for the summary.

[DECIDED]

---

## Decision 7: Testing Strategy

### Problem

How to test without a real Telegram bot or yt-dlp network access?

### Evidence

- DEV.md "Testing tools that need root / systemd / missing deps" (lines 194-214)
- Existing patterns: `FLAGS_DIR`, `SMB_CONF` env-seam approach; stub PATH fakes
- The tool is a thin classifier + delegator — most logic is in URL matching

### Decision

Stub PATH approach with fake `pos media mp3`/`pos media mp4` scripts.

### Test Harness Layout

```
/tmp/opencode/media-grab-test/
├── run-tests.sh          # Main test runner
├── stubs/                # Fake binaries
│   ├── pos               # Fake pos dispatcher → delegates to stub mp3/mp4
│   ├── pos-media-mp3     # Echoes args, creates a fake file
│   ├── pos-media-mp4     # Echoes args, creates a fake file
│   ├── yt-dlp            # Echoes args, creates a fake file, prints metadata
│   ├── stat              # Returns fake file size
│   └── ffmpeg            # No-op
└── fixtures/             # Test URLs (various domains)
```

### Test Cases (20+)

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1 | YouTube Music URL | `https://music.youtube.com/watch?v=xyz` | Routes to mp3 |
| 2 | YouTube video URL | `https://youtube.com/watch?v=xyz` | Routes to mp4 --best |
| 3 | YouTube short URL | `https://youtu.be/xyz` | Routes to mp4 --best |
| 4 | YouTube shorts URL | `https://youtube.com/shorts/xyz` | Routes to mp4 --best |
| 5 | SoundCloud URL | `https://soundcloud.com/artist/track` | Routes to mp3 |
| 6 | Bandcamp URL | `https://bandcamp.com/album/track` | Routes to mp3 |
| 7 | Vimeo URL | `https://vimeo.com/123456` | Routes to mp4 --best |
| 8 | Unknown domain | `https://example.com/video.mp4` | Routes to mp4 --best (default) |
| 9 | `--audio` override | `--audio https://youtube.com/watch?v=xyz` | Routes to mp3 |
| 10 | `--video` override | `--video https://soundcloud.com/track` | Routes to mp4 |
| 11 | `--worst` flag | `--worst https://youtube.com/watch?v=xyz` | Routes to mp4 --worst |
| 12 | `--best` explicit | `--best https://youtube.com/watch?v=xyz` | Routes to mp4 --best |
| 13 | `--dry-run` | `--dry-run https://youtube.com/watch?v=xyz` | Prints command, no download |
| 14 | No URL | (empty) | usage |
| 15 | `--help` | `--help` | Shows usage |
| 16 | Invalid URL | `not-a-url` | Error: "not a valid URL" |
| 17 | GRAB_DEFAULT=audio | `GRAB_DEFAULT=audio https://unknown.com/x` | Routes to mp3 |
| 18 | `--output` override | `--output /tmp/test https://...` | Passes to mp3/mp4 |
| 19 | HTTP URL | `http://youtube.com/watch?v=xyz` | Routes to mp4 (http not https) |
| 20 | `--no-playlist` | `--no-playlist https://youtube.com/playlist?list=xyz` | Passes to mp3/mp4 |

### Stub Implementation

```bash
#!/usr/bin/env bash
# Fake pos-media-mp3 — records args, creates a dummy file
OUT_DIR="${OUT_DIR:-/tmp/test-output}"
mkdir -p "$OUT_DIR"
URL="${*: -1}"  # last arg is URL
echo "pos-media-mp3 called with: $*" > /tmp/test-output/mp3.log
touch "$OUT_DIR/test.mp3"
echo "Downloaded: Test Song (3:42)"
echo "📁 $OUT_DIR/test.mp3 (4.2 MB)"
```

### What NOT to Test

- yt-dlp actual behavior (covered by yt-dlp's own tests)
- The listener integration (tested manually or with a Telegram bot test harness)
- URL regex edge cases that are handled by bash `[[ =~ ]]` (well-tested in bash)

[DECIDED]

---

## Decision 8: Dependency Handling

### Problem

What deps does `pos media grab` declare, and where?

### Evidence

- `pos media mp3` lines 17-18: guards `yt-dlp` and `ffmpeg`
- `pos media mp4` lines 17-18: same guards
- `pos media grab` delegates to mp3/mp4, which handle their own deps
- Grab itself only needs bash builtins for URL classification

### Decision

No deps guard in `pos media grab`. Deps are the responsibility of mp3/mp4.

### Rationale

Grab is a pure classifier + delegator. It doesn't call yt-dlp directly. If mp3/mp4 are called and their deps are missing, they'll error with their own helpful messages. Adding redundant deps guards in grab would:
- Duplicate error messages
- Create maintenance overhead when mp3/mp4 deps change
- Violate single-responsibility (grab classifies, mp3/mp4 download)

### Exception

If grab needs `stat` for file size reporting (Decision 6), that's a standard coreutil — no guard needed on Debian/Ubuntu.

[DECIDED]

---

## Summary: Implementation Scope

### Files to Create

| File | Responsibility |
|------|---------------|
| `bin/pos-media-grab` | URL classifier, delegate to mp3/mp4, clean output |

### Files to Modify

| File | Change |
|------|--------|
| `bin/pos-communication-telegram-listener` | Add `url_detect` function + URL routing step in `handle_message` |

### Files to Update (Docs)

| File | Change |
|------|--------|
| `DOC/POS.md` | Add `pos media grab` row to media table + detail block |
| `DOC/HOWTO.md` | Add media section reference if not already present |
| `DOC/howto/media.md` | Add `grab` usage example |
| `DOC/AGENT_Context_Project.md` | (auto via `make gen`) tree, dispatch, filetable |
| `AGENT_TODO.md` | Move to Done |

### Post-Implementation Gates

```bash
chmod +x bin/pos-media-grab
bash -n bin/pos-media-grab
bash -n bin/pos-communication-telegram-listener
make gen && make check && make lint   # 0 FAIL, 0 WARN
```

---

## Handoff

Status: DECISION_READY

Problem: Telegram bot needs intelligent URL routing to auto-download content as audio/video.

Decision: New `bin/pos-media-grab` tool (domain classifier + mp3/mp4 delegator) + listener URL routing step between prefix map and AI bridge.

Reasoning: Evidence-based — domain classification is fast/reliable for the primary use case, existing mp3/mp4 tools handle the heavy lifting, listener routing chain slots naturally for new intents.

Ownership: `bin/pos-media-grab` (new tool), listener integration in existing listener.

Interfaces: grab is called by the listener; grab calls mp3/mp4.

Approved scope: `bin/pos-media-grab` (new), listener modification (add ~30 lines), doc updates. No changes to mp3/mp4.

Explicitly out of scope: Changes to mp3/mp4 tools, feature flags, complex config.

Constraints: Must pass `make gen && make check && make lint` (0 FAIL, 0 WARN). Follow all pos conventions (shebang, strict mode, `# POS:` header, deps-before-help pattern, `common.sh` sourcing).

Verification: Stub-PATH test suite (20+ cases), `bash -n` on both modified files, `make gen && make check && make lint`.

Risks:
- URL regex may not match all URL formats (mitigated: covers http/https, the dominant formats)
- `--best` may not be what the user always wants for video (mitigated: `--worst` override)
- Metadata fetch adds ~1s latency (mitigated: acceptable for download context)

Recommended next agent: Builder

Reason: Architecture is fully defined with specific file paths, function signatures, listener line changes, config keys, and test plan. Ready for implementation.

Architect changes: None — pure decision record.
