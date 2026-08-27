# How-To: `pos ai`

Chat with AI models — Gemini, OpenRouter, and more — from the terminal and
through the Telegram bot.
Tool: `pos ai` with pluggable provider adapters (`gemini`, `openrouter`).

| Command | What it does |
|---------|--------------|
| `pos ai ask "<prompt>"` | Answer to stdout (scriptable; terse by default, `--full` for long form). Runs inside the persistent **`default`** session — it remembers prior turns across invocations |
| `pos ai --provider openrouter ask "<prompt>"` | Same, but uses OpenRouter instead of the default Gemini provider |
| `pos ai ask --last "why did that fail?"` | Same, but also appends the output of the **most recent logged pos command or captured output** so the model can diagnose a real failure (stderr notes which source + staleness warning) |
| `pos ai capture <cmd>` | Run any command, capture its output for `--last`, and show it on screen |
| `pos ai ask --session <name> "…"` | Same, but uses a named session instead of `default` |
| `pos ai chat` | Interactive multi-turn conversation (session `default` unless `--session`) |
| `pos ai models` | List available model ids for the active provider |
| `pos ai providers` | List all available providers and their config status |
| `pos ai sessions` | List persistent sessions / clear one (`reset <name>`, e.g. `reset default`) |

Shared flags: `--provider <name>` selects the backend (gemini|openrouter;
default: gemini; also settable via `AI_PROVIDER` env/config); `--model <id>`
overrides the model; `--system "<text>"` sets the system instruction for every
turn (kept out of the session file) — it replaces the built-in terse ask prompt
wholesale; `--full` skips that built-in prompt for long-form answers; `--last`
attaches the latest pos command output or captured output (tail, max 4096 chars)
to the question and notes on stderr which source was attached, its age, and a
staleness warning once it is older than an hour (`ask` only; stdout stays pure
answer). Use `capture` to save output from any command for `--last`.

Backward compatibility: `pos ai gemini` and `pos ai openrouter` still work as
shorthand for `pos ai --provider gemini` and `pos ai --provider openrouter`.

Every `ask`/`chat` lands in a persistent session file under
`~/.local/share/linux_post_install/ai/<name>.json` (capped at 40 turns).
Terminal work accumulates in `default`; clear it with
`pos ai sessions reset default`.

---

## Terse by default, rendered on screen

`ask` prepends a built-in system instruction telling the model to work like a
CLI assistant: lead with the exact commands, one-line explanations, no essays —
and when the message is a "how do I install/update/solve/edit X" question or
pastes an error/command output, diagnose it and lead with the fix command(s).
That prompt ends with one machine-context line (hostname, distro, kernel and
architecture detected on this box), so answers match the actual machine;
`--system "<text>"` swaps it wholesale; `--full` drops it for long-form output.
`chat` keeps its neutral behavior (only `--system` applies).

On a terminal, answers are rendered as markdown, separated from your prompt
line by one blank line: fenced code blocks stay
monospace (indented + dimmed), inline `` `code` `` turns yellow, `**bold**`
turns bold, headers become bold cyan, `---` becomes a thin rule. If `glow` is
installed it is used automatically; otherwise a small built-in renderer kicks
in — no extra dependency either way. When stdout is **not** a tty (pipes,
scripts, cron, the Telegram/Matrix bridges) the raw markdown bytes are printed
exactly as before (no added blank lines), so scripting stays byte-stable.

---

## First run — get a key, configure, chat

1. Get a free API key from https://aistudio.google.com/apikey (requires a Google
   account).
2. Configure it (masked input):

   ```bash
   pos config ai          # enter AI_API_KEY (or AI_GEMINI_API_KEY)
   ```

3. Test:

   ```bash
   pos ai ask "Explain DNS in one line"
   pos ai models                 # verify the default model id is live
   pos ai chat                   # multi-turn conversation
   ```

`ai.env` lives at `~/.config/linux_post_install/ai.env` (chmod 600); `pos config ai`
is the only place the key is written. The key is never printed by `pos`.

## OpenRouter — many providers, one key

[OpenRouter](https://openrouter.ai) gives access to hundreds of models from
different providers (Anthropic, OpenAI, Meta, Mistral, Google, …) through a
single OpenAI-compatible API. Use `--provider openrouter` to switch:

```bash
pos ai --provider openrouter ask "hi"
# or the legacy shorthand:
pos ai openrouter ask "hi"
```

Configure the API key:

```bash
pos config ai              # enter AI_API_KEY (or OPENROUTER_API_KEY)
```

The default model is `openrouter/auto` (OpenRouter picks the best available
provider automatically). Override with `--model provider/model-name`:

```bash
pos ai --provider openrouter ask --model anthropic/claude-sonnet-4 "explain DNS"
```

All features work the same way across providers — `--last` for diagnosing
failures, `--system` for custom instructions, `--full` for long-form answers,
persistent sessions, tty markdown rendering, and machine context. Sessions are
shared in `~/.local/share/linux_post_install/ai/` (universal messages format).

Switch providers per-invocation:

```bash
pos ai ask "hello"                    # uses gemini (default)
pos ai --provider openrouter ask "hello"  # uses openrouter
```

Or set the default via config:

```bash
pos config ai              # set AI_PROVIDER=openrouter
```

## Provider architecture

`pos ai` uses a pluggable provider system. Each provider is a thin adapter
in `lib/ai-providers/<name>.sh` that handles the API-specific logic (auth,
request format, response parsing). The main tool handles sessions, rendering,
machine context, and all shared logic.

Available providers:

| Provider | API | Default model | Config key |
|----------|-----|---------------|------------|
| `gemini` | Google Gemini REST API | `gemini-2.5-flash` | `AI_GEMINI_API_KEY` |
| `openrouter` | OpenRouter (OpenAI-compatible) | `openrouter/auto` | `OPENROUTER_API_KEY` |

Adding a new provider: create `lib/ai-providers/<name>.sh` implementing
`provider_name()`, `provider_default_model()`, `provider_generate()`, and
`provider_models_list()`. See the existing adapters for the interface contract.

## From the Telegram bot

Once `pos ai ask` works, any non-command message starting with `ai ` is
answered by the model — no bot map entry needed:

```
you:    ai what is Nvidia
bot:    NVIDIA is a company best known for GPUs...
```

The trigger word is configurable via `pos communication telegram listener
prefix <word>` (or `pos config telegram` → `TELEGRAM_AI_PREFIX`); it takes
effect immediately, so with prefix `bot` you'd message `bot what is Nvidia`.
`pos communication telegram listener prefix` shows the current value.

The bridge lives in the Telegram listener's `handle_message` (it calls
`pos ai ask`); only the owner chat is served, so your key stays private.
Set a different model per message:

```
you:    ai --model gemini-2.5-flash explain a Raft consensus log
```

### Telegram memory & formatting

Each chat has its own persistent session (`telegram-<chat id>` — independent
of your terminal's `default` session), so the model
remembers the conversation; `<prefix> /reset` clears it (with the default
prefix that's `ai /reset`). The listener passes a system
prompt telling the model it is answering in a Telegram chat — so it uses emojis
and stays lively — and strips markdown (`**x**`, backticks, `#`, links…) from
the reply before sending it, since messages go out as plain text.

Replying to a message before `<prefix> …` makes that message part of the
prompt, so the model can answer about it:

```
you:    /status                    → bot: (system health output…)
you:    ai check this details about my linux   ← reply to the /status message
```

## Recipes

- **Diagnose the last failed pos run:** `pos ai ask --last "why did that fail?"` — every non-interactive `pos <cmd>` logs its output to `~/.local/share/linux_post_install/logs/`; `--last` attaches the newest one (tail, max 4096 chars, errors at the bottom kept) and says on stderr which log it grabbed (name, age, first line). Older than an hour? You get a `[!]` staleness warning — the newest log may predate your current problem, so pipe the fresh failure in instead
- **Pipe arbitrary output in:** `failing-cmd 2>&1 | pos ai ask how do I fix this`
- **Answer from a file:** `pos ai ask "$(cat notes.txt)"`
- **Answer in a cron job:** `pos ai ask "summarize today's git log" > /tmp/ai_digest.txt`
- **Long-form on demand:** `pos ai ask --full "compare ext4 and zfs in depth"`
- **Forget what the terminal asked:** `pos ai sessions reset default`
- **Switch to OpenRouter:** `pos ai --provider openrouter ask "hi"`
- **Change the default model:**
  ```bash
  pos config ai              # set AI_MODEL, or:
  AI_MODEL=gemini-2.5-flash pos ai ask "hi"
  ```
- **List available providers:** `pos ai providers`

## Capturing any command's output for --last

By default, `--last` reads from pos dispatcher logs (only pos commands). To analyze
output from **any** command (`pip install`, `apt upgrade`, `make`, etc.):

**Option A — explicit capture:**
```bash
pos ai capture pip install xyz
pos ai ask --last "what happened"
```
The `capture` subcommand runs the command, shows its output on screen, and saves it
for `--last`. Each `capture` overwrites the previous one (latest only).

**Option B — automatic capture (shell hook):**
```bash
# Add to ~/.bashrc:
source /usr/local/bin/pos-ai-hook.sh
```
After sourcing, every command's output is silently captured. Then just run any
command and `--last` picks it up automatically. Captures up to 1 MB (oldest
truncated). To disable: `unset __POS_CAPTURE_ACTIVE`.

## How it works

- `ask` sends the session history (OpenAI `messages` format) to the active
  provider's API. Gemini converts to `contents` format internally; OpenRouter
  sends `messages` directly. The answer text is printed to stdout.
- Sessions live as one JSON file per name under
  `~/.local/share/linux_post_install/ai/` (`default.json` unless `--session`);
  each turn is appended and the file is pruned to the last 40 turns. Old
  Gemini-format sessions (`contents[]`) are auto-migrated to `messages` format
  on load.
- `chat` keeps the whole conversation in memory as a growing `messages[]`
  array (seeded from the session file), so later turns have earlier context.
  `/reset` drops it (and empties the session file).
- On a non-2xx response the API's `error.message` is shown and the exit code is
  non-zero — so scripts can rely on `ask` failing loudly.

## Troubleshooting

- `ask` errors "No Gemini API key — run 'pos config ai'" → the key isn't set
  (or `ai.env` isn't readable). Run `pos config ai`.
- `API error 400` → the model id is wrong or the prompt is too long for the
  model's context window; check `pos ai models`.
- `API error 429` → rate limit (free tier); wait and retry, or use a different
  model.
- Nothing in Telegram for `<prefix> …` (default `ai`) → the listener daemon
  must be running (`pos communication telegram listener --status`); the bot
  token and owner chat id must match `pos config telegram`. Check the current
  trigger word with `pos communication telegram listener prefix`.

---

## Related

- Reference: [DOC/POS.md → ai](../POS.md#ai)
- Telegram bridge context: [communication.md](communication.md)
