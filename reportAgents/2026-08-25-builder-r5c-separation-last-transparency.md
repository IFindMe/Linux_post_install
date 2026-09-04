# Builder R5c — `pos ai gemini`: tty answer separation · `--last` stderr transparency + staleness guard

## TL;DR
- Status: IMPLEMENTED — both fixes in, all gates green, probes 34/34 × 4 consecutive runs (incl. post-cleanup rerun)
- Files changed: `bin/pos-ai-gemini` (440 → 489 ln; +66/−17 vs R5b baseline), `DOC/howto/ai.md`, GEN regen (`DOC/AGENT_Context_Project.md` row 440→489 via make gen, completions byte-identical)
- Fix 1: on tty, rendered answers now start after one blank line and end with exactly one newline (ask + chat); non-tty path untouched — stdout md5-identical pre/post edit for plain AND `--last` runs
- Fix 2: `--last` prints STDERR-only `[i] attaching last pos output — <basename> (<age>)` + first-meaningful-line preview; `[!]` staleness warning when log >60 min old; `human_age()` helper (`just now`/`Nm`/`Nh`/`Nd`)
- Gates: bash -n OK · `make gen` idempotent (consecutive-run md5s equal) · `make check` OK · `make lint` **0 FAIL, 0 WARN** (2m13s)

## Scope (from brief)
- Allowed files: `bin/pos-ai-gemini`, `DOC/howto/ai.md`, GEN regen. No lib changes, no commits.
- Out-of-scope changes made: none. (Working tree carries other agents' pre-existing uncommitted work — `bin/pos-docker-vbox`, share clients, `lib/common.sh`, several docs — untouched by me; GEN files resync their rows mechanically as R5b already documented.)

## Step 0: Recon + baseline harness [DONE]
- Read R5b report + tool (440 ln) + `lib/common.sh` helpers (`err/warn/ok`; colors auto-off on non-tty) + `bin/pos:253-291` logging (per-run logs are pure tool output via tee — no header lines, so "first meaningful line" = first non-blank line).
- `glow` absent on this box → built-in awk renderer is the deterministic tty path; util-linux `script(1)` available for pty probes.
- Baseline snapshot → `/tmp/opencode/r5c/baseline/`; stub `curl` harness (logs sanitized args per request, emits canned Gemini JSON byte-exactly like real curl's `--write-out $'\n%{http_code}'`); throwaway HOMEs; capture dirs outside fake HOMEs.
- Pre-edit captures: `ask hello` and `ask --last …` non-tty stdout = `ANSWER_1\n` (md5 `88599de331dcbdef3bcf5555b95551ed`), stderr empty.
[DONE]

## Step 1: Fix 1 — tty answer separation [DONE]
- `render_markdown` (bin/pos-ai-gemini:252-316): non-tty branch untouched (`printf '%s\n'`). TTY branch now captures renderer output through `$()` (strips any trailing newlines) then `printf '\n%s\n' "$rendered"` → exactly one leading blank line + exactly one trailing newline, identical for glow and awk paths.
- Gotcha A: wrapping the awk program in `"$( )"` broke parsing — its backtick regexes were parsed as legacy command substitution inside `$()`. Fix: awk program hoisted to a single-quoted local `prog`, passed as `awk "$prog"` (bin/pos-ai-gemini:266-314).
- Gotcha B: first draft made chat's pre-answer `printf '\n'` tty-conditional; the pty probe disproved it — chat's bare `> ` prompt has NO trailing newline, so that `\n` merely closes the prompt line and the renderer's blank line is what becomes the visible gap. Reverted to unconditional `printf '\n'` with an explanatory comment (bin/pos-ai-gemini:341-345). Net effect: tty chat gains the visible separator; non-tty chat bytes unchanged (probe byte-exact).
[DONE]

## Step 2: Fix 2 — `--last` transparency + staleness guard [DONE]
- New global `LAST_LOG_STALE_SECS=3600` (bin/pos-ai-gemini:20).
- `human_age()` (bin/pos-ai-gemini:157-165): seconds → `just now` / `Nm` / `Nh` / `Nd`, negative clamp for clock skew.
- `last_log_annotate <file>` (bin/pos-ai-gemini:167-184), STDERR only:
  - always: `[i] attaching last pos output — <logfile-basename> (<human age>)`
  - preview: `[i]   "<first non-blank line, %.100s>"` (grep `-m1 '[^[:space:]]'`)
  - stale (>60 min): `[!] that log is <age> old and may not match your current problem. For a FRESH failure of any command:  failing-cmd 2>&1 | pos ai gemini ask "what happened"`
- Gotcha C: first draft recorded the resolved path in a global set inside `last_log_context` — dead on arrival because the function runs in a command substitution (subshell); annotation then `stat`ted an empty string. Fix: resolve once in `cmd_ask` via `newest_pos_log`, pass the file explicitly to `last_log_annotate` and `last_log_context "$file"` (signature change, single internal caller) (bin/pos-ai-gemini:327-333).
- Annotation fires right after resolution, before the network call. Error path when no log exists unchanged (message + rc≠0).
- usage() `--last` paragraph extended: stderr note + age + >60 min staleness hint + pipe example (bin/pos-ai-gemini:47-52).
[DONE]

## Step 3: Probes — stub curl + fixture logs, throwaway env; 34/34 PASS × 4 consecutive runs [DONE]
Harness: `/tmp/opencode/r5c/{stub/curl,capture-baseline.sh,probes.sh}`. Two harness bugs found & fixed during verification (runcap wiped shared capture dirs between requests; age-token grep expected `( 1h)` instead of `(1h)`) — neither masked a tool bug.
- **md5 proof (b)**: pre-edit `b1_plain.stdout`/`b2_last.stdout` vs post-edit `n1/n2` — all four `88599de331dcbdef3bcf5555b95551ed` (plain and `--last`, byte-identical). Plain-run stderr still empty. Piped chat REPL bytes unchanged. PASS
- **(a) tty** (pty via `script -qec`, CRLF-stripped): ask transcript == `\nANSWER_1\n` EXACTLY (one leading blank, one trailing newline). Chat shows exactly one visible blank between prompt and reply, transcript compact (no runaway blanks). PASS
- **(c) transparency**: stderr carries exactly the two `[i]` lines — basename `20260825_120000_pos_media_mp3.log`, `(just now)`, preview `"pos media mp3 https://example.com/song.mp3"`; stdout pure answer only; nothing else on stderr. PASS
- **(d) staleness boundaries**: 59 min → `(59m)`, no `[!]`; 61 min → `(1h)` + exact `[!]` text incl. pipe hint; 2 h → `(2h)`+warn; 3 d → `(3d)`+warn. PASS
- **(e) error path**: no logs dir → rc≠0, full original message + `failing-cmd 2>&1 | pos ai gemini ask how do I fix this` hint intact. PASS
- **(f) R5b regressions**: default-session accumulation (req#2 contents = user/model/user with stored ANSWER_1; default.json = 4 turns); prompt precedence (plain → terse+diagnose systemInstruction; `--full` → key absent; `--system CUSTOM9` → exactly CUSTOM9); model matrix (unset → gemini-2.5-flash; config → m_cfg; flag beats config → m_flag); `--last` rejected for chat ("only applies"); `sessions reset default` removes file, rc=0. PASS
[DONE]

## Step 4: Docs [DONE]
- `DOC/howto/ai.md`: table row `--last` += "(stderr notes which log + staleness warning)"; shared-flags paragraph += which-log/age/staleness note + "stdout stays pure answer"; rendering paragraph += "separated from your prompt line by one blank line" + explicit "no added blank lines" for pipes; recipe bullet += stderr attachment note + `[!]` staleness guidance pointing to the pipe-fresh recipe.
[DONE]

## Step 5: Gates [DONE]
- `bash -n bin/pos-ai-gemini` → clean
- `make gen` → OK; consecutive runs byte-identical (`20702ff8…` AGENT_Context_Project.md, `204382bca…` completions/pos.bash) → idempotent; filetable row auto-resynced to actual `wc -l` (489)
- `make check` → `check-sync: OK`
- `make lint` (timeout 600s ≥ 300s required) → **0 FAIL, 0 WARN**
[DONE]

## Diff stats
- `bin/pos-ai-gemini`: 440 → 489 ln (+66/−17 vs R5b working-tree baseline)
- `DOC/howto/ai.md`: 3 paragraphs + table row + recipe updated (+53/−11 vs git HEAD; file had no other agents' pending edits)
- GEN: `DOC/AGENT_Context_Project.md` ai-gemini count row resynced by `make gen`; `completions/pos.bash` unchanged by me

## Scope compliance
- Edits confined to `bin/pos-ai-gemini`, `DOC/howto/ai.md`, GEN outputs. No lib changes, no commits, no other files touched. `AGENT_TODO.md` untouched (outside allowed list).

## Remaining risks / notes
- Staleness uses file mtime; a log touched by anything else (e.g. manual `touch`) resets freshness — acceptable for its purpose.
- Preview truncates at 100 chars via printf `%.100s`; exotic multibyte splits at the cut are cosmetic-only (stderr).
- Chat-on-tty now emits one more newline before replies than R5b (the intended visible separator); non-tty chat is byte-identical to before.

REPORT_PATH: ./reportAgents/2026-08-25-builder-r5c-separation-last-transparency.md
