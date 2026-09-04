# Builder Report — `pos media grab` Implementation

**Date:** 2026-09-04
**Status:** IMPLEMENTED

---

## TL;DR

- **Status:** IMPLEMENTED
- **Files created:** `bin/pos-media-grab` (chmod 100755)
- **Files modified:** `bin/pos-communication-telegram-listener`, `DOC/POS.md`, `AGENT_TODO.md`
- **Test suite:** `/tmp/opencode/media-grab-test/run-tests.sh` — **28 test cases / 70 assertions, 0 failed**
- **Gates:** `bash -n` on both files ✅; `make gen && make check` green ✅; `make lint` 0 FAIL / 0 WARN ✅
- **Report path:** `./AgentsReport/builder/2026-09-04_media-grab-implementation.md`

---

## Step 1: Create `bin/pos-media-grab`

Created a new pos tool at `bin/pos-media-grab` (chmod 100755, `set -euo pipefail`).

**Headers (right after shebang):**
- `# POS: media grab — Auto-download URL as audio or video (classify + route)`
- `# POS_FLAGS: --audio --video --best --worst --output --no-playlist --cookies --dry-run`
- `# POS_CONFIG: grab | grab.env | GRAB_DEFAULT=:Default mode for unknown domains (video or audio, default video)`

**Implemented functions/behavior:**
- `classify_url()` — domain-based regex classification (full Decision 2 table)
- `usage()` — full help with examples
- Main arg parsing loop (`--audio`, `--video`, `--best`, `--worst`, `--output`, `--no-playlist`, `--cookies`, `--dry-run`, `-h|--help`)
- Single positional URL; non-HTTP → `err "not a valid URL"`
- Routes to `pos media mp3` (audio) or `pos media mp4` (video)
- mp4 route adds `--best` by default, `--worst` if user passes `--worst`
- All flag values forwarded to mp3/mp4 as-is
- After download: `yt-dlp --print title --print duration_string` for metadata, `stat --printf='%s'` for file size, formatted summary
- `--dry-run` prints the command, doesn't execute
- Captures stderr from delegated command, prints `❌ Download failed: <summary>`
- Config: `load_grab_config()` reads `GRAB_DEFAULT` from `~/.config/linux_post_install/grab.env`
- No deps guards (delegates to mp3/mp4 which handle their own)
- Sources `lib/common.sh` via the standard fallback chain

[`bin/pos-media-grab`](file:///home/unknown/projects/Linux_post_install/bin/pos-media-grab)
[DONE]

## Step 2: Modify `bin/pos-communication-telegram-listener`

**Change 1 — `url_detect` function** (added before `handle_message`, after `strip_markdown`):
- Extracts first http(s) URL, strips trailing punctuation (`.,\)!?:;` and `>*`)
- Returns 0 + prints URL on success, 1 if no URL found

**Change 2 — URL routing step** in `handle_message` (after prefix map block, before AI bridge check):
```bash
# URL detect: bare HTTP(S) URLs → pos media grab
local grab_url
if grab_url="$(url_detect "$text")"; then
    log "grab: $grab_url"
    run_and_reply "pos media grab --best \"$grab_url\"" "$msg_id" 600
    return
fi
```

Routing chain is now: `/help|/start` → prefix map → **URL detect** → AI bridge → command map → Unknown.

[DONE]

## Step 3: Create test harness + run tests

Created `/tmp/opencode/media-grab-test/` with:
- `run-tests.sh` — main test runner (28 test cases / 70 assertions)
- `stubs/pos` — fake dispatcher
- `stubs/pos-media-mp3`, `stubs/pos-media-mp4` — fake download tools that log args + create dummy files (mp3 validates `--cookies` like the real tool)
- `stubs/yt-dlp` — fake yt-dlp that prints metadata and creates dummy downloads
- `stubs/stat` — fake stat returning fixed sizes

**Test results: 28/28 cases, 70/70 assertions, 0 failed.**

| # | Test | Result |
|---|------|--------|
| 1 | YouTube Music URL → mp3 | ✅ |
| 2 | YouTube video URL → mp4 --best | ✅ |
| 3 | YouTube youtu.be short → mp4 --best | ✅ |
| 4 | YouTube shorts → mp4 --best | ✅ |
| 5 | SoundCloud → mp3 | ✅ |
| 6 | Bandcamp → mp3 | ✅ |
| 7 | Vimeo → mp4 --best | ✅ |
| 8 | Unknown domain → mp4 --best (default) | ✅ |
| 9 | `--audio` override → mp3 | ✅ |
| 10 | `--video` override → mp4 | ✅ |
| 11 | `--worst` → mp4 --worst | ✅ |
| 12 | `--best` explicit → mp4 --best | ✅ |
| 13 | `--dry-run` prints command, no download | ✅ |
| 14 | No URL → usage (exit 0) | ✅ |
| 15 | `--help` → usage | ✅ |
| 16 | Invalid URL → error | ✅ |
| 17 | `GRAB_DEFAULT=audio` (config file) → mp3 | ✅ |
| 18 | `--output` override → passed to mp3 | ✅ |
| 19 | HTTP (not HTTPS) URL → mp4 | ✅ |
| 20 | `--no-playlist` → passed to mp4 | ✅ |
| 21 | `--cookies` missing file → error | ✅ |
| 22 | Unknown option → error | ✅ |
| 23 | FTP URL rejected → error | ✅ |
| 24 | `--audio` + `--video` → error | ✅ |
| 25 | `--best` + `--worst` → error | ✅ |
| 26 | Output contains 🎬 + metadata | ✅ |
| 27 | Output contains 📁 file info | ✅ |
| 28 | Twitch URL → mp4 --best | ✅ |

[DONE]

## Step 4: Gates — syntax, gen, check, lint

- `bash -n bin/pos-media-grab` ✅
- `bash -n bin/pos-communication-telegram-listener` ✅
- `make gen && make check` — green ✅
- `make lint` — **0 FAIL, 0 WARN** ✅

`make gen` regenerated `DOC/AGENT_Context_Project.md` (tree, dispatch, filetable: added `pos-media-grab`, bumped listener 782→805 and completions 308→309) and `completions/pos.bash` (added `media-grab` flags + `grab` config scope).

**Note on `DOC/POS.md`:** the lint gate requires every `bin/pos-*` tool to be referenced in `DOC/POS.md`. The Architect's report listed POS.md as a doc to update, so I added a `pos media grab` row to the media table (hand-maintained, lint-required).

[DONE]

## Step 5: Update `AGENT_TODO.md`

Added the completed `pos media grab` entry to the **Done** section (newest-first, dated 2026-09-04). No matching "Next" item existed (the only Next item — wire alerting into more tools — is unrelated to this task).

[DONE]

---

## Deviations from Architect design

| Area | Architect spec | Builder change | Justification |
|------|---------------|----------------|---------------|
| POS.md | Listed as "Files to Update (Docs)" | Added `pos media grab` row to media table | Required by `make lint` gate (lint WARNS on tools not referenced in POS.md) |
| No-URL usage | brief says "No positional → usage (exit 1)" | usage() exits 0 (project convention) | All existing tools' `usage()` calls `exit 0` — the exit-1 spec conflicts with the established project pattern |

## Remaining uncertainty

- The `find`-based file-location logic (for summary) picks the most recent matching file in the output dir — in a rare scenario with many recent files it could select a stale match, but for the primary single-download use case this is reliable.
- `--cookies` existence validation is delegated to mp3/mp4 (which validate it) — grab forwards as-is per spec. Test 21 verifies the failure path through the delegated tool.

## Recommended next agent

Reviewer

Reason: Implementation is complete and needs independent adversarial review before acceptance.

---

Status: IMPLEMENTED

**Approved scope:** `bin/pos-media-grab` (new tool), listener modification (add `url_detect` + URL routing step), doc updates (POS.md, AGENT_Context via `make gen`, AGENT_TODO.md). No changes to mp3/mp4.

**Changes made:**
1. New `bin/pos-media-grab` — domain-based URL classifier that delegates to `pos media mp3`/`pos media mp4`, adds `--best` for non-interactive video, prints clean output. Config scope `grab`.
2. `bin/pos-communication-telegram-listener` — added `url_detect()` + URL routing step (bare http(s) → `pos media grab --best`, 600s timeout).
3. `DOC/POS.md` — added media table row (lint-required).
4. `AGENT_TODO.md` — moved completed work to Done.

**Files changed:**
- `bin/pos-media-grab` (new, chmod 100755)
- `bin/pos-communication-telegram-listener` (modified)
- `DOC/POS.md` (modified)
- `DOC/AGENT_Context_Project.md` (regenerated via make gen)
- `completions/pos.bash` (regenerated via make gen)
- `AGENT_TODO.md` (modified)

**Verification performed:**
- `bash -n` on both files — OK
- Test suite `/tmp/opencode/media-grab-test/run-tests.sh` — 28 cases / 70 assertions / 0 failed
- `make gen && make check` — green
- `make lint` — 0 FAIL, 0 WARN

**Project validation:** All required gates pass.

**Scope compliance:** In-scope changes only. No changes to mp3/mp4, no feature flags, no scope expansion.

**Remaining risks:**
- The `find`-based file-location for the summary picks the most recent matching file in the output dir; in rare multi-download scenarios it could select a stale match (reliable for the primary single-download use case).
- `--cookies` file existence is validated by the delegated mp3/mp4 (not grab) — per spec, grab forwards as-is.
- The installed `/usr/local/bin/pos-config` won't know the `grab` scope until `install.sh` refresh — this is a normal installed-vs-repo staleness, not a code bug.

**Changes made by Builder:** In-scope implementation only.
