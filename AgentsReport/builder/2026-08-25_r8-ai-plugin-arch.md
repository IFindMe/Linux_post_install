# Builder Report — R8: AI Provider-Agnostic Architecture

## TL;DR

- **Status:** IMPLEMENTED
- **Files changed:** 5 new, 8 modified, 0 deleted
- **New files:** `bin/pos-ai` (642 ln), `lib/ai-providers/gemini.sh` (59 ln), `lib/ai-providers/openrouter.sh` (59 ln)
- **Overwritten:** `bin/pos-ai-gemini` (596→7 ln, thin forwarder), `bin/pos-ai-openrouter` (597→7 ln, thin forwarder)
- **Modified:** `bin/pos`, `install.sh`, `config/ai.env`, `DOC/howto/ai.md`, `DOC/POS.md`, `DOC/HOWTO.md`, `DOC/AGENT_Context_Project.md`, `completions/pos.bash`, `lib/pos-ai-hook.sh`
- **Gates:** bash -n OK, make gen OK, make check OK, make lint 0 FAIL / 0 WARN
- **Probes:** 22/22 pass (all probes a–n verified)

---

## Step 1: Provider adapters

**[DONE]** `lib/ai-providers/gemini.sh` (59 lines) — Gemini adapter implementing `provider_name()`, `provider_default_model()`, `provider_generate()` (converts OpenAI `messages` → Gemini `contents`), `provider_models_list()`.

**[DONE]** `lib/ai-providers/openrouter.sh` (59 lines) — OpenRouter adapter implementing the same interface; sends `messages` directly to OpenAI-compatible API.

## Step 2: Main tool

**[DONE]** `bin/pos-ai` (642 lines) — Provider-agnostic main tool with:
- Unified `# POS:` header (`ai ask`, subcommands: ask/chat/sessions/capture/models/providers)
- `--provider` flag + `AI_PROVIDER` env/config resolution
- Unified `AI_API_KEY` with provider-specific fallback (`AI_GEMINI_API_KEY` → `OPENROUTER_API_KEY`)
- Unified `AI_MODEL` with provider-specific fallback
- `AI_SYSTEM_PROMPT` config support (between `--system` and built-in)
- Universal session format (OpenAI `messages`) with auto-migration from old Gemini `contents` format
- `cmd_providers()` — new subcommand listing providers + config status
- All shared logic from both originals (render_markdown, machine_context, --last, capture, sessions)

## Step 3: Backward compat forwarders

**[DONE]** `bin/pos-ai-gemini` (7 lines) — `exec pos ai --provider gemini "$@"`
**[DONE]** `bin/pos-ai-openrouter` (7 lines) — `exec pos ai --provider openrouter "$@"`

Both include `-h|--help` passthrough for lint compliance.

## Step 4: Install + dispatcher updates

**[DONE]** `install.sh` — Added `ai-providers/` directory copy to `/usr/local/bin/ai-providers/`
**[DONE]** `bin/pos` — Added `ai` to `INTERACTIVE_CMDS`

## Step 5: Config + doc updates

**[DONE]** `config/ai.env` — Updated template with unified + legacy keys
**[DONE]** `DOC/howto/ai.md` — Full rewrite reflecting unified architecture
**[DONE]** `DOC/POS.md` — Unified ai section (replaces separate gemini/openrouter sections)
**[DONE]** `DOC/HOWTO.md` — Updated ai.env table row
**[DONE]** `DOC/AGENT_Context_Project.md` — Updated ai.env description + Common Tasks row
**[DONE]** `completions/pos.bash` — Regenerated (make gen)
**[DONE]** `lib/pos-ai-hook.sh` — Updated comment references

## Step 6: Gates

**[DONE]** `bash -n` — All 5 new/changed files pass
**[DONE]** `make gen` — Idempotent (no drift)
**[DONE]** `make check` — OK (check-sync passes)
**[DONE]** `make lint` — 0 FAIL, 0 WARN

## Step 7: Verification probes

**[DONE]** All 22 probes pass:
- (a) gemini adapter calls correct API endpoint ✅
- (b) openrouter adapter calls correct API + Bearer auth ✅
- (c) `--provider` flag overrides `AI_PROVIDER` config ✅
- (d,e) backward compat forwarders route correctly ✅
- (f) `--system` overrides built-in; `AI_SYSTEM_PROMPT` from config; `--system` overrides config; `--full` drops all ✅
- (g) `AI_API_KEY` precedence over provider-specific; fallback works; error on missing key ✅
- (h) `--model` flag; `AI_MODEL` config; `AI_GEMINI_MODEL` legacy fallback; provider default model ✅
- (i) Session migration: old `contents` format → `messages` format ✅
- (k) Capture saves command output ✅
- (l) `pos ai providers` lists both providers with status ✅
- (n) Non-tty output is plain text (byte-compat) ✅

## Step 8: AGENT_TODO

**[DONE]** Task is an Orchestrator assignment — no AGENT_TODO entry (ephemeral task, not project backlog).

---

## Diff summary

```
New files:
  bin/pos-ai                         642 lines
  lib/ai-providers/gemini.sh          59 lines
  lib/ai-providers/openrouter.sh      59 lines

Overwritten (thinned):
  bin/pos-ai-gemini                 596→  7 lines (forwarder)
  bin/pos-ai-openrouter             597→  7 lines (forwarder)

Net: -1327 old lines removed, +189 modified lines, +760 new lines
     = 774 total new (vs ~1183 original combined)
```

---

REPORT_PATH: ./AgentsReport/builder/2026-08-25_r8-ai-plugin-arch.md
