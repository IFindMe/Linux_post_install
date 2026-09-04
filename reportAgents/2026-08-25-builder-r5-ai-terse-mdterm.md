# Builder R5 — `pos ai gemini ask` terse-by-default + terminal markdown rendering

## TL;DR
- Status: IMPLEMENTED — all gates green, 16/16 probes pass
- Files changed: `bin/pos-ai-gemini` (+105/-19 → 392 lines), `DOC/howto/ai.md`, `DOC/POS.md`, GEN regen (`DOC/AGENT_Context_Project.md`, `completions/pos.bash`)
- Flags added: `--full`; `--system` semantics now "replaces built-in terse prompt wholesale"
- Byte-compat proof: non-tty stdout md5 identical to pre-edit baseline (`bc3c8123…`, cmp clean)
- Gates: bash -n OK · `make gen` idempotent · `make check` OK · `make lint` = **0 FAIL, 0 WARN**

## Step 0: Baseline capture (byte-compat reference) [DONE]
- Pre-edit copy → `/tmp/opencode/r5/baseline-pos-ai-gemini`; mirror dir `/tmp/opencode/r5/base/{bin,lib→repo/lib}` so the fallback source chain resolves
- Stub curl (`/tmp/opencode/r5/stub/curl`): logs args + `--data` payload, writes URL/data to files, emits canned Gemini JSON fixture + `\n200\n` (emulating `--write-out`)
- Fixture markdown: ATX header, plain line, ```bash fence (2 lines incl. literal `**`), list with bold+inline code, `---` hr, `__bold__` tail

## Step 1: `bin/pos-ai-gemini` implementation [DONE]
- `DEFAULT_SYSTEM_PROMPT` constant (terse CLI wording from brief) — bin/pos-ai-gemini:17
- `# POS_FLAGS:` → `--model --session --system --full` — bin/pos-ai-gemini:5
- `FULL_MODE=0` global; `--full` case in flag parser — bin/pos-ai-gemini:366
- `cmd_ask`: effective prompt = `$SYSTEM_PROMPT` if set, else default unless `--full` (`--system` beats `--full`); reuses existing jq `systemInstruction` merge; output via `render_markdown "$out"` — bin/pos-ai-gemini:248-280
- `render_markdown()` (~55 lines w/ comments, zero deps): `[ ! -t 1 ]` → raw passthrough; graceful `command -v glow` probe (no `|| err` → lint-safe opportunistic use) → `glow -`; else awk renderer: fence toggle + 4-space indent + dim, ATX #1–4 → bold cyan (#'s stripped), `-/--/__` hr → 60-char dim rule, inline `` ` `` → yellow (backticks stripped), `**`/`__` → bold; unmatched tails preserved via rest accumulation; list markers untouched — bin/pos-ai-gemini:160-216
- `cmd_chat`: reply via `render_markdown` (spacing preserved); Telegram listener markdown-stripping path NOT touched
- usage(): Usage line, Options (`--full`, revised `--system`), new Notes block (default terse prompt / glow / raw-when-piped), examples updated
- Model resolution untouched (`resolve_model`): flag > `AI_GEMINI_MODEL` > `gemini-2.5-flash`

## Step 2: Probe results (stubbed curl, throwaway env) [DONE] — final-state rerun 16/16 PASS
- (a) no `--system`: payload `.systemInstruction.parts[0].text` == terse default AND url == `models/gemini-2.5-flash:generateContent` — PASS
- (b) `--system "CUSTOM9"`: payload == CUSTOM9 exactly (wholesale) — PASS
- (c) `--full`: `has("systemInstruction")` == false — PASS
- (d) tty render (via `script -qec` pty): header ESC[1;36m stripped of ##; fence lines ESC[2m + 4sp indent (literal `**` kept inside fences — verbatim by design); bold ESC[1m; inline code ESC[33m no backticks; hr → dim rule; plain lines/list markers intact; zero `##`/backtick leaks — PASS (found+fixed real awk bug: text between matches was dropped; caught because fixture had a matchless plain line)
- (e/h) non-tty byte-compat vs HEAD baseline: md5 `bc3c8123…` equal both sides, `cmp` clean, wc -c equal (163), stderr identical, stdin-piped ask same md5 — PASS
- (f) chat under pty with scripted input: reply rendered w/ ANSI, `/reset` → `[history cleared]`, `q` → `bye`, prompts intact — PASS
- (g) glow stub present → `GLOW_RENDERED:` path used; absent → built-in awk path — PASS
- (i) precedence matrix: unset → flash; env pro → pro; env pro + flag 1.5-pro → flag wins — PASS
- Extras: `--full` accepted before subcommand; `--system` overrides `--full` — PASS

## Step 3: Docs [DONE]
- `DOC/howto/ai.md`: flags paragraph (+`--full`, wholesale-replace wording), new "Terse by default, rendered on screen" section (default prompt, glow note, raw-when-piped byte-stability rule), table row + `--full` recipe
- `DOC/POS.md`: ask row (terse default, tty rendering vs raw non-tty bytes), chat row (rendered replies)

## Step 4: Gates [DONE]
- `bash -n bin/pos-ai-gemini` → clean
- `make gen` → regen OK; second run produced zero further drift (idempotent); expected deltas only: `_pos_flags[ai-gemini]+="--full"`, filetable row `pos-ai-gemini 311→392` (other tools' count rows resynced mechanically from other agents' pre-existing uncommitted edits — their files untouched by me)
- `make check` → `check-sync: OK`
- `make lint` (timeout 420s) → `0 FAIL, 0 WARN`
- Scope audit: my edits confined to `bin/pos-ai-gemini`, `DOC/howto/ai.md`, `DOC/POS.md` + GEN blocks; `features/*` (Telegram listener), `lib/*` untouched (pre-existing tree edits belong to other tasks)

REPORT_PATH: ./reportAgents/2026-08-25-builder-r5-ai-terse-mdterm.md
