# Reviewer Report — `pos media grab` Implementation

**Date:** 2026-09-04
**Status:** ACCEPT_WITH_NOTES

---

## TL;DR

- **Status:** ACCEPT_WITH_NOTES
- **Verdict:** Implementation faithfully matches the approved architecture. One minor cosmetic defect, two unverified gates (sandbox prevented execution), one missing doc entry (howto/media.md).
- **Findings:** 0 BLOCKING, 0 REQUIRED, 2 SUGGESTED, 1 NOTE
- **Gates:** UNVERIFIED (sandbox restriction — see details below)

---

## Checklist Results

### Code Quality

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 1 | `set -euo pipefail` present | ✅ PASS | `bin/pos-media-grab:2` — `set -euo pipefail` |
| 2 | `# POS:` header correct format | ✅ PASS | `bin/pos-media-grab:3` — `# POS: media grab — Auto-download URL as audio or video (classify + route)` |
| 3 | `# POS_FLAGS:` header correct | ✅ PASS | `bin/pos-media-grab:4` — declares all 8 flags matching implemented case arms |
| 4 | `# POS_CONFIG:` header correct | ✅ PASS | `bin/pos-media-grab:5` — `grab \| grab.env \| GRAB_DEFAULT=:...` matches Architect Decision 3 exactly |
| 5 | Sources `lib/common.sh` via standard fallback | ✅ PASS | `bin/pos-media-grab:7` — standard `$(dirname "$0")/../lib/common.sh` fallback chain, identical to `pos-media-mp3:6` |
| 6 | No deps guards (Decision 8) | ✅ PASS | No `command -v` guard present; deps are delegated to mp3/mp4 per spec |
| 7 | `classify_url()` matches Decision 2 table | ✅ PASS | `bin/pos-media-grab:28-39` — exact match: `music.youtube.com→audio`, `soundcloud.com→audio`, `bandcamp.com→audio`, `youtube.com/youtu.be→video`, `vimeo.com→video`, `twitch.tv→video`, `*→$GRAB_DEFAULT`. Priority order correct (music.youtube.com matches before youtube.com). |
| 8 | `usage()` present | ✅ PASS | `bin/pos-media-grab:41-67` — full help with options and examples |
| 9 | Arg parsing handles all declared flags | ✅ PASS | `bin/pos-media-grab:78-97` — all 8 flags + `-h\|--help` + catch-all for unknown options |
| 10 | `--audio` / `--video` mutual exclusion | ✅ PASS | `bin/pos-media-grab:108-109` — `FORCE_AUDIO -eq 1 && FORCE_VIDEO -eq 1` → error |
| 11 | `--best` / `--worst` mutual exclusion | ✅ PASS | `bin/pos-media-grab:110-111` — `BEST -eq 1 && WORST -eq 1` → error |
| 12 | Single positional arg (URL) enforced | ✅ PASS | `bin/pos-media-grab:94-95` — first non-flag sets URL, second triggers error |
| 13 | Non-HTTP URLs rejected | ✅ PASS | `bin/pos-media-grab:102-105` — case match on `http://*\|https://*`, else → error |
| 14 | `--dry-run` works without downloading | ✅ PASS | `bin/pos-media-grab:138-141` — prints command and exits before delegation |
| 15 | Output format matches spec (emoji, title, duration, path, size) | ✅ PASS | `bin/pos-media-grab:208-227` — `🎵/🎬 Downloaded: $title ($duration)` + `📁 $rel_path ($size_human)` |
| 16 | Error handling: stderr captured, clean message | ✅ PASS | `bin/pos-media-grab:144-157` — `2>&1` capture, grep for error summary, `err` with clean message |

### Listener Integration

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 17 | `url_detect` function exists | ✅ PASS | `bin/pos-communication-telegram-listener:660-672` — matches Architect spec exactly |
| 18 | URL routing step position (after prefix map, before AI bridge) | ✅ PASS | `bin/pos-communication-telegram-listener:700-706` — between prefix map block (lines 688-699) and AI bridge (lines 707+) |
| 19 | Timeout is 600s | ✅ PASS | `bin/pos-communication-telegram-listener:704` — `run_and_reply ... "$msg_id" 600` |
| 20 | `run_and_reply` called with correct args | ✅ PASS | `bin/pos-communication-telegram-listener:704` — `run_and_reply "pos media grab --best \"$grab_url\"" "$msg_id" 600` |

### Convention Compliance

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 21 | `bash -n` on `pos-media-grab` | ⚠️ UNVERIFIED | Sandbox denied execution; Builder reports ✅ |
| 22 | `bash -n` on `pos-communication-telegram-listener` | ⚠️ UNVERIFIED | Sandbox denied execution; Builder reports ✅ |
| 23 | `make gen && make check` passes | ⚠️ UNVERIFIED | Sandbox denied execution; Builder reports ✅. Code review of gen output: `DOC/AGENT_Context_Project.md` tree/dispatch/filetable entries present (lines 83, 297, 626), `completions/pos.bash` has `media-grab` flags (line 12) and `grab` config scope (line 50). |
| 24 | `make lint` passes (0 FAIL, 0 WARN) | ⚠️ UNVERIFIED | Sandbox denied execution; Builder reports ✅ |
| 25 | Tool is executable (chmod 100755) | ⚠️ UNVERIFIED | Sandbox denied `stat`; Builder reports ✅ |
| 26 | POS.md has grab row | ✅ PASS | `DOC/POS.md:240` — `pos media grab <url>` row in media table with full configuration column |

### Security

| # | Check | Result | Evidence |
|---|-------|--------|----------|
| 27 | No command injection via URL (proper quoting) | ✅ PASS | Listener: `"$grab_url"` inside double-quoted cmdline string → URL is properly quoted for `bash -c`. Tool: `"${DELEGATE_ARGS[@]}" "$URL"` → proper array expansion. |
| 28 | No path traversal risks | ✅ PASS | No user-controlled path manipulation; output dirs are `$HOME/Music` or `$HOME/Videos` with optional `--output` override. `find` uses `-maxdepth 1` preventing traversal. |
| 29 | Config file permissions | ✅ PASS | Config file at `~/.config/linux_post_install/grab.env` — file is only read (line 11-23), never written by this tool. Existing project convention for `.env` files is `chmod 600` at write time. |

### Architect Compliance

| # | Decision | Result | Evidence |
|---|----------|--------|----------|
| 30 | D1: `bin/pos-media-grab` as standard tool | ✅ PASS | File created at `bin/pos-media-grab`, not `features/` |
| 31 | D2: Classification logic matches table | ✅ PASS | `classify_url()` at lines 28-39 — exact match (see #7 above) |
| 32 | D3: Config scope `grab` with `GRAB_DEFAULT` | ✅ PASS | `POS_CONFIG` header at line 5, `load_grab_config()` at lines 10-23, called at line 25 |
| 33 | D4: No INTERACTIVE_CMDS change; `--best` default for mp4 | ✅ PASS | `pos` INTERACTIVE_CMDS (line 269) does not include `media-grab`. mp4 route adds `--best` by default (line 133) |
| 34 | D5: 600s timeout in listener | ✅ PASS | `run_and_reply ... 600` at line 704 |
| 35 | D6: Clean output contract (emoji, title, duration, path, size) | ✅ PASS | Lines 198-227 — matches spec format exactly |
| 36 | D7: Stub-based test harness | ✅ PASS (per Builder) | Builder reports 28 cases / 70 assertions / 0 failed at `/tmp/opencode/media-grab-test/` |
| 37 | D8: No deps guards in grab | ✅ PASS | No `command -v` guards present; delegates to mp3/mp4 |

---

## Findings

### Finding 1: Trailing "1" in error messages

**Severity:** SUGGESTED
**Certainty:** FACT

**Evidence:** `bin/pos-media-grab` calls `err` with a trailing `1` argument in 6 places (lines 86, 90, 93, 95, 104, 109, 111, 156). The `err()` function from `lib/common.sh` is defined as:
```bash
err() { echo "${RED}ERROR:${RESET} $*" >&2; exit 1; }
```
Since `$*` joins all arguments, the trailing `1` becomes part of the visible error message. For example, line 95:
```bash
err "pos media grab: Unexpected argument: $1" 1
```
Would print: `ERROR: pos media grab: Unexpected argument: foo 1`

**Relevant files/lines:** `bin/pos-media-grab:86,90,93,95,104,109,111,156`
**Approved scope reference:** Architect Decision 8 (conventions) — follow established patterns.
**Why it matters:** Every other tool in the codebase calls `err "message"` without a trailing exit code (e.g., `pos-media-mp3:52,57,61,63`). The `1` is redundant (exit code is hardcoded to 1) and pollutes the user-facing error output.

---

### Finding 2: `howto/media.md` not updated with grab section

**Severity:** SUGGESTED
**Certainty:** FACT

**Evidence:** `DOC/howto/media.md` line 5 lists tools as `mp3`, `mp4`, `sync`, `ytsync` — `grab` is missing from this list. The Architect scope explicitly listed `DOC/howto/media.md — Add grab usage example` as a file to update. The Builder did not mention updating this file. The `make lint` gate apparently does not check howto coverage (it checks POS.md), so this passed silently.

**Relevant files/lines:** `DOC/howto/media.md:5,7-12`
**Approved scope reference:** Architect "Files to Update (Docs)" table: `DOC/howto/media.md — Add grab usage example`
**Why it matters:** Users consulting the how-to guide won't find `pos media grab` documented there. Minor doc completeness gap.

---

### Finding 3: Gates could not be independently verified

**Severity:** NOTE
**Certainty:** UNVERIFIED

**Evidence:** The sandbox restricted bash execution to only git/grep/sort/wc/head/tail commands. I could not independently run `bash -n`, `make gen`, `make check`, `make lint`, the test suite, or `stat` to verify file permissions. Builder reports all green; code inspection is consistent with this (generated files appear correct in `DOC/AGENT_Context_Project.md` and `completions/pos.bash`).

**Relevant files/lines:** N/A
**Approved scope reference:** Architect "Post-Implementation Gates"
**Why it matters:** Independent verification is a core reviewer responsibility. The Orchestrator should run these gates before final acceptance.

---

### Finding 4: `url_detect` trades off against `ai`-prefixed text with URLs

**Severity:** NOTE
**Certainty:** FACT (known Architect design trade-off)

**Evidence:** `bin/pos-communication-telegram-listener:700-706` — URL detection runs before the AI bridge (lines 707+). A message like `ai what is https://example.com` will be routed to `pos media grab` instead of the AI bridge. The Architect explicitly documented this trade-off in Decision 5: "This is a minor trade-off — the user is more likely asking AI about the URL content than wanting to download it. However, this is a rare edge case."

**Relevant files/lines:** `bin/pos-communication-telegram-listener:700-706`
**Approved scope reference:** Architect Decision 5, Edge Cases table
**Why it matters:** No action needed — this is an acknowledged design decision, not a Builder deviation.

---

## Verification Verified

- **classify_url() matches Decision 2 exactly** — FACT (code comparison)
- **url_detect() matches Architect spec exactly** — FACT (character-by-character comparison of `bin/pos-communication-telegram-listener:660-672` vs Architect Decision 5 pseudocode)
- **URL routing step is between prefix map and AI bridge** — FACT (line positions confirmed: prefix map ends ~699, URL detect 700-706, AI bridge starts ~707)
- **600s timeout** — FACT (line 704)
- **POS.md row present and correct** — FACT (`DOC/POS.md:240`)
- **Config scope in completions** — FACT (`completions/pos.bash:50` has `grab`)
- **Flags in completions** — FACT (`completions/pos.bash:12` has `media-grab` flags)
- **AGENT_Context_Project.md updated** — FACT (tree: line 83, dispatch: line 297, filetable: line 626)
- **AGENT_TODO.md updated** — FACT (line 45, dated 2026-09-04)
- **No INTERACTIVE_CMDS change** — FACT (line 269 does not include `media-grab`)

## Verification Unverified

- `bash -n` syntax check on both files — UNVERIFIED (sandbox)
- `make gen && make check` — UNVERIFIED (sandbox)
- `make lint` — UNVERIFIED (sandbox)
- Test suite (`/tmp/opencode/media-grab-test/run-tests.sh`) — UNVERIFIED (sandbox)
- File permissions (`chmod 100755`) — UNVERIFIED (sandbox)
- `url_detect` edge case behavior — UNVERIFIED (would require runtime execution)

## Scope Compliance

**In-scope confirmed:**
- `bin/pos-media-grab` — new tool ✅
- `bin/pos-communication-telegram-listener` — `url_detect` + routing step ✅
- `DOC/POS.md` — media table row ✅
- `DOC/AGENT_Context_Project.md` — regenerated via make gen ✅
- `completions/pos.bash` — regenerated via make gen ✅
- `AGENT_TODO.md` — moved to Done ✅

**Out-of-scope changes found:** None.

**Missing from Architect scope:**
- `DOC/howto/media.md` — grab section not added (Finding 2)

## Remaining Uncertainty

1. All runtime gates (bash -n, make gen/check/lint, test suite) are unverified due to sandbox restrictions. Orchestrator should run them before final close.
2. The `find`-based file-location heuristic (lines 192-196) could pick a stale file in multi-download scenarios. This is an Architect design decision (Decision 6), not a Builder deviation.

## Deviations from Architect Design

| Area | Architect spec | Implementation | Assessment |
|------|---------------|----------------|------------|
| `err` call pattern | Not specified (implicit — follow conventions) | `err "msg" 1` with trailing exit code | Minor convention violation — all other tools use `err "msg"` without exit code. Cosmetic only. |
| POS.md row | "Add `pos media grab` row to media table + detail block" | Added row to media table | ✅ Matches — Builder correctly identified this as lint-required |
| howto/media.md | "Add `grab` usage example" | Not updated | Gap — listed in Architect scope but not implemented |

## Recommended next agent

**Orchestrator**

Reason: Implementation is complete and architecturally faithful. One SUGGESTED fix (trailing "1" in err calls) could be handed to Builder, and the howto gap is a doc update. The remaining uncertainty is gate verification — the Orchestrator should run `bash -n`, `make gen && make check && make lint`, and the test suite to close the verification gap before final acceptance.

## Changes made by Reviewer

None — read-only review.
