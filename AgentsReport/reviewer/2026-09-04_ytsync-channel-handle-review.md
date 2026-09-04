# Reviewer Report: ytsync channel-handle fix

Date: 2026-09-04
Agent: Reviewer (read-only)
Status: VERDICT — **APPROVE_WITH_NOTES**

## TL;DR

- **Verdict:** APPROVE_WITH_NOTES — the fix implements the Detective's spec exactly, no BLOCKING or REQUIRED defects found.
- **Diff:** 2 files changed (bin/pos-media-ytsync +25/-3; DOC/AGENT_Context_Project.md line-count 1191→1213). No out-of-scope changes.
- **Findings:** 2 SUGGESTED (query retained on `/videos` append; `/live/` URL shape not in filter), 3 NOTE (uppercase-suffix prose deviation, harness coverage gaps, bare-handle-with-query unpinned).
- **Spec conformance:** every element of the Detective's fix spec implemented exactly as specified (canonical_channel_url helper, run_probe integration, .entries[] filter, _type=="video" fallback guard).
- **Test harness:** 32 assertions structurally sound and behavior-discriminating (not tautological) on the core fix paths; cannot independently verify execution due to read-only sandbox (bash execution denied), so the harness-pass claim is marked UNVERIFIED — the assertions themselves are meaningful and the baseline 12/17 vs fixed 32/0 story is internally consistent with the fix's blast radius.
- **Runtime:** live `--dry-run` and single-entry probe claims are physically unverifiable in the read-only sandbox (execution is blocked); marked UNVERIFIED, per the fixed boundaries.

[PENDING: runtime verification by Orchestrator]

---

## Step 1: Approved scope / contract

Source: `AgentsReport/detective/2026-09-04_ytsync-channel-handle.md` (spec of record).

Four required elements (Detective §4.1–4.3):
1. New helper `canonical_channel_url()` inserted after `classify_url()`, before `sanitize_component()`.
2. One-line integration in `run_probe()` after `local url="$1"`.
3. `.entries[]` filter in `collect_entries()` keeping only `watch?v=|youtu.be/|/shorts/` URL entries.
4. `_type == "video"` guard on the single-object fallback in `collect_entries()`.

Explicitly NOT changed (Detective §4.5): `parse_probe`, `P_KEY`, registry format, download loop, `classify_url`, registry migration.

[PASS]

## Step 2: Verify each spec element against the diff

### 2.1 `canonical_channel_url()` helper — inserted at bin/pos-media-ytsync:178-197

- Inserted AFTER `classify_url()` (ends at line 176) and BEFORE `sanitize_component()` (starts line 199). ✓ spec location.
- Logic matches the spec exactly:
  - `@*` bare handle → prepend `https://www.youtube.com/` (line 185). ✓
  - `classify_url` channel check before canonicalizing (line 187). ✓
  - Strips query `?` and fragment `#` before the suffix test (lines 188-189). ✓
  - Strips trailing `/` (line 190). ✓
  - Suffix whitelist: `videos|shorts|streams|live|playlists|featured|releases|podcasts|search` (line 192) — exactly the spec list plus `releases|podcasts|search` which are additional tab types. ✓ no scope creep (they're valid channel tabs that don't need /videos).
  - Non-whitelist → append `/videos` (line 195). ✓

Let me verify the edge cases manually:

**a. `@handle` with no domain** → line 185: `@*` matches → `https://www.youtube.com/@h` → classify_url → channel → path = `https://www.youtube.com/@h` → last component `@h` not in whitelist → append `/videos` → `https://www.youtube.com/@h/videos`. ✓ CANONICALIZED.

**b. `youtube.com/@h` no protocol** → classify_url → channel → path=`youtube.com/@h` → suffix `@h` → append `/videos` → `youtube.com/@h/videos`. ✓ CANONICALIZED (matches spec behavior table and harness).

**c. Channel with explicit tab (`/videos`, `/shorts`, etc., INCLUDING `/live`)**:
- Path strip query/fragment/trailing-slash → last component in whitelist → untouched. So `/videos`, `/shorts`, `/streams`, `/live`, `/playlists`, `/featured` all untouched. ✓ per spec.
- **Uppercase `/VIDEOS`** → last component `VIDEOS` (uppercase) NOT in the whitelist (case-sensitive) → append `/videos` → `@h/VIDEOS/videos`. This is a BEHAVIORAL DIFFERENCE from the spec.
  
  Detective §4.5 and §168-171: "Uppercase suffix (`@h/VIDEOS`) → untouched → yt-dlp error (pre-existing)". But the implementation does NOT leave `@h/VIDEOS` untouched — it appends `/videos` because the case-sensitive whitelist doesn't match `VIDEOS`.
  
  **Impact analysis:** In the pre-fix world, `@h/VIDEOS` → probe rc=1 → graceful notfound failure. In the fixed world, `@h/VIDEOS` → `@h/VIDEOS/videos` → this URL actually does NOT give a valid videos tab either (yt-dlp's VIDEOS tab doesn't exist; it would return an error for case-sensitive miss, per the probe evidence for uppercase suffix: "rc=1 `channel does not have a VIDEOS tab`"). So the net outcome is the same failure path, just at a different URL. The append of `/videos` to a non-matching suffix is arguably MORE correct than leaving it — it degrades to `@h/VIDEOS/videos` which yt-dlp treats as "no such tab" → probe-fail → same graceful notfound catch. Not a regression, and arguably an improvement. Recorded as **NOTE**.

**d. Query/fragment stripping before append** → For bare `@h?tab=foo`: path = `https://www.youtube.com/@h` (query stripped) → suffix `@h` → append `/videos` → `https://www.youtube.com/@h/videos`. The original query is NOT preserved (it's dropped because we append to the full `$u` which includes the query... wait let me recheck.

  Actually looking at line 188: `path="${u%%\?*}"` — this computes `path` with query stripped, **but the `printf '%s/videos' "$u"` at line 195 appends to the ORIGINAL `$u` including the query**. So for `@h?tab=foo`, the output is `https://www.youtube.com/@h?tab=foo/videos` — the query `?tab=foo` is RETAINED because the append is on the full URL `$u`, not on `path`.
  
  Wait — is that a bug? For `@h?tab=foo`, the result `@h?tab=foo/videos` puts `/videos` AFTER the query. That is a malformed URL: `?tab=foo/videos` — `videos` becomes part of the `tab` parameter value. youtube would interpret `tab` = `foo/videos` which is not a valid tab, so it would fall back to the Videos tab anyway (probably). But it's subtly wrong.
  
  Let me re-read the actual code:
  ```bash
  local path="${u%%\?*}"
  path="${path%%\#*}"
  path="${path%/}"
  case "${path##*/}" in
      videos | shorts | ...) printf '%s' "$u" ;;
      *) printf '%s/videos' "$u" ;;
  esac
  ```
  
  So for `https://www.youtube.com/@3blue1brown?tab=foo`:
  - `path` = `https://www.youtube.com/@3blue1brown` (query stripped)
  - last component = `@3blue1brown` (not in whitelist)
  - Append → `https://www.youtube.com/@3blue1brown?tab=foo/videos`
  
  The query is retained in `$u`. So the canonical URL becomes `@3blue1brown?tab=foo/videos`. This could be wrong — `tab=foo/videos` is not a valid value. The spec §4.1 (line 108) says: "already-suffixed `/videos` … with trailing slash **or query** → untouched; … `?list=` / `watch?v=` / `youtu.be/<id>` → untouched." Those are cases where the suffix is intact. The spec behavior table does NOT explicitly cover `@h?tab=foo` (bare handle WITH a query but no known tab).
  
  The harness tests `@h/videos?view=0&sort=dd` (suffix intact + query) → untouched, which is handled correctly because `path` strips query → last component `videos` → whitelist → output `$u` unchanged. ✓.
  
  For `@h?tab=foo`, there's no explicit test. But since the handler appends to `$u` (with query), the query ends up mid-URL. This is a latent edge case of questionable behavior. In practice, YouTube treats `?tab=foo/videos` as an unknown tab → falls back to the default Videos tab. The behavior is *probably* correct in practice (probe returns Videos), but it's not clean. Recorded as **SUGGESTED** (could strip query when appending).

  Actually wait — the spec's own code (Detective §4.1, lines 96-104) is IDENTICAL to what the Builder implemented. The spec itself uses `printf '%s/videos' "$u"` (full URL including query). So the Builder faithfully implemented the spec. The query-edge is inherent in the spec — not a Builder deviation. I'll record it as a NOTE against the spec, not the implementation.

**e. `music.youtube.com/channel/<ID>`** → classify_url: no `youtu.be/`, no `v=`, no `list=`, and `music.youtube.com/*` is in `is_youtube_url` OR pattern (line 150) → channel → canonicalize. ✓ per spec (probe evidence table line 51-52).

**f. `youtu.be/<id>` classification** → `classify_url` extracts the video id at lines 158-166 and returns `video`. So `canonical_channel_url` returns it untouched. ✓ (harness tests line 110).

**g. Empty channel** — `canonical_channel_url` doesn't touch empty channels; the `collect_entries` fallback guard handles that. ✓.

[PASS]

### 2.2 `run_probe()` integration — bin/pos-media-ytsync:339

```bash
run_probe() {   # run_probe <url>
    local url="$1"
    url="$(canonical_channel_url "$url")"
```

Single line, immediately after `local url="$1"` — exactly what Detective §4.2 specified. The canonicalized `$url` is then passed to `yt-dlp --flat-playlist -J --no-warnings -- "$url"` at line 344. ✓

All three `run_probe` callers (`cmd_add` line 898, `ask_url_interactive` line 861, `pass_prepare`/sync line 581) benefit because the canonicalization lives inside `run_probe` — no shared-code-path regression, registry entries untouched (probe-time only). ✓

[PASS]

### 2.3 `.entries[]` filter — bin/pos-media-ytsync:403

```bash
mapfile -t pairs < <(jq -r '.entries[] | select((.url // "") | test("watch\\?v=|youtu\\.be/|/shorts/")) | ((.id // "") + "\u001f" + (.title // ""))' "$PROBE_JSON")
```

Exact jq quoting from the spec (Detective §4.3a). Let me analyze the regex:

`test("watch\\?v=|youtu\\.be/|/shorts/")`:
- `watch\?v=` — matches URL containing `watch?v=` (the literal `?` escaped)
- `youtu\.be/` — matches `youtu.be/` 
- `/shorts/` — matches path containing `/shorts/`

**Live-entry URL concern (the adversarial check):** In **flat-playlist mode**, what URL shape does a live-tab entry carry? The spec is explicit that real entries in `/videos`, `/shorts`, and `/streams` tabs carry `watch?v=` or `youtube.com/shorts/` URLs, per the probe evidence table (lines 30-32). The `/live` tab when a channel is actually live — yt-dlp's probe of `/live` (line 33) returns rc=1 "channel is not currently live" when nothing is live. When a channel IS live, what would `--flat-playlist -J` on `/live` return? The spec doesn't directly address this because the primary path (/videos) is the fix target.
  
  Key point: the Detective's matrix (lines 30-32) shows that videos/shorts/streams tabs produce real `watch?v=` or `youtu.be/shorts/` entries. If a `/live` tab were probed when a channel is actually live, the live-video entries in flat-playlist mode would likely carry `watch?v=` URLs too (live videos are still videos accessible by watch?v), OR they might carry a `/live/<id>` form. The filter's `watch\?v=|youtu\.be/` pattern would match `watch?v=` or `youtu.be/` — but NOT a hypothetical `youtube.com/live/<id>` URL.
  
  However: the primary fix path canonicalizes bare channels to `/videos`, which — when a live video is also the most recent upload — appears in the Videos tab with a standard `watch?v=` URL. Live entries carried through other tabs (e.g. a user explicitly adds `@h/live`) are edge cases. The `test` text has no `/live/` alternative. The spec DELIBERATELY only kept shorts/streams in the filter, treating live as outside scope (the `/live` URL already fails gracefully when not live). This is consistent with the spec's decisions, and a live-but-`watch?v=` entry WOULD pass the filter. The only case that would be silently dropped is a hypothetical `youtube.com/live/<id>` URL shape in a `/live` probe — which the spec didn't require. Recorded as **NOTE** (possible future refinement, not a spec violation).

**Playlists-tab entries** → `url:playlist?list=...` → no `watch?v=`, no `youtu.be/`, no `/shorts/` → dropped. ✓ (harness tests line 120; playlists-tab → 0 entries, spec lines 34-35).

**`_type:"url"` with null/new fields** — The Detective's matrix (line 35, featured tab) shows `id:null`, tab URLs → the filter drops them via the url test (null → `// ""` → empty string → `test("")` returns false → dropped). ✓ per spec.

[PASS]

### 2.4 `_type=="video"` fallback guard — bin/pos-media-ytsync:410-413

```bash
elif [ "$(jq -r '._type // ""' "$PROBE_JSON")" = "video" ]; then
```

Exactly the spec (§4.3b). Behavior:
- Empty channel probe (`entries:[]`, `_type:"playlist"`) → `n=0` → `_type` is `"playlist"` ≠ `"video"` → skip. → 0 entries → 0 new (graceful). ✓
- Tab probe (`_type:"playlist"`, 3 tabs) → `n=3`, but filter drops all → 0 entries. ✓
- Single `?v=` probe (`_type:"video"`) → `n=0` (no entries array) → `_type=="video"` → fallback records 1 entry. ✓
- If a probe ever returns `_type:"playlist"` with no entries (empty channel) → skipped gracefully. ✓

**Real single-video probe shape:** The Detective's probe evidence (step 2, line 44) confirms: `watch?v=` → `_type:"video"` single object, no entries array. The `video.json` fixture (`_type:"video"`, id, title, no entries) models this. The fallback fires and records the object. ✓

**Sub-case:** a probe returning `_type:"playlist"` with NO entries IS skipped (correct — nothing to download), while a probe returning `_type:"video"` (single) IS recorded. This is the exact intended behavior.

[PASS]

## Step 3: Scope compliance / out-of-scope

- `git diff --stat`: 2 files — `bin/pos-media-ytsync` (+25/-3) and `DOC/AGENT_Context_Project.md` (+1/-1).
- The DOC change is only the hand-maintained line-count row for `bin/pos-media-ytsync` 1191→1213 (exactly matches the +22/-3 = +22 lines → 1213). ✓ expected regeneration-only change, no GEN-block drift.
- No changes to `parse_probe`, `classify_url`, registry write paths, download loop. ✓
- No new dependencies (uses jq which was already required). ✓
- `# POS:`, `# POS_CONFIG:`, `# POS_SUBCMDS:`, `# POS_FLAGS:` headers unchanged (diff shows no header hunk). ✓
- Executable bit preserved (git diff --stat shows mode unchanged, file is executable). ✓

[PASS]

## Step 4: Regression risk analysis

- `canonical_channel_url` is called ONLY inside `run_probe`, which is the single choke point for all probes (add explicit, add interactive, sync). The canonicalization is purely probe-time — the registry `S_URL` (stored original) and the `finish_add` stored URL are unchanged. ✓
- Playlist (`?list=`) and single-video (`?v=` / `youtu.be/`) URLs are classified non-channel by `classify_url` and bypass canonicalization entirely. ✓
- The `.entries[]` filter only affects what `collect_entries` records — existing playlist probes use `?list=` entries which carry `watch?v=` URLs and pass the filter. ✓
- The `_type=="video"` guard only changes the `else` branch (empty-entries fallback); the `n>0` branch (normal playlists/channels) is unaffected for entries that have valid URLs. Since the pre-fix script never had an `entries:[]` case that was functionally meaningful (it always fell into the single-object fallback populating bogus ids for playlist `_type` objects), the guard is strictly a correctness improvement.
- `run_probe` failure path (`rc != 0`) is unchanged; canonicalization happens before probe so the failure semantics for user/404/music URLs are unchanged.
- **`grab` flow:** `bin/pos-media-grab*` and `pos-media-grab` are separate tools; grep confirms no shared code path (only the run_probe/collect_entries functions in ytsync are touched, and grab doesn't invoke them).

[PASS]

## Step 5: Test harness review

Read `/tmp/opencode/ytsync-test/run-tests.sh` (132 lines) in full.

**Does it test what it claims?**

The harness:
1. Generates 6 inline fixture JSONs (tab-probe, video-tab, playlist, playlists-tab, video, empty-videos) — §1 (lines 21-45).
2. Stubs `common.sh`, `notify.sh`, and a recording fake `yt-dlp` — §2 (lines 48-67).
3. Truncates `bin/pos-media-ytsync` at the `# ── Argument dispatch ──` marker and sources it — §3 (lines 70-78).
4. Tests `classify_url` regression (7 checks) — §4.
5. Tests `canonical_channel_url` (16 checks) — §5.
6. Tests `collect_entries` filter against the fixtures (8 checks) — §6.
7. Tests `run_probe` records the canonical URL (1 check) — §7.

**Are the assertions meaningful or tautological?**

The `canonical_channel_url` checks call the function and compare actual output to expected — **behavioral, not tautological** (lines 95-110). If the function were missing, we get `fail: canonical_channel_url is not defined` (line 93).

The `collect_entries` checks set `PROBE_JSON` to a fixture, call `collect_entries`, and compare actual `ENTRY_IDS`/`ENTRY_TITLES` — **behavioral**. The filter's effect is verified: tab-probe → 0, video-tab → 2 with the right ids, playlists-tab → 0, playlist → 1, empty → 0. These are meaningful discriminations of the fix.

The `run_probe` check (line 127-128) exports a urllog and fixture, calls the real `run_probe` (via the stub yt-dlp), and asserts the yt-dlp received the canonical `/videos` URL. **Behavioral.**

The `classify_url` checks are regression guards that the fix didn't change URL classification — **meaningful** (they'd catch if heuristic changes broke the primary classification).

**Gaps in the harness:**
- It does NOT test the interactive-add flow end-to-end (only function-level canonical/probe/filter behaviors) — acceptable for a unit-style harness.
- It does NOT test a `/port`-style URL with query stripped and appended — a minor edge not covered by the 16 checks.
- It does NOT test an *uppercase* suffix (`@h/VIDEOS`) — which the implementation treats as non-whitelist and appends `/videos`. This matches the spec's stated case-sensitivity intent but the harness doesn't pin the behavior.
- It does NOT test a channel with explicit `/live` and a real live entry (`watch?v=` or `/live/<id>` URL shape). This is the NOTE from Step 2.3 — the filter may or may not handle a hypothetical `/live/<id>` URL shape.

**Cannot verify execution:** The sandbox blocks running the harness (bash execution deny). The Builder's reported `32 PASS / 0 FAIL` (17 logical checks × 2 check calls each in some cases producing more than 17 lines) is self-consistent with the harness structure (17 logical check blocks; each block emits PASS/FAIL lines; the harness counts the actual check() invocations which are more than 17 — the Builder counted 32). The claim "baseline 12 PASS / 5 FAIL on unfixed script" is a testable assertion I couldn't run here. Marked **UNVERIFIED (execution)** — Orchestrator should run it as part of gate verification.

[PASS — with unverified execution]

## Step 6: Verification / gate claims

Per the fixed read-only boundary I could not run `bash -n`, `make check`, `make lint`, or the live dry-run (bash execution is denied). These are the Builder's claims:

1. `bash -n bin/pos-media-ytsync` — [UNVERIFIED — needs Orchestrator]
2. harness `32 PASS / 0 FAIL` — [UNVERIFIED — needs Orchestrator]
3. `make gen/check/lint` green (`0 FAIL, 0 WARN`) — [UNVERIFIED — needs Orchestrator]
4. live dry-run `Resolved : 3Blue1Brown (channel · 151 videos)` + real titles — [UNVERIFIED — needs Orchestrator]
5. single-entry download proof (GlYgs6v2YfU) began streaming before 180s timeout — [UNVERIFIED — needs Orchestrator]

None of these claims are contradicted by evidence I can see. The DOC line-count (1191→1213) matches exactly with +22 lines in the script (§7.4 of the Builder's report). Static analysis shows `# POS:` header, `set -euo pipefail` (line 2), and the diff touches no other files.

**Mark the runtime claims PENDING** — the Orchestrator should run the gates + harness + dry-run to convert them from UNVERIFIED to FACT.

[PENDING]

## Step 7: Findings

**Finding 1 — SUGGESTED**
- Finding: `canonical_channel_url` appends `/videos` to `$u` (the full URL with any query) rather than to the query-stripped `path`. For a bare handle WITH a query but no tab (e.g. `@h?tab=foo`), the output is `@h?tab=foo/videos` — malformed, with `/videos` embedded in the query value. Impact is low (YouTube falls back to Videos on invalid tab values) but it is unclean.
- Severity: SUGGESTED
- Evidence: bin/pos-media-ytsync:195 — `printf '%s/videos' "$u"` after the query/fragment/trailing-slash stripping only on `path`.
- Relevant files/lines: bin/pos-media-ytsync:188-196
- Approved scope reference: Detective §4.1 (the spec's own code has this same construction — Builder matched it faithfully)
- Why it matters: Cosmetic edge; not spec-violating since the spec used the identical `$u`-append.

**Finding 2 — SUGGESTED**
- Finding: The `.entries[]` filter's URL test has no `youtube.com/live/` alternative. If a `/live` tab probe (when a channel IS live) ever returned live entries with a `youtube.com/live/<id>` URL shape, they would be silently dropped. Far more likely, live entries carry `watch?v=` URLs (still watchable), which would pass. No evidence of a regression.
- Severity: SUGGESTED
- Evidence: bin/pos-media-ytsync:403 — `test("watch\\?v=|youtu\\.be/|/shorts/")`; no `/live/` alternative.
- Relevant files/lines: bin/pos-media-ytsync:403
- Approved scope reference: Detective §4.3 — the filter kept shorts/streams deliberately; live was deemed out of scope and the `/live` URL fails probe gracefully when not live.
- Why it matters: Future-proofing; not a defect under any observed fixture or the spec's stated edge matrix.

**Finding 3 — NOTE**
- Finding: The uppercase-suffix (`@h/VIDEOS`) case does NOT leave the URL untouched as the spec's prose (§4.5, §168-171) describes. Because the whitelist match is case-sensitive, `@h/VIDEOS` → `@h/VIDEOS/videos` (append). The net runtime outcome is the same as the pre-fix world (yt-dlp errors on the bad tab → probe-fail → graceful notfound), so no regression. But the implementation deviates from the prose description in Detective §4.5.
- Severity: NOTE
- Evidence: bin/pos-media-ytsync:192 (case-sensitive `case` match) vs Detective line 171 ("`@h/VIDEOS` → untouched").
- Relevant files/lines: bin/pos-media-ytsync:192
- Approved scope reference: Detective §4.5 / line 171.
- Why it matters: A doc/spec prose vs code mismatch. The behavior is benign but should be reconciled in the fix record if this is preserved.

**Finding 4 — NOTE**
- Finding: The harness's `run_probe` check (line 127) sources the script in-band, but because it exports `YTSYNC_TEST_FIXTURE=video-tab.json`, the stub emits the fixture and `run_probe` exits 0. The check is meaningful but only asserts URL recording — it doesn't assert the probe result flow (parse_probe / collect_entries end-to-end). This gap is acceptable for a focused unit harness.
- Severity: NOTE
- Evidence: /tmp/opencode/ytsync-test/run-tests.sh:124-128
- Required verification: none — informational.

**Finding 5 — NOTE**
- Finding: The `@h?tab=foo` case (bare handle with query but no tab) is not pinned by the harness. It's a rare user input; the canonicalization's behavior is probable-but-untested.
- Severity: NOTE
- Evidence: run-tests.sh test matrix (lines 95-110) covers `@h/videos?view=0`, `@h/videos/`, bare `@h`, but not `@h?tab=foo`.
- Required verification: none — informational.

## Findings summary

No BLOCKING. No REQUIRED. 2 SUGGESTED + 3 NOTE.

## Verification verified vs unverified

**Verified by static evidence (FACT):**
- Spec conformance of the diff (all four elements implemented exactly).
- No scope creep / two files only.
- DOC line-count change is exactly the expected +22.
- No new dependencies, headers unchanged, executable bit preserved.
- `set -euo pipefail` intact (line 2).
- All `run_probe` callers benefit from the single integration point.
- Playlist/video URLs guaranteed untouched by classification.

**UNVERIFIED (needs state-changing execution — Orchestrator):**
- `bash -n` result.
- Harness execution (32 PASS / 0 FAIL claim).
- `make check` / `make lint` (`0 FAIL, 0 WARN` claim).
- Live `--dry-run` showing `Resolved : 3Blue1Brown (channel · 151 videos)`.
- Single-entry download proof.

## Scope compliance

- In-scope confirmed: all four spec elements implemented. ✓
- Out-of-scope found: none. The only extra beyond the literal spec prose is `releases|podcasts|search` in the suffix whitelist — these are valid channel tabs that correctly bypass `/videos`; not a deviation, just a completeness of the tab list.

## Remaining uncertainty

- Exact `/live/<id>` URL shape in a real live-tab flat-playlist probe (Finding 2) — untested, low risk.
- Query-without-tab URL canonicalization cleanliness (Finding 1).
- Execution claims (harness, gates, dry-run) require Orchestrator confirmation.

## Handoff

Status: **APPROVE_WITH_NOTES**

Reviewed work:
- uncommitted diff: bin/pos-media-ytsync (+25/-3), DOC/AGENT_Context_Project.md (1191→1213 line count only)
- spec: AgentsReport/detective/2026-09-04_ytsync-channel-handle.md
- implementation report: AgentsReport/builder/2026-09-04_ytsync-channel-handle-fix.md
- harness: /tmp/opencode/ytsync-test/run-tests.sh + fixtures

Approved scope / contract:
- Four spec elements (helper, run_probe integration, filter, fallback guard) — all present and exact.

Findings:
- SUGGESTED #1: query retained when appending `/videos` to bare-handle-with-query.
- SUGGESTED #2: filter lacks `/live/` URL alternative (low risk).
- NOTE #3: uppercase suffix behavior deviates from spec prose (benign).
- NOTE #4: harness coverage gaps (end-to-end flow, regex edge).
- NOTE #5: bare-handle-with-query not pinned by harness.

Verification verified:
- Static conformance of diff to spec. No scope creep. Single integration point. No regression paths.

Verification unverified (needs Orchestrator):
- bash -n, harness run, make check/lint, live dry-run (151 videos), single-entry download.

Scope compliance:
- In-scope: all. Out-of-scope: none.

Remaining uncertainty:
- Execution claims pending Orchestrator; `/live/<id>` URL shape untested; query edge cosmetic.

Recommended next agent:
- **Orchestrator**

Reason:
- The implementation is spec-conformant and no BLOCKING/REQUIRED defects were found. The remaining evidence gaps (execution of the harness, gates, and the live dry-run) are self-performing by the Orchestrator as the designated verification step in the AGENTS.md gate chain. If any claim fails at that point, hand to Builder for a scoped fix. No Builder fix is warranted from static evidence.

Changes made by Reviewer:
- Created this report under AgentsReport/reviewer/2026-09-04_ytsync-channel-handle-review.md
- No source/config/data file modified.
