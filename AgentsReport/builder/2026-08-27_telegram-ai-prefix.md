# Builder Report — Configurable AI-Bridge Trigger Word for the Telegram Listener

**Date:** 2026-08-27
**Status:** COMPLETE — implemented, verified, committed (`e6fa0a4`), pushed

---

## TL;DR

- **Request:** make the Telegram listener's `ai ` → Gemini bridge prefix configurable ("like communication telegram-listener prefix").
- **Change:** new `TELEGRAM_AI_PREFIX` config (default `ai`) + new `prefix` verb on the listener; live (per-message) reload like the command map; also editable via `pos config telegram`.
- **Files:** `bin/pos-communication-telegram-listener` 566→623, `bin/pos-communication-telegram-sender` (config-scope field), `completions/pos.bash` (regen), `DOC/AGENT_Context_Project.md` (regen filetable row), `DOC/POS.md`, `DOC/howto/ai.md`, `AGENT_TODO.md`.
- **Verification:** function-level routing harness (green), CLI verb tests, dispatch smoke via `pos`, `pos config telegram` render, gates `0 FAIL, 0 WARN`.
- **Commit:** `e6fa0a4` — pushed (`4306a53..e6fa0a4`).

[DONE]

---

## 1. Design

- **Config seam:** `TELEGRAM_AI_PREFIX` in `telegram.env` (shared by sender + listener). The listener already had a generic `load_config`; the key needs no code to load. Added to the `telegram` `# POS_CONFIG:` scope (in the sender's header, which owns that scope) so `pos config telegram` renders/edits it — registry-driven, no config-ui code.
- **CLI verb:** `pos communication telegram listener prefix` → shows current word; `prefix <word>` → validates `[A-Za-z0-9][A-Za-z0-9_-]*` (one word, no spaces/pattern metachars, no leading `-` to avoid flag ambiguity), writes `TELEGRAM_AI_PREFIX=` to `telegram.env` (chmod 600, mktemp+mv, `grep -vE` old line). Registered via `# POS_SUBCMDS: prefix` → completions regenerate.
- **Hot reload:** like the command map (re-read per message), a new `ai_bridge_prefix()` reads `telegram.env` per message. Precedence: file > env var from `load_config` (daemon start) > default `ai`. No daemon restart needed after `prefix <word>`.
- **Matching:** literal, case-insensitive prefix followed by whitespace. `case` patterns cannot express "literal word + one space + case-insensitive", so the handler uses a scoped `shopt -s nocasematch` + quoted-literal `=~`: `^"$prefix"[[:space:]](.*)$` (quoted variable = literal; nocasematch covers `AI`/`Ai`/custom `BoT`…). Unset immediately to keep the rest of the handler case-sensitive.
- **Preserved behavior:** bare `ai` (no trailing space) never matched the original `^[Aa][Ii][[:space:]]` regex → still falls through to "Unknown command". `ai /reset` (or `<prefix> /reset`) clears the session. Usage/`Unknown command`/log lines now interpolate the actual prefix.

[DONE]

---

## 2. Files Changed

| File | Change |
|------|--------|
| `bin/pos-communication-telegram-listener` | `prefix_cmd()` (show/set/validate/write), `ai_bridge_prefix()` (hot-reload resolver), `handle_message` uses `$prefix` with scoped nocasematch + literal `=~`, `--status` shows `ai prefix:`, usage() documents `prefix`, `# POS_SUBCMDS: prefix`, updated header comments |
| `bin/pos-communication-telegram-sender` | `# POS_CONFIG:` telegram scope + `TELEGRAM_AI_PREFIX=:AI-bridge trigger word in the telegram listener (default ai)::ai` |
| `completions/pos.bash` | regen: `_pos_subcmds[communication-telegram-listener]="prefix"` |
| `DOC/AGENT_Context_Project.md` | regen filetable: listener row 566→623 |
| `DOC/POS.md` | listener table: two `prefix` rows; paragraph now says `<prefix>` (default `ai `) configurable via verb/config; corrected stale claim that AI errors reply "plus a `pos config ai` hint" — code replies `AI error: …` only |
| `DOC/howto/ai.md` | Telegram section: trigger word configurable, `<prefix> /reset`, reply-context wording; troubleshooting points at `prefix` verb |
| `AGENT_TODO.md` | dated Done entry |

[DONE]

---

## 3. Tests Performed

### Routing harness — `/tmp/ai_prefix_routing_test.sh`
Extracts the listener's real functions (`handle_message` + deps) via `sed`, routes messages through them with a PATH-stub `pos` (fixed: `timeout pos …` runs a child process, so a bash-function stub is invisible) and a stub `reply`.

| Case | Result |
|------|--------|
| `ai hello` → gemini ask (`--session telegram-123 --system … hello`), answer replied | ✅ |
| `AI Hello` → routed, prompt kept (case-insensitive) | ✅ |
| `ai` (no space) → **Unknown command** (preserved edge), no ask | ✅ |
| `ai ` (trailing space) → Usage reply | ✅ |
| `ai /reset` → `pos ai gemini sessions reset telegram-123`, "Memory cleared." | ✅ |
| `hello` → Unknown command (not ai-routed) | ✅ |
| `TELEGRAM_AI_PREFIX=bot`: `bot hi` → routed; `BOT Hi` → routed; `ai hi` → Unknown command | ✅ |
| `bot /reset` → sessions reset | ✅ |
| var removed → `ai back` routed again (hot-reload fallback) | ✅ |

### CLI verb — real script, temp CONFIG_DIR
| Test | Result |
|------|--------|
| `prefix` (no arg) → `AI bridge prefix: ai` + usage hint | ✅ |
| `prefix bot` → writes `TELEGRAM_AI_PREFIX=bot` to telegram.env, rc 0 | ✅ |
| `prefix` after set → `AI bridge prefix: bot` | ✅ |
| `prefix 'a b'` and `prefix 'a.b'` → rc 1, validation error | ✅ |
| `prefix 1ok` → accepted (leading digit allowed) | ✅ |
| `--status` → `ai prefix: <current>` | ✅ |
| `prefix ai` → back to default | ✅ |

### Dispatch + config UI
- `pos communication telegram listener prefix` and flat `pos communication telegram-listener prefix` both show the current prefix (repo `bin/pos` on PATH). ✅
- `pos config telegram` (temp dir) renders `TELEGRAM_AI_PREFIX` with its description. ✅

### Gates
`bash -n` ×2 · `make gen` idempotent · `make check` OK · `make lint` 0 FAIL / 0 WARN. ✅

[DONE]

---

## 4. Notes / Remaining Risks

- **Matrix listener untouched** — it has its own hard-coded `ai …` bridge (session `matrix-<room>`); the same treatment is a possible follow-up if wanted.
- The daemon still loads `TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHAT_ID` once at start (unchanged); only the prefix hot-reloads.
- A prefix change applies to ALL chats the listener serves (there is one owner chat by design).
- Literal prefix matching means a prefix containing regex metacharacters would be matched literally (quoted), but validation restricts to word chars for predictability.

[DONE]

---

**Status: COMPLETE.** The `ai ` trigger is now `TELEGRAM_AI_PREFIX` (default `ai`), configurable via `pos communication telegram listener prefix <word>` or `pos config telegram`, applied live.