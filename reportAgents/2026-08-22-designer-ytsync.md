# Designer Report — `pos media ytsync` UX Specification

Date: 2026-08-22 · Agent: Designer · Status: **DESIGN_PROVISIONAL** (spec complete; 5 assumptions flagged for Architect reconciliation)
Spec-only task — no code or docs modified outside this report. Dirty share-suite work untouched.

---

## 1. Objective

Design the end-to-end terminal experience for `pos media ytsync`: interactively ask for a YouTube channel/playlist URL, then auto/incrementally download videos into `~/Videos/<channel>/<playlist-or-flat>`. Repeat runs fetch only new content. Covers flow shape, non-tty safety, naming as the user sees it, progress UX, state visibility, error handling, notifications, dry-run, and console hygiene.

Users: the repo owner and their schedulers (`pos system schedule`), on Debian/Ubuntu terminals, sometimes over SSH with 80-col windows, sometimes non-tty under systemd timers.

---

## 2. UX Decisions (each with rationale + evidence)

### D1 — Interaction flow: subcommand-first tool whose bare invocation is the interactive front door

**Decision.** CLI surface:

```
pos media ytsync                  # interactive front door (see below)
pos media ytsync add [<url>]      # register a source + first sync (prompts when url omitted)
pos media ytsync sync [<name>]    # incremental pass; no arg = all tracked channels
pos media ytsync list             # tracked channels + archive status table
pos media ytsync remove <name>    # stop tracking a source (downloaded files are KEPT)
# global flags: --dry-run, -h/--help        (# POS_SUBCMDS: add sync list remove)
```

Bare invocation behavior (tty):
- **Nothing tracked yet** → skip any menu, go straight to the URL prompt. First-run friction must be zero; this matches the stated objective ("mainly ASKS for a YouTube channel URL").
- **Channels already tracked** → lean looping menu (share-suite pattern):

```
════════════════════════════════════════════
  ytSync — YouTube channel sync
════════════════════════════════════════════
  1) Sync all channels now   (3 tracked · last run 2026-08-21 09:14)
  2) Add a channel or playlist
  3) List channels
  4) Remove a channel
  0) Exit
--------------------------------------------
Choose:
```

After **any** completed interactive action → loop back to this menu (or re-offer the add prompt in the empty-state path). Exit via `0`/`q`/`Q`/EOF. After a **subcommand** action (`add <url>`, `sync`) → print summary and exit 0 (scriptable, no loops).

Add-flow prompt sequence (interactive):
1. Prompt for URL (exact copy in §3).
2. Validate + resolve: probe source metadata; show what was resolved *before* downloading:
   ```
   Resolved : Linus Tech Tips (channel · 2140 videos)
   Library  : ~/Videos/Linus Tech Tips/
             └── flat videos: <title>.<ext>
   Start download? [Y/n]
   ```
   Invalid input re-prompts in place (max 3 attempts, then cancel back to menu) — same validation-feedback discipline as mp4's format-id check (`bin/pos-media-mp4:104-116`).
3. Download with progress UX (D4). 4. Summary line (D5). 5. Optional notify (D7). 6. Back to menu.

`add <url>` with an explicit URL skips the confirm (non-interactive contract); it prints the resolved mapping line and proceeds.

**Single-verb vs menu/subcommand — comparison and verdict.**

| | Single verb (`ytsync [url]`, always asks) | Menu/subcommand (recommended) |
|---|---|---|
| First-run ask-for-URL | ✅ literal match to objective | ✅ preserved (empty state bypasses menu) |
| Repeat runs (dominant case) | ❌ must re-paste URL every time | ✅ `sync` = zero input |
| Scheduler/non-tty | ❌ needs URL embedded in job; bare call hangs/quits ambiguously | ✅ explicit prompt-free verbs |
| State visibility (list/remove) | ❌ bolted-on flags feel tacked-on | ✅ first-class verbs |
| Repo precedent | mp3/mp4 (one-shot downloads — different job) | share suite menus + vbox confirms |

Evidence: share suite's looping menu + EOF-safe guard is the repo's proven interactive-layer pattern (`lib/share-lib.sh:38-44` guard, `:46-80` menu loop); vbox's post-action confirm shows light confirms after heavy ops are idiomatic (`DOC/AGENT_Context_Project.md:315`). A pure single-verb tool optimizes the *rare* action (adding) at the cost of the *common* one (incremental sync). Verdict: **menu/subcommand hybrid** — the menu only appears once there is something to manage.

### D2 — Non-tty / EOF safety matrix (scheduler-safe by construction)

| Situation | Behavior |
|---|---|
| Bare/menu/prompt entry, stdin not a tty | One-line stderr hint + exit 0 (nothing attempted ≠ failure): `[!] ytSync needs a terminal for its prompt — use 'pos media ytsync sync' for unattended runs.` — verbatim pattern of `share_menu_guard` (`lib/share-lib.sh:38-44`) |
| EOF (Ctrl-D) at any prompt | Clean cancel of that step; partial results still summarized; exit 0. Precedent: menu/picker EOF handling (`lib/share-lib.sh:65-67`, `:125-127`, `share_ask_value :154-156`) |
| Empty input at URL prompt | Re-ask (max 3), then treat as cancel → back to menu / exit 0 |
| `add <url>` / `sync` / `list` / `remove` verbs | **Never prompt.** Safe under cron/systemd timers and under the dispatcher's tee pipe |
| Any hang risk | None: no read without a preceding tty guard |

Exit codes: `0` = run completed (including "0 new videos", clean cancels, non-tty guard); `1` = fatal only — missing dependency, invalid explicit URL, or ≥1 channel-level failure during an explicitly requested sync (so scheduler notify policies can react). Per-video failures never flip the exit code (routine on YouTube).

**Prompt transport — flagged ASSUMPTION A1 (Architect).** Recommended: read prompts from `/dev/tty` instead of plain stdin. Then the script does **not** need `INTERACTIVE_CMDS` registration, so *every* invocation keeps full `tee` logging (`bin/pos:285`) — for an hours-long downloader, the log file becomes the audit trail of what was fetched. DEV.md's lint gate excludes `/dev/tty` reads from the stdin check (`DOC/DEV.md:329`), so this passes conventions. Fallback if Architect rejects it: register `media-ytsync` in `INTERACTIVE_CMDS` (`bin/pos:261`) and accept that the whole script loses output logging (all-or-nothing per script, `DOC/DEV.md:58`) — then D5's history line becomes mandatory rather than recommended. Either way, all user-visible behavior in this spec is unchanged.

### D3 — Download tree as the user sees it

Target (user-stated): `~/Videos/<channel>/<playlist>/…` for playlists, `~/Videos/<channel>/…` flat otherwise.

- **Channel dir derivation:** resolved **once at registration** from a source-metadata probe — never per-video. Rationale: per-video templates like `%(uploader)s` scatter collaboration/cross-posted videos into other folders, silently fragmenting the library. One stable directory per tracked source is the mental model.
- **Name preference: `%(channel)s` over `%(uploader)s`.** yt-dlp defines `channel` = "Full name of the channel the video is uploaded on" and `uploader` = legacy "full name of the video uploader"; they diverge for distributed/VEVO-style content, and `channel` is the identity the user actually browsed/subscribed to. Use a fallback alternation `%(channel,uploader,uploader_id)s` (display name → uploader → handle) — mirrors the repo's own fallback precedent `%(artist,uploader)s` (`bin/pos-media-mp3:69`). The resolved name is shown at the add-confirm screen (§D1) so surprises are impossible.
- **Sanitization:** yt-dlp sanitizes filename components natively; recommend `--windows-filenames` (+ optional length cap) so the tree stays safe on USB sticks/Samba/TV playback — exact flags are the Architect's call (**A4**).
- **Playlist subdir naming:** the playlist title, resolved at registration and stored with the source. If the curator later renames the playlist on YouTube, the local dir does **not** rename mid-library (stability beats freshness); documented in help text.
- **Filename inside dirs:**
  - playlist sources: `%(playlist_index)03d - %(title)s.%(ext)s` → zero-padded numeric order = playlist order (yt-dlp docs' own example pattern). Caveat documented: inserting a video mid-playlist shifts future numbering; existing files are never renamed.
  - flat/channel sources: `%(title)s.%(ext)s` — matches both existing media tools, which deliberately drop yt-dlp's default `[id]` suffix (`bin/pos-media-mp4:125`, mp3:71).
- **Collisions/rename behavior visible to the user:**
  - already-in-archive ids → skipped silently, counted as "already present" in the summary;
  - same-title different-video under `--no-overwrites` (repo precedent `bin/pos-media-mp4:124`) → warning counted in the run summary;
  - title changes on YouTube never rename local files (archive keyed by video id) — stated plainly in help so expectations are set.
- **State files live OUTSIDE `~/Videos`** — the media tree must contain nothing but media (it gets synced to TVs/sticks). Registry + archive placement is Architect's (**A3**); the UX requirement is only: not inside `~/Videos`, discoverable via `list`.

### D4 — Long-download progress UX: per-video lines, not a spinner, not raw passthrough

**Decision:** the tool prints one LF-terminated line per video event; yt-dlp runs effectively quiet with native progress allowed only on a TTY (yt-dlp auto-simplifies when piped).

```
[+] Linus Tech Tips — 14 new of 2154
  [1/14] The new GPU tier list is here
  OK [1/14] The new GPU tier list is here (4m12s)
  [2/14] We built a PC for $100
  ...
```

Shape: `step`-style start line per video + `ok` completion line with elapsed (helpers: `lib/common.sh:37-42`, `:25`). Byte-level rate/ETA comes from yt-dlp's own progress and only when attached to a terminal — never `\r`-only sequences into logs.

**Rejected alternatives, with evidence:**
- `spawn()` around the whole batch — wrong tool: spawn captures stdout+stderr to temp files until completion (`lib/common.sh:88-90`) and dumps stderr only on FAIL (`:109-112`). For a 500-video initial backfill that is hours of silence behind a braille spinner. Feedback opacity fails the primary long-run use case.
- Raw yt-dlp passthrough — `\r` progress spam pollutes the tee'd log files and drowns the per-item heartbeat.

Rationale: the unit of progress the user cares about is *videos*, matching the repo's per-file feedback precedent (`bin/pos-media-sync:152` echoes `+ rel` per copied file). `spawn` remains right for short pre-steps only (the metadata probe, ≤ seconds — its designed habitat, cf. mp3/mp4 usage `bin/pos-media-mp4:131`). Overall duration via `timer_start/timer_stop` in the summary.

### D5 — State visibility: `list` view + end-of-run summary

`pos media ytsync list` (works non-tty):

```
Tracked sources (2)

  NAME              TYPE      VIDEOS  LAST SYNC     DESTINATION
  Linus Tech Tips   channel     2140  2026-08-21    ~/Videos/Linus Tech Tips
  CS50 lectures     playlist     132  2026-08-19    ~/Videos/David Malan/CS50 lectures
```
plus a footer line showing where state lives (registry/archive paths — content owned by Architect, **A3**).

End-of-run summary mirrors the established grammar of `pos media sync` (`bin/pos-media-sync:159-163`):

```
OK Sync complete: 14 new, 2126 already present, 0 failed → /home/u/Videos/Linus Tech Tips
```
Multi-channel `sync` adds a roll-up block listing per-channel counts, then one total line. Every run also appends one history line (`date · name · N new · M skipped · K failed`) for scheduled-run visibility — recommended in v1, **mandatory** if A1 resolves to INTERACTIVE_CMDS registration (only trace left).

### D6 — Error & edge UX: warn-and-continue, with precise vocabulary

Policy: a batch is never aborted by one bad item; failures are *counted*, *named*, and *summarized*.

| Case | What the user sees | Run effect |
|---|---|---|
| Unreachable network at probe/download | `[!] could not reach YouTube — check connection` | channel marked failed; continue others; rc 1 if all requested failed |
| Source not found / private / deleted | `ERROR: source not found or private: <url>` at add-time (re-prompt ≤3) | add aborts cleanly |
| Members-only/age-gated videos inside a channel | `[!] 3 videos require sign-in — skipped` in summary | warn-and-continue (cookies support = open question, see §8) |
| Single unavailable/deleted video mid-batch | one `[!] unavailable: <title>` line | continue; counted as failed |
| Same-title collision | `[!] exists, kept: <file>` | continue; counted separately |
| Disk full (ENOSPC) | prominent `[!]` + that channel stops | other channels continue |
| Everything requested failed | final `ERROR:` line | exit 1 (scheduler-visible) |

Optional nice-to-have: a disk-space preflight estimate at add-confirm, mirroring `pos media sync`'s fail-early check (`bin/pos-media-sync:110-132`) — mark as enhancement, not v1 blocker.

### D7 — Notifications: noteworthy-only digest via `notify_send`

Source `lib/notify.sh` opt-in; silent-fail when Telegram/Matrix unconfigured (`lib/notify.sh:24-25,72-84`) — zero-risk integration.

- **Send a digest only when something happened**: `new > 0` OR `failed > 0`. A scheduled run that finds nothing new stays silent — daily no-op runs must not spam the chat. (Contrast: `media-sync` always notifies, `bin/pos-media-sync:163`; entertainment-send sends only real content, `bin/pos-entertainment-send:74-95`. For a *scheduled* downloader, silence-on-noop is the correct default.)
- **Failure alarm** regardless of digest policy: `trap 'notify_send "⚠️ ytSync FAILED for <name>"' ERR` — verbatim pattern of `bin/pos-media-sync:74`.
- **Message shape** (plain text, Telegram-readable):

```
📺 ytSync — 3 new videos: Linus Tech Tips
• Title of video one
• Title of video two
• Title of video three
→ ~/Videos/Linus Tech Tips
```
Cap listed titles at 5, then `…and 9 more`. Failures variant uses `⚠️` prefix (established emoji convention, `bin/pos-entertainment-send:76`). No markdown in v1 (plain survives every sender; `--markdown` available later).

### D8 — Dry-run preview: plan, counts, example filenames

`--dry-run` works on `add` and `sync`. It performs the cheap metadata probe + archive diff, then prints:

```
[+] DRY RUN — nothing will be downloaded
Source   : https://youtube.com/@SomeChannel
Resolved : Some Channel (channel · 812 videos)
Library  : ~/Videos/Some Channel/
New      : 12 would be downloaded (800 already present)
  0001 - First new video title.mp4
  0002 - Second new video title.mp4
  … 10 more
DRY RUN complete — 12 new would be fetched → ~/Videos/Some Channel
```

Final line mirrors the dry-run summary grammar of `bin/pos-media-sync:160`. Note one deliberate divergence from mp3/mp4: their `--dry-run` works without deps because it only prints the command (`bin/pos-media-mp3:8-13` comment); ytsync's preview *is* the value and needs the probe, so deps guards stay active under `--dry-run`.

### D9 — Accessibility / console hygiene

- Colors **exclusively** through `lib/common.sh` variables — tput-based, auto-disabled when piped (`lib/common.sh:2-13`). No raw ANSI escapes anywhere.
- Meaning never carried by color alone: `[+]` / `[!]` / `ERROR:` / `OK` / `FAIL` prefixes carry all semantics (`lib/common.sh:22-25,105-108`) → fully readable without color, and screen-reader/braille-friendly (spinners are decorative only; all state is plain text lines).
- All prompts via `read -rp` (stderr) so stdout stays machine-parseable — the "ui_pick lesson": menus/tables on stderr, data on stdout (`bin/pos-media-mp4:82-84`, `lib/share-lib.sh:11-13`).
- No cursor games, no `clear` (scrollback preserved), rules ≤ 80 cols matching `section()` width (`lib/common.sh:31`).

---

## 3. Prompt/message copy proposals (exact strings)

**usage() block**

```text
Usage: pos media ytsync [command] [args]

Incrementally download YouTube channels/playlists into ~/Videos.
First run asks for a channel URL; repeat runs fetch only new videos.

Commands:
  add [url]         Register a source and download it (asks for URL if omitted)
  sync [name]       Incremental sync of tracked sources (all, if no name given)
  list              Show tracked sources and their status
  remove <name>     Stop tracking a source (keeps downloaded files)

Options:
  --dry-run         Show what would be downloaded, fetch nothing
  -h, --help        This help

Layout:
  Videos/<channel>/<playlist>/<NNN> - <title>.<ext>   (playlist sources)
  Videos/<channel>/<title>.<ext>                      (channel/video sources)

Notes:
  Existing files are never overwritten; renamed/retitled videos keep their
  local filename. Unattended/scheduled use: 'pos media ytsync sync'.

Examples:
  pos media ytsync                                  # interactive
  pos media ytsync add https://youtube.com/@SomeChannel
  pos media ytsync sync                             # cron/timer entry point
  pos media ytsync sync --dry-run                   # preview only
  pos media ytsync list
```

**Prompts and confirmations**

| Context | Exact string |
|---|---|
| URL ask | `Channel or playlist URL: ` |
| Re-prompt after invalid input | `Try again (2 of 3), or press Enter to cancel: ` |
| Add confirm | `Start download? [Y/n]` |
| Menu remove pick | `Remove which channel? [1-N], 0=cancel ` |
| Remove confirm | `Stop tracking '<name>'? Files stay in ~/Videos. [y/N]: ` |

**Errors and warnings**

| Context | Exact string |
|---|---|
| Deps guard | `yt-dlp not found — install it with: sudo apt install yt-dlp` (matches `bin/pos-media-mp4:17`; see note on accuracy in §8) |
| Bad URL shape | `[!] Not a YouTube URL — expected a channel (@handle, /c/, /user/), a playlist (?list=…), or a video link` |
| Probe unreachable | `[!] could not reach YouTube — check your connection and try again` |
| Not found/private | `ERROR: source not found or private: <url>` |
| Requires sign-in | `[!] N videos require sign-in — skipped` |
| Non-tty guard | `[!] ytSync needs a terminal for its prompt — use 'pos media ytsync sync' for unattended runs.` |
| EOF cancel | `[+] Cancelled — nothing changed` |

**Progress / summary lines**

```text
[+] Some Channel — 12 new of 812
  [1/12] Video title here
OK [1/12] Video title here (4m12s)
[!] unavailable: Some old video (deleted or private)
OK Sync complete: 12 new, 800 already present, 1 failed → /home/u/Videos/Some Channel
DRY RUN complete — 12 new would be fetched → ~/Videos/Some Channel
```

**Notification messages**

```text
📺 ytSync — 3 new videos: Linus Tech Tips
• Video title one
• Video title two
• Video title three
→ ~/Videos/Linus Tech Tips
```
```text
⚠️ ytSync FAILED for Linus Tech Tips
⚠️ ytSync — 2 videos failed: Some Channel (run 'pos media ytsync sync' to retry)
```

---

## 4. Affected areas (UX surface only)

- **`bin/pos-media-ytsync`** (new) — everything specified above: verbs, menu, prompts, copy, states, summaries.
- **`bin/pos`** — only if A1 resolves to Option 2: append `media-ytsync` to `INTERACTIVE_CMDS` (`bin/pos:261`). Optional EXAMPLES line in `usage()`.
- **Completions** — via `# POS_SUBCMDS:` / `# POS_FLAGS:` headers + `make gen` (no hand edits).
- **Docs** — `DOC/POS.md` media row + detail block; `DOC/HOWTO.md` index row; section in `DOC/howto/media.md`; AGENT_TODO Done entry.
- **No changes required** to `lib/common.sh` or `lib/notify.sh` — both consumed as-is.

## 5. Scope boundary

Out of scope (explicitly): writing/implementing any code; yt-dlp flag selection and state-file mechanics (Architect — A1–A5); cookies/members-only auth support (v1 reports them as skipped; parity with mp3/mp4's `--cookies` is a fast-follow candidate); whole-channel "every playlist" trees (v1 = channel→flat, playlist URL→one subdir); SponsorBlock/format selection beyond bestvideo+bestaudio merge parity; scheduling integration docs beyond pointing at `pos system schedule` with the `sync` verb.

## 6. Usability verification plan (for Tester)

Harness rules (per `DOC/DEV.md:191-212`): stub-PATH fake `yt-dlp` emitting canned metadata/progress; env-seam overrides for every written path (`YTSYNC_*` names = Architect's, A3); throwaway `/tmp/opencode/ytsync-*`; assert **side effects, not prompt strings**, when piped (`DOC/DEV.md:209`).

PTY-driven prompt tests — `printf 'answer\n' | script -qec "cmd" /dev/null` (`DOC/DEV.md:198`):

1. Fresh add happy path: feed URL + Enter → assert registry entry, dir created, archive lines appended, summary string exact-match, rc 0.
2. EOF at URL prompt (empty PTY input) → guard-free clean exit 0, nothing registered.
3. Invalid input ×3 → cancel message, rc 0, nothing registered.
4. Decline add-confirm (`n`) → no dirs, no download, back-to-menu/exit 0.
5. Menu loop: pick Sync-all, then 0 → two actions, one process, rc 0.
6. Non-tty matrix: bare call with stdin closed/pipe under `timeout 10` → exactly the guard line on stderr, rc 0, **no hang**; same for EOF mid-menu.
7. `sync` non-tty full run → completes with zero prompts, summary + history line present.
8. Log hygiene: simulate dispatcher tee → assert no `\r` bytes in captured log (`grep -c $'\r'` = 0).
9. Incremental idempotency: second `sync` → `0 new`, all "already present", mtimes unchanged.
10. Collision fixture: pre-existing same-name file → warning counted, existing file byte-identical afterwards.
11. Failure paths: fake yt-dlp failing per-video → run continues, count correct, rc 0; failing at channel level → rc 1 + `⚠️` notify.
12. Notify capture: fake `pos-communication-telegram-sender` appending to `sends.log` (DEV.md:205 pattern) → digest sent only when new>0 or failed>0; silent noop verified.
13. Dry-run: matches plan block above; zero writes anywhere (assert tree absent).
14. Gates after implementation: `make gen && make check && make lint` (0 FAIL / 0 WARN).

## 7. Remaining uncertainty (assumptions for reconciliation)

| # | Assumption | Owner |
|---|---|---|
| A1 | Prompt transport `/dev/tty` (recommended, keeps logging) vs `INTERACTIVE_CMDS` registration (loses all logs for script) | Architect |
| A2 | Metadata-probe mechanics (`--flat-playlist`-style single probe) and acceptable latency (~seconds; shown under a `spawn` label) | Architect |
| A3 | State layout: registry file + per-channel archives; location **outside** `~/Videos`; env-seam names for tests | Architect |
| A4 | yt-dlp flag ownership: `--download-archive`, `--windows-filenames`, `--trim-filenames`, merge format parity with mp4, retry flags | Architect |
| A5 | Digest policy interplay with `pos system schedule` NOTIFY policies (avoid double-notifications when run *as* a scheduled job) | Architect |
| A6 | Dep-guard copy says `sudo apt install yt-dlp`, but `preinstall.sh:64-67` installs yt-dlp from GitHub binaries — pre-existing drift shared with mp3/mp4 (`bin/pos-media-mp4:17`); consistency kept for now, Maintainer may want one accurate canonical string | Maintainer |

Open product questions: cookies/auth demand (fast-follow); whether `remove` should also offer deletion (v1: never deletes).

## 8. Recommended next agent

**Architect** — reconcile A1–A5 (state layout, prompt transport vs dispatcher logging, yt-dlp flag set), then hand to Builder with this spec as the behavioral contract; Reviewer may pre-check spec completeness against §6's test matrix.

*Changes made by Designer:* this report only (`reportAgents/2026-08-22-designer-ytsync.md`). No other files touched.
