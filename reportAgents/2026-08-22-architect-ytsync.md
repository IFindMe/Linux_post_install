# Architect Report — `pos media ytsync`

Date: 2026-08-22 · Agent: Architect · Status: **DECISION_READY**

Spec-only task. No code or docs modified outside this report. The dirty share-suite
working tree was left untouched (verified via `git status`: share suite files only).
Builds on `reportAgents/2026-08-22-designer-ytsync.md` (behavioral contract).

> Note (orchestrator): the Architect session could not write files (sandbox denied);
> this report was delivered verbatim and persisted on its behalf.

---

## Status

DECISION_READY — every boundary, ownership, interface, and constraint needed for
implementation is decided below. One environment blocker is recorded in §9
(this session could not write files; content delivered inline). Builder can
start without making architectural choices.

## Objective

Turn the user objective ("tool in media category that asks for a YouTube channel
URL, then incrementally downloads into `Videos/<channel>/<playlist-or-flat>`")
and the Designer UX spec into an implementable architecture: canonical CLI name,
subcommand surface + completion headers, state/storage ownership, yt-dlp
invocation strategy, prompt transport, scheduling integration, dependency guards,
and documentation obligations — resolving Designer assumptions A1–A5.

## Problem

yt-dlp-based one-shot downloaders exist (`mp3`/`mp4`), but none owns *tracked,
incremental* channel sync. The new tool introduces persistent state (registry +
download archives) — the first media tool with machine-owned state — which must
not leak into `~/Videos`, must fit the repo's config/state split, must survive
scheduler runs, and must respect the dispatcher's logging tee and the convention
lint gate.

## Constraints (evidence)

- Naming: lowercase + hyphens, `pos-<category>-<command>` — DOC/AGENT_Context_Project.md:491-496, DOC/DEV.md:497-503.
- New tools start from `templates/pos-tool.sh` (AGENTS.md "Doc conflicts" bullet; template usage at templates/pos-tool.sh:7), need `# POS:`/`# POS_SUBCMDS:`/`# POS_FLAGS:` headers right after shebang, exec bit `100755`, auto-discovery — DOC/DEV.md:122-136, AGENT_Context_Project.md:530-539.
- Dispatcher pipes non-interactive tools through a logging `tee`; stdin-readers must be in `INTERACTIVE_CMDS` or prompts break — bin/pos:283-288, bin/pos:261, DOC/DEV.md:58. Registration is all-or-nothing per script.
- Lint gate excludes `/dev/tty` reads from the stdin⇄INTERACTIVE_CMDS check — DOC/DEV.md:327-329 (rule class at :344-346).
- Env seams: every written path guarded `VAR="${VAR:-default}"` — DOC/DEV.md:196 (+ missing-leading-`:-` gotcha), review step DEV.md:180-182.
- Deps guards sit before `-h|--help`; non-apt binaries get `command -v` guards in-tool, never PACKAGES — DOC/DEV.md:110, :149, AGENTS.md Quick facts. yt-dlp is a GitHub-release binary (preinstall.sh:64-67); ffmpeg/jq are apt (preinstall.sh:40, :29).
- Config dir seam is canonical in lib/common.sh:19 (`CONFIG_DIR`); runtime tool config = `~/.config/linux_post_install/<tool>.env` chmod 600 with env precedence (DOC/DEV.md:156); `# POS_CONFIG:` grammar in lib/config-ui.sh:7-15 (live example bin/pos-communication-scrcpy:5).
- Machine-owned mutable data lives under `~/.local/share/linux_post_install/` (scheduler state/logs lib/scheduler-lib.sh:26-28; entertainment last-run state, ai sessions — AGENT_TODO Done entries 2026-08-09/13).
- Structured record separators: never tab/IFS-whitespace; use `\x1f` — DOC/DEV.md:207.
- Atomic config/job writes via mktemp+mv precedent — lib/scheduler-lib.sh:108-123.
- Scheduler jobs: chmod-600 `.env` files with `INTERVAL/NOTIFY/COMMAND`; policies `always|onchange|onerror|threshold|never`; `COMMAND` executed via `bash -c` — lib/scheduler-lib.sh:4-21, :180; per-job run state recorded regardless of policy — :231-244.
- Timer machinery is shared (lib/user-timers-lib.sh) but bespoke enable/disable subcommands duplicate the general scheduler (consolidation history in AGENT_DONE 2026-08-12 `system schedule` entry).
- Notify: opt-in source, silent-fail, never affects exit codes — lib/notify.sh:24-25, :72-84; ERR-trap alarm precedent bin/pos-media-sync:74.
- Colors auto-disable when stdout isn't a TTY — lib/common.sh:2-13 (relevant under the tee branch).
- Definition of done: `make gen && make check && make lint` (0 FAIL/0 WARN) + CI tags — AGENTS.md Quick facts, DOC/DEV.md:190.

---

## Decisions

### D1 — Canonical name: `pos media ytsync` (file `bin/pos-media-ytsync`); "ytSync" is display branding only

**Decision.** CLI/file name follows the repo naming rule exactly: `bin/pos-media-ytsync`,
invoked as `pos media ytsync`. The mixed-case "ytSync" appears ONLY as a human-facing
brand string inside the interactive menu header, notification copy, and docs prose.

**Why.** "Hyphens for word separation, lowercase always" (AGENT_Context_Project.md:491-496;
DEV.md:497-503) is unqualified; every generated table (tree/dispatch/filetable),
completion map, and the dispatcher's filename-derived discovery (bin/pos:17-26)
assume it. A camelCase filename would be a lone outlier across 37 tools and would
force special-casing in generators for zero functional gain. Display branding
costs nothing and preserves the user's mental model.

### D2 — Subcommand surface RATIFIED (Designer D1), with three small amendments

**Decision.** Exactly the Designer's surface:

```
pos media ytsync                  # interactive front door (empty-state → URL prompt; else looping menu)
pos media ytsync add [<url>]      # register + first sync (prompts iff url omitted)
pos media ytsync sync [<name>]    # incremental pass; no arg = all tracked sources; NEVER prompts
pos media ytsync list             # tracked-sources table + footer showing state paths; non-tty safe
pos media ytsync remove <name>    # stop tracking; keeps downloaded files AND archive
# flags: --dry-run (add/sync/remove), -h/--help
```

Headers (single source of truth for gen/completion):

```bash
# POS: media ytsync — Incrementally sync YouTube channels/playlists into ~/Videos
# POS_SUBCMDS: add sync list remove
# POS_FLAGS: --dry-run
```

Carrying both `POS_SUBCMDS` and `POS_FLAGS` on one tool is precedented
(`pos-network-download` — AGENT_TODO Done 2026-08-12: "# POS_SUBCMDS: (18) +
# POS_FLAGS:"); completion updates come exclusively from `make gen`.

**Amendments** (boundary tightenings, not redesigns):
1. **Name matching:** `sync <name>` / `remove <name>` accept the internal slug OR the
   exact display name; no fuzzy/prefix matching (ambiguity → error listing candidates,
   rc 1). Prevents surprise partial matches against stored names containing spaces.
2. **Ambiguous URLs:** a URL carrying BOTH `v=` and `list=` parameters is treated as a
   SINGLE VIDEO with an implied `--no-playlist` (flag precedent bin/pos-media-mp4:39);
   pure `…&list=…` without `v=` is a playlist source. Rule: nobody accidentally
   backfills a 500-video playlist by pasting a watch link copied from a playlist view.
   Documented in usage().
3. **Verb-less flag invocation:** `pos media ytsync --dry-run` (no verb) prints a
   one-line usage hint on stderr ("use 'add --dry-run' or 'sync --dry-run'") and exits 1.

**Exit codes RATIFIED** (Designer D2): 0 = completed, including "0 new", clean cancels,
EOF, and the non-tty guard; 1 = fatal only (missing dep, invalid explicit URL, unknown
`<name>`, or ≥1 requested source failing wholesale during `sync`). Per-video failures
never flip the exit code. Scheduler observability is preserved even at rc 0/noop because
the scheduler records rc/output per run (lib/scheduler-lib.sh:231-244).

### D3 — State & storage layout (resolves A3: AGREED with placement split config-vs-state)

**Decision.**

**User-editable runtime config** (repo's `<tool>.env` pattern, DOC/DEV.md:156):
`~/.config/linux_post_install/ytsync.env`, chmod 600, loaded with env-var precedence,
registered for the shared config UI:

```bash
# POS_CONFIG: ytsync | ytsync.env | YTSYNC_VIDEOS_DIR=:Videos root for synced channels (default ~/Videos) | YTSYNC_EXTRA_ARGS=:Extra yt-dlp flags appended verbatim to every yt-dlp call (advanced)
```

(grammar per lib/config-ui.sh:7-15; EXTRA_ARGS escape-hatch precedent:
`SCRCPY_EXTRA_FLAGS` bin/pos-communication-scrcpy:5). Two keys only. No
postinstall template — defaults are complete without a file (absence tolerated on read);
the file materializes via `pos config ytsync`.

**Machine-owned state** — NOT config, so it lives under the repo's data root
(precendent: scheduler state lib/scheduler-lib.sh:27-28):

```
~/.local/share/linux_post_install/ytsync/
├── registry            # one line per tracked source, \x1f-delimited (see below)
├── archive/<slug>.txt  # native yt-dlp --download-archive format, one per source
└── history.log         # append-only: date · source · new/skipped/failed per run
```

`registry` record fields (in order, `\x1f`-separated — never tabs, per DEV.md:207):

```
slug ⇥type⇥url⇥subdir⇥playlist_title⇥added_ts        (⇥ = \x1f)
```

- `slug` — unique internal key `[a-z0-9][a-z0-9_-]*`, derived from the probed
  `uploader_id`/handle (sanitized), numeric `-2` suffix on collision. Keys archive
  filenames and is the primary argument token for `sync`/`remove`.
- `type` — `channel | playlist | video` (classification rule in D4).
- `subdir` — destination path RELATIVE to the videos root, resolved ONCE at
  registration (e.g. `Linus Tech Tips` or `David Malan/CS50 lectures`). Stored, never
  recomputed — YouTube renames never mutate the local tree (ratifies Designer D3).
- `playlist_title` — empty for flat sources; display-only.
- Writes are atomic (temp+mv, lib/scheduler-lib.sh:108-123 pattern).

**Ownership rule:** `~/Videos/<subdir>/` contains NOTHING but media files. Registry,
archives, history live outside it — satisfies the Designer requirement and keeps the
media tree TV/stick-syncable without metadata noise.

**Env seams (test overrides)** — all written `VAR="${VAR:-default}"` with the leading
`VAR:-` (DEV.md:196 gotcha):

| Seam | Default | Role |
|---|---|---|
| `YTSYNC_VIDEOS_DIR` | `$HOME/Videos` | user-facing key AND test seam (same duality as `MEDIA_SYNC_SOURCE`, bin/pos-media-sync:16) |
| `YTSYNC_STATE_DIR` | `${XDG_STATE_HOME:-$HOME/.local/share}/linux_post_install/ytsync` | test seam only — not advertised in usage() |
| `CONFIG_DIR` | already canonical (lib/common.sh:19) | covers ytsync.env location |

No dedicated binary seams — fake `yt-dlp`/`jq`/`ffmpeg` arrive via stub PATH (DEV.md:197).

**`remove` semantics:** drops the registry line; KEEPS downloaded files AND keeps the
archive file. Keeping the archive makes a future re-add of the same source a true
incremental resume instead of a full re-download colliding with existing files under
`--no-overwrites` (which would spam collision warnings). Orphaned archives (tiny text
files) are acceptable; documented in help text.

### D4 — yt-dlp strategy (resolves A2 + A4: AGREED with amendments)

**Registration/dry-run probe (A2):**
- Single fast call: `yt-dlp --flat-playlist -J -- <url>` (dump-single-json; flat
  entries stay stubs → 1–2 HTTP round trips regardless of library size). Latency
  budget: seconds; wrapped in `spawn "Resolving source …"` — spawn's designed habitat
  for short pre-steps (Designer D4 concurs; mp3/mp4 wrap their quick calls likewise).
- Parse with `jq` (already a repo dep, preinstall.sh:29; guard per D7).
- Display-name chain: `.channel // .uploader // .uploader_id // .title` — mirrors the
  repo's established fallback-alternation idiom (`%(artist,uploader)s`
  bin/pos-media-mp3:69,:77). Resolved ONCE, shown on the add-confirm screen, stored in
  the registry. Never used as a per-video directory template (avoids collaboration/
  cross-post scatter — Designer D3 rationale upheld).
- The probe JSON also yields entry ids/titles/count → the **new-list is computed BEFORE
  any download** by diffing entry ids against `archive/<slug>.txt`. Consequences: exact
  `[n/N]` counts, exact dry-run plans, zero speculative downloads.
- Classification (deterministic, URL-shape based): contains `list=` without `v=` →
  playlist source; contains neither → channel/video flat source; both → single video
  (D2 amendment 2).

**Download invocations (A4):** paths are COMPUTED from stored registry fields — the
tool does not lean on `%(playlist_title)s` or `--output-na-placeholder` for shaping.
This removes A4's fragile empty-for-flat question entirely: a stored `subdir` cannot
be NA, cannot drift mid-library, and `list` renders destinations straight from the
registry. Per-invocation templates:

- flat/channel/video: `-o "<videos_dir>/<subdir>/%(title)s.%(ext)s"`
- playlist: `-o "<videos_dir>/<subdir>/<NNN> - %(title)s.%(ext)s"` where `<NNN>` is a
  LITERAL zero-padded index injected by the tool (taken from the probe's entry
  position/`playlist_index`), because the chosen execution model (below) invokes
  yt-dlp per video and a standalone video URL has no live `%(playlist_index)s`.

**Execution model:** one yt-dlp invocation PER NEW VIDEO, looped in diff order:

```
yt-dlp -f "bestvideo*+bestaudio/best"
       --merge-output-format mp4          # parity: bin/pos-media-mp4:120
       --embed-metadata --embed-chapters  # parity: mp4:121
       --embed-thumbnail                  # parity: mp4:123
       --no-overwrites                    # parity: mp4:124
       --download-archive "<state>/archive/<slug>.txt"   # crash-safe per-video recording
       --windows-filenames                # USB/Samba/TV-safe names (Designer D3 ask)
       --trim-filenames 120               # headroom for NNN prefix + ext under 255-byte limits
       --retries 3 --fragment-retries 3
       [--no-playlist]                    # only for v=+list= URLs
       ${YTSYNC_EXTRA_ARGS}               # appended LAST — user override hatch
       -o "<template from above>"
       "<canonical per-video URL>"
```

Rationale for per-video loops over one batched call: identical code path for
channel/playlist/video types; exact per-video `[n/N] title` + OK lines with no log
parsing; precise failure isolation (Designer D6 taxonomy maps 1:1 to loop iterations);
crash-resume safety via the archive. Cost — one extra extraction round trip per video
(~seconds on a multi-hour backfill) — accepted for v1; batching is a listed future
optimization, not a design gap.

**Deliberate divergences from mp4, documented in help text:**
- NO `--embed-subs --sub-langs all`: bulk-library size bloat for marginal value;
  users re-add subs per-source via `YTSYNC_EXTRA_ARGS` (appended-last wins in yt-dlp).
- Progress hygiene (contract, mechanics left to Builder within it): our own LF-terminated
  per-video lines are the heartbeat; pass `--quiet --no-warnings` toward yt-dlp and add
  `--progress` ONLY when stdout is a TTY — `\r` bytes must never reach the tee'd log
  (Designer D4/D9). NEVER wrap the batch in `spawn()` — spawn captures output until
  completion (lib/common.sh:88-90) = hours of silence behind a braille spinner.
- Sequential downloads; no concurrency knob in v1.

### D5 — Prompt transport (resolves A1: `/dev/tty` reads; NO INTERACTIVE_CMDS registration)

**Decision. Option 1 — read interactive input from `/dev/tty`. Do NOT add
`media-ytsync` to `INTERACTIVE_CMDS`.**

**Justification:**
1. **Logging preserved where it matters most.** Unregistered tools run through the
   dispatcher's tee branch (bin/pos:283-288) — hours-long `sync` runs leave a complete
   per-file audit trail in `~/.local/share/linux_post_install/logs/`. Registration is
   all-or-nothing per script (DOC/DEV.md:58): it would silence logs for `sync`, `list`,
   and `add <url>` alike — the wrong trade for a long-running downloader.
2. **Lint-clean by explicit carve-out.** `/dev/tty` reads are excluded from the
   stdin⇄INTERACTIVE_CMDS gate (DOC/DEV.md:327-329) — no FAIL/WARN either way, no
   `bin/pos` edit, no completion/doc churn.
3. **Precedent.** sudo reads `/dev/tty` (noted at DEV.md:58); smb-client password
   prompting via `/dev/tty` shipped 2026-08-11 (AGENT_TODO Done). share-lib's guard
   (`[ -t 0 ]` else hint+clean exit, lib/share-lib.sh:38-44) remains the entry gate.

**Builder obligations under this decision:**
- Every interactive entry point checks stdin-tty FIRST (share_menu_guard pattern);
  the guard message points at `sync` for unattended runs (Designer copy, D2 matrix).
- All prompt reads use `read -rp '...' </dev/tty`; bash prints `-p` prompts to stderr
  when input is a terminal → stdout stays machine-parseable (Designer D9 holds).
- EOF on the tty read = clean cancel of the current step, rc 0 (Designer D2).
- Accepted consequence (repo-wide behavior, not new): dispatched runs pipe stdout
  through tee → colors auto-disabled (lib/common.sh:2-13). Menus/tables must remain
  fully readable colorless — they are, because semantics ride `[+]`/`[!]`/`ERROR:`/`OK`
  prefixes (Designer D9). Direct invocation (`bin/pos-media-ytsync` or post-install
  `/usr/local/bin`) on a real terminal keeps colors.
- If INTERACTIVE_CMDS had been chosen instead (rejected): Designer D5's history line
  would become mandatory; moot here — the history log is specified in D3 anyway.

### D6 — Scheduling integration (resolves A5: primary path = `pos system schedule` job; NO built-in enable/disable; NO own timers)

**Decision.** ytsync ships as a bare manual tool. Automation is documented as a
scheduler job — the repo's general-purpose facility (jobs = chmod-600 env files,
lib/scheduler-lib.sh:4-11; `COMMAND` runs via `bash -c`, :180; per-job user-timer
units reconciled on enable/disable):

```
# recommended recipe (goes in howto/media.md + POS.md):
pos system schedule config   → name: ytsync
  INTERVAL=daily
  NOTIFY=never                 # ← the double-notify resolution, see below
  MSG="ytSync"
  COMMAND=pos media ytsync sync
```

**Rejected alternative:** entertainment-style `enable/disable` subcommands writing
their own user-timer pairs (precedent bin/pos-entertainment-enable:47-48 +
lib/user-timers-lib.sh:65-94). Rejected because it duplicates interval validation,
unit writing, linger bootstrap, run-state, and run logs that `pos system schedule`
already provides generically — the platform consolidated FROM bespoke single-purpose
timers INTO the scheduler (AGENT_TODO Done 2026-08-12); a third timer writer inverts
that decision. Entertainment keeps its own UI for historical reasons, not as a pattern
to extend.

**Double-notify resolution (A5):** single-notification-owner principle — the TOOL owns
content notifications (D7: noteworthy-only digest + ERR-trap alarm); the JOB therefore
runs `NOTIFY=never` ("silent side-effect jobs", lib/scheduler-lib.sh:19). Result:
exactly one notification path can fire per event. Observability is not lost: rc and
output are still recorded per run and visible in `pos system schedule list/status`
(lib/scheduler-lib.sh:246-252, :560-568) — including rc 1 when every requested source
failed. Users who deliberately prefer scheduler-owned alerts simply don't enable the
job recipe as documented (and accept doubled failure alarms); v1 adds no config key to
silence the tool's own notify — out of scope (§ Scope).

**Timer-safety by construction:** `sync` never prompts (D2); interactive verbs hit the
non-tty guard and exit 0 — an accidental misconfiguration of the job command can't hang
a timer unit (TimeoutStopSec=5s backstop exists regardless, lib/user-timers-lib.sh:77).

### D7 — Dependencies, guards, dry-run boundary, notify ownership

- **Guards (before `-h|--help`, DOC/DEV.md:110):**
  - `yt-dlp`: `command -v` guard, ACTIVE EVEN UNDER `--dry-run` — deliberate
    divergence from mp3/mp4 (their `--dry-run` skips all guards because it only prints
    a command line, bin/pos-media-mp3:16-19; mp4:16-19). ytsync's dry-run IS the probe;
    without yt-dlp it has no value. Copy uses accurate install guidance for THIS repo:
    `err "yt-dlp not found — installed by preinstall.sh (GitHub release → /usr/local/bin); run ./preinstall.sh or see DOC/howto/media.md"`.
    Do not propagate mp3/mp4's inaccurate `sudo apt install yt-dlp` string (their drift
    = Maintainer follow-up, Designer A6; fixing them here is out of scope).
  - `jq`: guarded (probe parser; apt-dep preinstall.sh:29, guard precedent
    bin/pos-media-sync:14).
  - `ffmpeg`: guarded, SKIPPED under `--dry-run` (no merge/embed happens during a plan;
    structure mirrors the conditional-guard block of mp3/mp4).
- **PACKAGES: unchanged.** yt-dlp is a non-apt GitHub-release installer (preinstall.sh:64-67)
  → in-tool guard per the non-apt rule (AGENTS.md Quick facts; DOC/DEV.md:149);
  ffmpeg/jq already present (preinstall.sh:40, :29).
- **`--dry-run` support boundary:** valid on `add` and `sync` (probe + plan block +
  example filenames; ZERO writes — no registry mutation, no directories, no archive
  appends, no notify) and on `remove` (preview only). Dry-run performs real network
  probes; it is honest about needing connectivity.
- **Notifications:** THE TOOL sources `lib/notify.sh` opt-in and owns delivery:
  per-run digest ONLY when new>0 or failed>0 (Designer D7 shape/caps ratified);
  `trap 'notify_send "⚠️ ytSync FAILED …"' ERR` mirroring bin/pos-media-sync:74;
  silent-fail safety guaranteed by lib/notify.sh:24-25,72-84. The scheduler side stays
  silent via `NOTIFY=never` (D6). Emoji/plain-text conventions per entertainment-send
  precedent. No markdown in v1.

### D8 — Documentation obligations checklist (Builder, same commit)

1. `tools-docs/ytsync.md` — NEW research doc honoring the pending per-tool-research-docs
   convention (directory does not exist yet — creating it is part of this workflow):
   probe mechanics, chosen flag set + why each flag, archive format, classification
   rules, edge cases (mid-playlist inserts, title renames, sign-in-skipped).
2. `DOC/POS.md` — media section table row + detail block (hand-written; lint WARN
   coverage class, DEV.md:347).
3. `DOC/HOWTO.md` index row + section in `DOC/howto/media.md`: recipes (first channel,
   daily automation via the D6 schedule recipe, troubleshooting sign-in-skipped /
   collision warnings / probe failures).
4. Generated surfaces — run `make gen`: AGENT_Context tree/dispatch/filetable rows +
   completions/pos.bash subcmd/flag entries. Never hand-edited (GEN markers).
5. Hand-maintained spots in `DOC/AGENT_Context_Project.md`: add a §14 "Common Tasks"
   row ("Modify YouTube channel sync logic → Edit bin/pos-media-ytsync"). Line-count
   table: the `bin/pos-media-ytsync` row is gen-generated; no manual bump needed.
6. `bin/pos` usage() EXAMPLES: optional showcase line (hand-maintained block,
   bin/pos:140-207) — recommended, e.g. `pos media ytsync sync   Incremental YouTube channel sync`.
7. `AGENT_TODO.md`: move the task to **Done (dated) in the same commit** (repo rule).
8. `INTERACTIVE_CMDS` in `bin/pos`: **NO change** (consequence of D5).
9. `preinstall.sh`, `postinstall.sh`, `install.sh`, `AGENTS.md` Quick facts, root
   `README.md`: **NO change** (deps present; no new category; no structural fact).
10. Gates: `make gen && make check && make lint` ending 0 FAIL / 0 WARN.

### D9 — v1 OUT of scope (explicit non-goals)

- Cookies/auth (members-only, age-gated): reported as "N videos require sign-in —
  skipped"; manual escape hatch = `YTSYNC_EXTRA_ARGS="--cookies …"`. Fast-follow candidate.
- Live streams / premieres handling beyond whatever yt-dlp naturally skips.
- SponsorBlock, segment cutting, format/quality selection UI (fixed
  bestvideo*+bestaudio → mp4 merge; override via `YTSYNC_EXTRA_ARGS`).
- Deleting or renaming local files when YouTube deletes/retitles/reorders (archive is
  keyed by video id; local files are immutable once written; mid-playlist insert shifts
  FUTURE numbering only — documented caveat).
- Auto-expanding a channel into all of its playlists (channel URL ⇒ flat videos; one
  playlist URL ⇒ one subdir).
- Audio-only mode (that is `pos media mp3`'s job), subtitles embedding (divergence
  documented in D4), thumbnail/NFO/Kodi sidecar files.
- Built-in enable/disable/schedule subcommands; any new systemd units (D6).
- Per-tool notify on/off switch; rclone/cloud offload; dedupe; concurrency controls;
  rate-limit tuning beyond the fixed retry defaults.
- Renaming/migrating existing libraries; import of previously downloaded trees (a
  manually seeded `--download-archive` file is the power-user path, undocumented beyond
  tools-docs).
- Fixing the mp3/mp4 dep-guard copy drift (Maintainer, A6).

---

## Ownership

- `bin/pos-media-ytsync` (new tool) owns: registry/archive/history lifecycle, probe,
  download loop, prompts/menu, summaries, notifications, dry-run.
- `pos system schedule` (existing) owns: timing, run logs, run state for scheduled runs.
- `lib/notify.sh` (existing, consumed as-is) owns: platform routing/delivery.
- `lib/common.sh` / `lib/config-ui.sh` (existing, consumed as-is) own helpers/config UI.
- Nothing new in `lib/` — one self-contained tool; if a second consumer of this
  registry ever appears, extracting a lib becomes a fresh architectural decision.

## Interfaces

- CLI: `pos media ytsync {add [url]|sync [name]|list|remove <name>} [--dry-run] [-h|--help]`
  (headers in D2 feed dispatch help, tree, completion via `make gen`).
- Config surface: `# POS_CONFIG: ytsync …` → `pos config ytsync` (keys in D3).
- State format: registry record schema in D3 (`\x1f`-separated; treat as internal —
  `list` is the supported read API; format changes require a migration note).
- Notification messages: Designer §3 copy, plain text.
- Exit-code contract: D2.

## Affected areas (exact files)

**Create:**
- `bin/pos-media-ytsync` — from `cp templates/pos-tool.sh`, chmod `100755`, committed mode 100755.
- `tools-docs/ytsync.md` — research doc (new directory; pending convention).

**Modify (docs/process only):**
- `DOC/POS.md` — media row + detail block.
- `DOC/HOWTO.md` + `DOC/howto/media.md` — index row + hands-on section incl. schedule recipe.
- `AGENT_TODO.md` — Done entry (dated, same commit).
- `DOC/AGENT_Context_Project.md` — §14 Common-Tasks row (hand) + generated blocks (via `make gen`).
- `completions/pos.bash` — via `make gen` only.
- `bin/pos` — OPTIONAL usage() EXAMPLES line only; **NOT** INTERACTIVE_CMDS.

**Explicitly NOT touched:** `preinstall.sh`, `postinstall.sh`, `install.sh`,
`lib/*` (incl. `user-timers-lib.sh`, `scheduler-lib.sh`, `share-lib.sh`),
all existing `bin/pos-*` tools, the dirty share-suite work.

## Approved implementation scope (for Builder)

Implement `bin/pos-media-ytsync` exactly within D1–D9 + Designer's behavioral spec
(its §2–§3 copy/states are binding UX contract). Allowed: internal helper functions,
ordering of flags within the D4 skeleton, choice of jq filters achieving D4's
extractions. Not allowed without returning to Architect: new verbs, new flags beyond
`--dry-run/-h/--help`, any write outside `YTSYNC_VIDEOS_DIR`/`YTSYNC_STATE_DIR`/
`CONFIG_DIR` seams, INTERACTIVE_CMDS changes, new libs, new systemd units, changes to
shared scripts, deviation from exit-code contract.

## Verification plan (Builder proves; Tester adversarially re-proves)

Static gates (definition of done): `make gen` (byte-stable, LC_ALL=C determinism),
`make check`, `make lint` → `0 FAIL, 0 WARN`; `bin/pos help media ytsync`;
`pos media ytsync -h`; `pos media --help` lists the tool; CI tags green on push.

Env-seam proof (DEV.md:180-188): with `YTSYNC_STATE_DIR=/tmp/opencode/ytsync-test/state`
and `YTSYNC_VIDEOS_DIR=/tmp/opencode/ytsync-test/Videos`, assert the real
`$HOME/.local/share/linux_post_install/ytsync` and `$HOME/Videos` are byte-untouched
(guards the missing-leading-`:-` gotcha, DEV.md:196).

Stub-PATH behaviour suite (throwaway, `/tmp/opencode/ytsync-test/` per DEV.md:192-212;
fake yt-dlp emitting canned `-J` JSON + per-video success/failure; fake
telegram sender appending to `sends.log`): run Designer §6's 14-case matrix verbatim
— it already encodes this architecture's observable contracts (registry/archives/
summaries/rc/non-tty/no-\r-in-log/idempotency/collision/notify-policy/dry-run-zero-writes).
Add these architect-mandated cases:
15. Dispatcher integration: `bin/pos media ytsync list` under piped stdout → per-command
    log file created (proves no INTERACTIVE_CMDS entry is needed or present).
16. Playlist numbering: fixture playlist source → files land as `001 - …`, `002 - …`
    (literal-index injection correct; stable across a second sync).
17. `v=`+`list=` URL → single video downloaded with `--no-playlist`, registered type `video`.
18. `remove` then re-`add` same source → archive retained → second add reports 0 new.
19. Registry atomicity: simulate mid-write failure (stub) → registry either old or new,
    never truncated.
20. Accurate dep-guard copy: missing yt-dlp stub PATH → error text matches D7 wording,
    fires even for `--dry-run` and `--help`.

PTY-driven prompt tests per DEV.md:198 (`printf 'answer\n' | script -qec … /dev/null`)
for the Designer matrix items 1–6.

Live smoke (real box, optional but recommended before Done): one small channel add +
two consecutive `sync` runs (second = 0 new), then the D6 schedule recipe with
`NOTIFY=never` and `run ytsync` once.

## Remaining uncertainty (explicit, non-blocking)

1. Probe JSON field availability varies by extractor version/site (`channel` may be
   null off-YouTube) — mitigated by the four-step fallback chain + mandatory
   resolved-name confirm screen; worst case stores a handle string.
2. Literal `NNN - ` prefix passes through yt-dlp's windows-filename sanitation
   unchanged (digits/space/dash are legal everywhere); verify in case 16 — if a
   sanitizer edge appears, fall back to per-video `--parse-metadata` injection.
3. Per-video invocation overhead on very large backfills (accepted; batching listed as
   future optimization in tools-docs).
4. Slug stability if a channel migrates handles — archive keyed by video id inside, so
   worst case is a re-resolve, not re-download.
5. Whether subtitles should default on later (decided off; revisit on user feedback).

**Open questions needing user/orchestrator input (non-blockers):**
- Codify the pending `tools-docs/` convention somewhere authoritative (MAINTENANCE.md?)
  — currently honored only by workflow instruction.
- Preferred default schedule interval for the recipe (doc suggests `daily`; user taste).
- Maintainer follow-up on mp3/mp4 dep-guard copy accuracy (A6) — separate small task.

**Recommended next agent**

**Builder** — implement `bin/pos-media-ytsync` + docs checklist per this report and the
Designer spec, starting from `templates/pos-tool.sh`. Reason: boundaries, interfaces,
state formats, flag sets, transport, and verification are fully pinned; no
architectural latitude remains that Builder would have to guess. Reviewer should
adversarially check the finished tool against D1–D9 + Designer §6 before Done.

## Architect changes

None committed — spec-only session; this document is the sole artifact.
