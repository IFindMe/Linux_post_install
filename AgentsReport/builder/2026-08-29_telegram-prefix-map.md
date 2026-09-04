# Telegram listener: generic text-prefix → app map

**TL;DR:** The listener now routes any non-command message `<word> <text>` to a user-configurable command with `<text>` appended as ONE quoted argument — `opencode=opencode` turns "opencode check cpu" into `opencode "check cpu"`. Routing order per message: text-prefix map → built-in Gemini `ai` bridge → `/command` map → "Unknown command". `prefix` verb reworked to manage the map; `TELEGRAM_AI_PREFIX` is now set only via `pos config telegram`.

## Steps

- [DONE] Design — generalized the previous scalar AI-prefix into a full prefix→command map per the user's clarification ("each prefix call a app with pass 'text'"); kept the `/command` map and the Gemini bridge untouched, with the prefix map checked first so a mapped word can shadow `ai`.
- [DONE] Implement `bin/pos-communication-telegram-listener` (623→782):
  - `PREFIX_FILE="$CONFIG_DIR/telegram_prefixes.env"` (chmod 600, hot-reloaded per message like the command map).
  - `prefix_map_find(text)` — case-insensitive `^word[[:space:]](.*)$` (quoted-literal bash regex in scoped `nocasematch`); first file match wins; requires non-empty remainder; returns `command\x1fremainder`.
  - `prefix_map_set/del/show` — same mktemp+mv pattern as the map functions; words validated `[A-Za-z0-9][A-Za-z0-9_-]*`; commands `bash -n`-checked via `check_syntax` (fixed latent `set -e` abort: `errs="$(...)" || err ...`).
  - `run_and_reply(cmdline, msg_id, tmo, quiet)` — shared runner: `timeout <tmo> bash -c`, empty→`OK`, non-zero→`exit N`+output, `@quiet`→no reply. `/command` map uses 60s (unchanged), prefix map 120s.
  - `handle_message` — prefix bridge inserted after `/help|/start`, before the AI bridge; `/command` map block refactored onto `run_and_reply`.
  - `prefix` verb: bare = list + bridge word; `prefix <word> <command...>` = map; `prefix <word>` = show one; `prefix -r <word>` = remove. Dispatch `prefix) prefix_cmd "${@:2}"`.
  - `--status` lists prefix entries; usage() + header `# POS:` line updated.
- [DONE] Docs — POS.md listener rows + new Text-prefix map / AI bridge paragraphs; howto/communication.md text-prefix bullet; howto/ai.md trigger-word wording (now `pos config telegram`) + prefix-map/shadowing note; AGENT_Context regen via `make gen`.
- [DONE] AGENT_TODO.md Done entry appended (newest-last).
- [PENDING] Commit + push (next step after this report).

## Verification

- Routing harness `/tmp/prefix_map_routing_test.sh` — extracts the real listener functions (incl. new prefix map helpers + `run_and_reply`) with PATH stubs for `pos` and `opencode`; **27/27 PASS**:
  - ai-bridge regression: `ai hello` → gemini ask, `ai /reset` → sessions reset, no-prefix → Unknown.
  - `opencode check cpu` → app runs, remainder is ONE arg (`argc=1 arg1=<check cpu>`), output replied.
  - Case-insensitive `OpEnCoDe`; bare `opencode` and `opencode ` (trailing space) fall through to Unknown.
  - Mapped `ai` shadows the Gemini bridge and passes the remainder.
  - No false match on partial prefixes (`o` vs `opencode`).
  - `exit N` reply, empty→`OK`, `@quiet` suppression, `$TELEGRAM_CHAT_ID` expansion in templates.
  - `/command` map regression through `run_and_reply` (`/health`, `/failx` exit 2, `@quiet`, `/help` list, unknown).
- CLI verb suite (real tool, temp `CONFIG_DIR`): set / show / remove / remove-missing (rc 0) / invalid word (rc 1) / invalid cmd `if then` (rc 1, nice `ERROR:` instead of raw `set -e` abort) / update-existing / `@quiet` template accepted / `--status` listing.
- Dispatch smoke via `bin/pos`: nested `pos communication telegram listener prefix …` and flat `pos communication telegram-listener prefix -r …` both work; bare `prefix` lists.
- `pos config telegram` (temp dir) still renders `TELEGRAM_AI_PREFIX` with description.
- Gates: `bash -n` clean; `make gen && make check` OK; `make lint` 0 FAIL / 0 WARN.

## Notes / behavior choices

- Bare `<word>` (no trailing space) does NOT trigger a prefix app — falls through to the Gemini bridge / command map / Unknown, preserving the pre-existing `ai` edge behavior.
- Prefix apps run with the FULL remainder as one quoted argument (`printf '%q'`); a template wanting the text mid-line can place it anywhere since it is appended after the command.
- Because matching requires `<word><whitespace>`, two distinct map words can never both match one message — "first match wins" only matters for hand-edited files with unusual words; kept as documented file-order semantics.
- Text-prefix entries are NOT pushed to the bot command menu (`build_commands_json` reads only `MAP_FILE`) — they are text triggers, not `/`-commands.
- The old `prefix <word>` = set `TELEGRAM_AI_PREFIX` behavior is intentionally replaced; the word is set via `pos config telegram` (field already exists in the `telegram` scope) and displayed by bare `prefix` + `--status`.

**Status: COMPLETE** (pre-commit). Next: commit + push.