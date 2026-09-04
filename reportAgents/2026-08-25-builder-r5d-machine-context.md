# Builder R5d — `pos ai gemini`: machine-context clause in the built-in default prompt

## TL;DR
- Status: IMPLEMENTED — clause live in the built-in default ask prompt; gates green; probes 33/33 × 2 consecutive runs
- Files changed: `bin/pos-ai-gemini` (489 → 565 ln, +79/−3 vs R5c state), `DOC/howto/ai.md` (+2 ln: one sentence), GEN regen via `make gen` (ai-gemini row resynced to 565; completions byte-identical)
- Clause: `Machine context (answers must fit this box): <host>, <distro>, kernel <rel>, <arch>.` — appended only when composing the DEFAULT prompt (no `--system`, no `--full`); omitted entirely when nothing resolves
- Collection: one `hostnamectl status` call preferred; `/etc/os-release` + `uname -sr/-m` fallback/complement; every source optional, never errors; ANSI/control chars stripped, whitespace collapsed, single line ≤2 lines total
- Gates: bash -n OK · `make gen` idempotent (consecutive md5s equal) · `make check` OK · `make lint` **0 FAIL, 0 WARN** (1m25s)
- Probes (a)–(h): **33 PASS, 0 FAIL**, rerun stable

## Scope (from brief)
- Allowed files: `bin/pos-ai-gemini`, `DOC/howto/ai.md` (one sentence), GEN regen. No commits.
- Out-of-scope changes made: none. (`AGENT_TODO.md` untouched — outside allowed list, matching R5c precedent. Working tree carries other agents' pre-existing uncommitted work — `bin/pos-docker-vbox`, share clients, `lib/common.sh`, several docs — untouched.)

## Step 0: Recon + baseline harness [DONE]
- R5c report + tool read. Default-prompt composition is in `cmd_ask`; chat never uses the built-in prompt → change is ask-only.
- DEV.md §"Testing tools that need root/systemd/missing deps" sanctions env-overridable path seams for system config locations (`SMB_CONF`, `EXPORTS_FILE`, …; "don't advertise it in usage()") → added read-only seam `OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"` so os-release fixtures are probeable without touching the real file.
- Real box: hostnamectl present/working (Debian 13 trixie); lint classes checked — read-only `/etc` use triggers no write-seam WARN; no new flags/subcmds/config keys → completions expected byte-stable (confirmed).
- Harness `/tmp/opencode/r5d/`: stub curl (captures args + `--data` body per request; canned `ANSWER_<n>` JSON byte-exactly incl. `\n200`), fixture dirs per scenario (Debian-clean / Ubuntu-noisy hostnamectl, hostnamectl-exit-7, uname ok/fail, os-release Debian-PRETTY_NAME / Ubuntu-NAME+VERSION_ID, restricted-PATH symlink dir), shared `harness.sh`.
- Pre-edit baselines (stub curl, throwaway HOME): plain `ask hello` stdout = `ANSWER_1\n` md5 `88599de331dcbdef3bcf5555b95551ed`, stderr empty, rc 0 — matches R5c's recorded md5; systemInstruction = base prompt only; `--full` body has no systemInstruction key.
[DONE]

## Step 1: Implementation [DONE]
- `mc_clean` (stdin→stdout): strips ANSI CSI sequences, collapses whitespace runs to single spaces, deletes control chars via `tr -d '\000-\010\013-\037\177'`, trims both ends. Keeps UTF-8 letters intact.
  - Gotcha A: GNU sed does not support `\xHH` escapes inside `[bracket expressions]` — first draft's `[\x00-\x08…]` failed ("Invalid range end") and silently emptied every value (clause vanished on the real box). Fixed by moving control-char deletion to `tr -d`; sed keeps CSI-strip + collapse only.
- `machine_context()` prints the clause or nothing:
  - Preferred: one `hostnamectl status` call; colon-key parsing of Static/Transient hostname / Operating System / Kernel / Architecture (whitespace-insensitive keys).
  - Fallback/complement: `$OS_RELEASE_FILE` sourced in a subshell (vars stay local) — PRETTY_NAME, else `NAME (VERSION_ID)`; `uname -sr`/`uname -m` fill gaps; `"Linux "*` prefix stripped from kernel AFTER cleaning.
  - Gotcha B: hostnamectl values carry a leading space (` Linux …`), so normalizing pre-clean never matched — normalization moved after `mc_clean`.
  - Gotcha C: `${pieces[*]}` joins with the FIRST IFS char only (`IFS=', '` yields `,`) — replaced with an explicit incremental `, `-join.
  - Errexit-safe throughout (`|| true` guards, no failing AND-list as last statement).
- Wiring in `cmd_ask`: `system="$DEFAULT_SYSTEM_PROMPT$mc"` where `mc=" $(machine_context)"` only when `--system` unset and not `--full`. Semantics preserved exactly: `--system` replaces wholesale (no clause), `--full` drops the entire built-in prompt including machine facts, empty collection ⇒ base prompt unchanged. Chat untouched.
- Real-box smoke: `Machine context (answers must fit this box): lattepanda, Debian GNU/Linux 13 (trixie), kernel 6.12.94+deb13-amd64, x86-64.` — single line, 122 chars.
[DONE]

## Step 2: Docs [DONE]
- `bin/pos-ai-gemini` usage() Notes paragraph extended: built-in prompt ends with one machine-context line (hostname, distro, kernel, arch detected on this box); `--system` replaces wholesale, `--full` drops it all.
- `DOC/howto/ai.md` §"Terse by default" — the one allowed sentence: machine-context line (hostname/distro/kernel/arch detected on this box) so answers match the actual machine; `--system` swaps wholesale; `--full` drops it.
[DONE]

## Step 3: Gates [DONE]
- `bash -n bin/pos-ai-gemini` → clean (489 → 565 ln)
- `make gen` → OK; consecutive runs byte-identical (AGENT_Context_Project.md `b55c8677…`, completions `204382bc…` unchanged from pre-edit) → idempotent; ai-gemini row resynced 489→565 automatically
- `make check` → `check-sync: OK` (re-run again after all edits)
- `make lint` (timeout headroom ≥300s required) → **0 FAIL, 0 WARN** (1m24s)
[DONE]

## Step 4: Probes (a)–(h) — 33 PASS, 0 FAIL × 2 consecutive runs [DONE]
Harness bugs found & fixed during verification (none masked a tool bug): PATH leakage between cases broke later cases ((b2)'s restricted PATH starved the harness of coreutils; (a2) reused (a1)'s fixture dir) — fixed with per-case `TOOL_PATH` consumed inside a subshell; capture-dir wipe on shared capname ((f1) lost req_1) — one cap dir per request; stub-seq restart made req_2 live at index 1 in its own dir; missing `mkdir` symlink in the restricted fixture (session_save, bin/pos-ai-gemini:212).
- (a1) Debian hostnamectl fixture → request JSON systemInstruction ends `… Machine context (answers must fit this box): hostdeb, Debian GNU/Linux 12 (bookworm), kernel 6.1.0-18-amd64, x86-64.` PASS
- (a2) noisy Ubuntu fixture (ANSI colors, emoji, tabs, CRLF, doubled spaces) → cleaned exact values `host-ubu, Ubuntu 24.04.2 LTS, kernel 6.8.0-52-generic, x86-64.` PASS
- (b1) hostnamectl exits 7 → os-release Ubuntu fixture (NAME+VERSION_ID → `Ubuntu (24.04)`) + REAL uname values. PASS
- (b2) hostnamectl truly absent (restricted PATH, no systemd utils) → PRETTY_NAME Debian fixture + real uname; rc=0 under restricted PATH. PASS
- (c) all sources missing (hostnamectl fails, OS_RELEASE_FILE=/nonexistent, uname fails) → NO clause, systemInstruction == base prompt exactly, body valid JSON with user turn, stdout ANSWER_1, rc 0. PASS
- (d) `--system CUSTOM9` with fixtures present → systemInstruction exactly `CUSTOM9`, no clause substring. PASS
- (e) `--full` → `.systemInstruction` null (key absent), rc 0. PASS
- (f1) default-session double ask → both requests carry the clause; saved session JSON has 4 turns user/model/user/model and contains NO "Machine context" anywhere (clause lives in systemInstruction, not turns). PASS
- (f2) `--session work` carries the clause; work.json created. PASS
- (f3) `ask --last` → stderr annotation present, log ctx appended to user turn only, clause still intact in systemInstruction. PASS
- (g) plain non-tty ask post-edit stdout md5 == pre-edit `88599de331dcbdef3bcf5555b95551ed`, byte-identical (`cmp`), stderr empty. PASS
- (h) whitespace hygiene on the noisiest source: no newline/tab/CR, no double spaces, trimmed ends, exact clause suffix. PASS
[DONE]

## Diff stats (vs R5c working-tree state)
- `bin/pos-ai-gemini`: 489 → 565 ln (+79/−3): seam constant, mc_clean + machine_context (~50 ln incl. comments), cmd_ask wiring, Notes paragraph, DEFAULT_SYSTEM_PROMPT comment
- `DOC/howto/ai.md`: 155 → 157 ln (one sentence, wrapped)
- GEN: `DOC/AGENT_Context_Project.md` ai-gemini row resynced by `make gen`; `completions/pos.bash` byte-identical

## Scope compliance
- Edits confined to `bin/pos-ai-gemini`, `DOC/howto/ai.md`, GEN outputs (via make gen). Out-of-scope changes: none.

## Remaining risks / notes
- `OS_RELEASE_FILE` is an internal test seam per DEV.md convention — deliberately not documented in usage().
- If `/etc/os-release` exists but defines neither PRETTY_NAME nor NAME, the distro piece is simply omitted (kernel/arch/host still compose).
- Clause adds ~120 chars to each default ask request payload; token cost negligible, session storage unaffected.
- `hostnamectl` on systems without systemd usually still works via systemd's dbus-less fallback or fails cleanly — both paths probed (exit-7 stub + true absence).
- Chat intentionally unchanged (it never had a built-in default prompt; only `--system` applies there).

REPORT_PATH: ./reportAgents/2026-08-25-builder-r5d-machine-context.md
