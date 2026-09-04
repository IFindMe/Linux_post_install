# Builder R5b — `pos ai gemini`: `--last` log attach · troubleshooting prompt clause · persistent `default` session

## TL;DR
- Status: IMPLEMENTED — all gates green, 46/46 probes pass × 3 consecutive runs (+ final rerun)
- Files changed: `bin/pos-ai-gemini` (+86/−38 vs R5 baseline → 440 ln), `DOC/howto/ai.md`, `DOC/POS.md`, GEN regen (`DOC/AGENT_Context_Project.md`, `completions/pos.bash`)
- Flags added: `--last` (ask-only; attaches newest dispatcher log tail ≤4096 chars, END kept, `[…truncated…]` marker)
- Behavior changes: default terse prompt gained diagnose-pasted-output clause; `ask`/`chat` without `--session` now persist to session `default` (`pos ai gemini sessions reset default`)
- Gates: bash -n OK · `make gen` idempotent (md5 -c OK) · `make check` OK · `make lint` = **0 FAIL, 0 WARN**

## Step 1: Recon + baseline [DONE]
- R5 report read; baseline snapshot of current tree → `/tmp/opencode/r5b/baseline-pos-ai-gemini` (392 ln; git HEAD ≠ baseline because R5 itself is uncommitted — all diffs here are measured against the working-tree baseline).
- Dispatcher logging facts: LOG_DIR=`~/.local/share/linux_post_install/logs` (bin/pos:254), per-cmd logs `<ts>_pos_<cmd>.log` (bin/pos:257), MAIN_LOG `pos.log` = invocation index only (must be excluded or it always wins). `ai-gemini` IS in INTERACTIVE_CMDS (bin/pos:261) → `pos ai gemini ask --last` never creates its own output log; "newest non-empty previous log" is well-defined.
- Bridge call sites (untouched by design): `bin/pos-communication-{telegram,matrix}-listener` call `ask --session <telegram-N|matrix-room> --system "$AI_SYSTEM"` and `sessions reset <name>`.

## Step 2: Feature A/B/C implementation in `bin/pos-ai-gemini` [DONE]
- A: `# POS_FLAGS:` += `--last` (line 5); `LAST_MODE` global + `--last` case in parser + post-parse guard "`--last` only applies to ask"; `DISPATCH_LOG_DIR`, `LAST_LOG_MAX_BYTES=4096` constants; `newest_pos_log()` (newest non-empty `*.log`, excludes `/pos.log$`); `last_log_context()` (END kept via `tail -c 4096`, leading `[…truncated…]` when file >4096 bytes, iconv `-c` sanitize for byte-cut multibyte); injection in `cmd_ask` AFTER question text as `\n\n[last command output:]\n<ctx>`; no-log error carries both hints (run through pos / pipe example).
- B: `DEFAULT_SYSTEM_PROMPT` extended with the diagnose-pasted-output clause ("…may paste a problem, error, or command output: diagnose it from that and lead with the fix command(s)").
- C: `SESSION="default"` initial value; stateless branches removed from `cmd_ask` (session_load/push/save unconditional) and `cmd_chat` (banner/saves unconditional, `/reset` persists default too); sessions list/reset need no special-casing (plain `<name>.json`).
- Probe-harness bug found & fixed in tool during verification: same-second log files tie-flake under `ls -t` → `newest_pos_log` now sorts name-descending (`LC_ALL=C sort -r`) since bin/pos embeds a zero-padded sortable `<ts>` prefix; deterministic across runs.
[DONE]

## Step 3: Probes (stub curl, throwaway HOME) [DONE] — 46/46 PASS × 3 consecutive runs
Harness: `/tmp/opencode/r5b/{stub/curl,probes.sh,env.sh}` — stub captures args/url/data per request, emits canned Gemini JSON (`--write-out` emulation); capture dir OUTSIDE fake HOME (earlier harness bug: fresh_home nuked it).
- (a) newest log injected tail-first: question+`\n\n[last command output:]\n[…truncated…]\n`+`tail -c 4096` of NEWEST log; pos.log excluded; END kept (line 500 present); old log unused; small log → full content, NO marker; exact byte equality asserted — PASS
- (b) no logs / all-empty logs → rc≠0, hint names log dir AND shows `failing-cmd 2>&1 | pos ai gemini ask …` pipe example — PASS
- (c) two consecutive plain asks: req#2 payload = 3 contents, [0]=turn-one user text, [1]=stored model reply; `default.json` ends at 4 turns — PASS
- (d) `--session work` payload has 1 content while default keeps its 4 — PASS
- (e) `sessions` lists `default N turns`; `reset default` rc=0, file gone, other sessions kept — PASS
- (f) piped REPL without flags: banner `session: default`, payload user turn correct, saved 2 turns to default.json — PASS
- (g) prompt matrix: plain ask → systemInstruction contains new clause AND terse core; `--full` → no systemInstruction key; `--system CUSTOM9` → exactly CUSTOM9 — PASS
- (h) precedence intact: unset→gemini-2.5-flash; config→gemini-1.5-pro; flag beats config→gemini-2.0-flash — PASS
- (i) non-tty stdout byte-exact vs fixture (cmp clean) — PASS
- (j) bridge names untouched: `--session telegram-123456789 --system BRIDGE_SYS` passthrough + len-1 fresh session; `matrix-!room_x:y.org` sanitized to `matrix-_room_x_y_org.json`; `sessions reset telegram-…` works; bridge call sites unmodified (grep) — PASS
- Extras: `--last`+`--session`+`--system` combine; `--last` rejected for chat/models ("only applies to ask", rc≠0); flag order-free before subcommand; name-desc beats newer mtime (ts prefix is the clock) — PASS

## Step 4: Docs [DONE]
- `DOC/howto/ai.md`: table reworked (ask row = persistent `default`; new `--last` row; sessions row shows `reset default`), shared-flags paragraph += `--last`, terse section += diagnose-pasted-output clause, new persistence paragraph (40-turn cap, `sessions reset default`), recipes += `--last` / pipe-hint / reset-default, "How it works" += session-file mechanics, Telegram section notes bridge sessions are independent of terminal `default`.
- `DOC/POS.md`: ai rows updated — purpose line (ask no longer "one-shot"), ask row (default session + cap, extended prompt wording, `--last`), chat row (persisted session file), new explicit `sessions` row.
- GEN regen deltas (mine): `_pos_flags[ai-gemini]` += `--last`, filetable row `pos-ai-gemini 392→440`. Gen also mechanically resynced other agents' pre-existing uncommitted edits (`pos-docker-vbox` count row + flags, `pos-share-*` count rows) — their files untouched by me (same phenomenon R5 documented).

## Step 5: Gates [DONE]
- `bash -n bin/pos-ai-gemini` → clean
- `make gen` → OK; second run byte-identical (`md5sum -c` on AGENT_Context_Project.md + completions/pos.bash) → idempotent
- `make check` → `check-sync: OK`
- `make lint` (timeout 420s ≥ 300s required) → `0 FAIL, 0 WARN`

## Scope compliance
- Edits confined to: `bin/pos-ai-gemini`, `DOC/howto/ai.md`, `DOC/POS.md`, GEN outputs. No lib changes, no commits, no other files touched by me. `AGENT_TODO.md` deliberately untouched (outside the allowed-files list).

## Remaining risks / notes
- `--last` truncation counts bytes (`tail -c`), not characters — spec said "≤4096 chars"; multibyte logs may cut slightly under 4096 chars; partial multibyte heads are dropped via `iconv -c` when available.
- Session names sanitize through `[A-Za-z0-9_-]` (pre-existing behavior); `default` needs no special-casing anywhere.
- Two same-second pos runs produce same-timestamp log names; newest is then the lexicographically-latest command name — acceptable and deterministic.

REPORT_PATH: ./reportAgents/2026-08-25-builder-r5b-last-default-session.md
