# How-To: `pos ai`

Chat with AI models — Gemini, OpenRouter, and more — from the terminal and
through the Telegram bot.
Tools: `gemini` (`ask`, `chat`, `models`), `openrouter` (`ask`, `chat`, `sessions`).

| Tool | What it does |
|------|--------------|
| `pos ai gemini ask "<prompt>"` | Answer to stdout (scriptable; terse by default, `--full` for long form). Runs inside the persistent **`default`** session — it remembers prior turns across invocations |
| `pos ai gemini ask --last "why did that fail?"` | Same, but also appends the output of the **most recent logged pos command or captured output** so the model can diagnose a real failure (stderr notes which source + staleness warning) |
| `pos ai gemini capture <cmd>` | Run any command, capture its output for `--last`, and show it on screen |
| `pos ai gemini ask --session <name> "…"` | Same, but uses a named session instead of `default` |
| `pos ai gemini chat` | Interactive multi-turn conversation (session `default` unless `--session`) |
| `pos ai gemini models` | List available model ids |
| `pos ai gemini sessions` | List persistent sessions / clear one (`reset <name>`, e.g. `reset default`) |

Shared flags: `--model <id>` overrides the model; `--system "<text>"` sets the
system instruction for every turn (kept out of the session file) — it replaces
the built-in terse ask prompt wholesale; `--full` skips that built-in prompt
for long-form answers; `--last` attaches the latest pos command output or
captured output (tail, max 4096 chars) to the question and notes on stderr
which source was attached, its age, and a staleness warning once it is older
than an hour (`ask` only; stdout stays pure answer). Use `capture` to save
output from any command for `--last`.

Every `ask`/`chat` lands in a persistent session file under
`~/.local/share/linux_post_install/ai/<name>.json` (capped at 40 turns).
Terminal work accumulates in `default`; clear it with
`pos ai gemini sessions reset default`.

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
   pos config ai          # enter AI_GEMINI_API_KEY
   ```

3. Test:

   ```bash
   pos ai gemini ask "Explain DNS in one line"
   pos ai gemini models                 # verify the default model id is live
   pos ai gemini chat                   # multi-turn conversation
   ```

`ai.env` lives at `~/.config/linux_post_install/ai.env` (chmod 600); `pos config ai`
is the only place the key is written. The key is never printed by `pos`.

## OpenRouter — many providers, one key

[OpenRouter](https://openrouter.ai) gives access to hundreds of models from
different providers (Anthropic, OpenAI, Meta, Mistral, Google, …) through a
single OpenAI-compatible API. `pos ai openrouter` works identically to the
Gemini tool — same subcommands (`ask`, `chat`, `sessions`), same flags
(`--last`, `--system`, `--full`, `--session`), same terminal rendering and
machine context.

1. Get an API key from https://openrouter.ai/settings/keys.

2. Configure it:

   ```bash
   pos config ai-openrouter    # enter OPENROUTER_API_KEY
   ```

3. Test:

   ```bash
   pos ai openrouter ask "hi"
   ```

The default model is `openrouter/auto` (OpenRouter picks the best available
provider automatically). Override with `--model provider/model-name`:

```bash
pos ai openrouter ask --model anthropic/claude-sonnet-4 "explain DNS"
```

Sessions are stored separately from Gemini's:

```
~/.local/share/linux_post_install/ai-openrouter/<name>.json
```

All features work the same way — `--last` for diagnosing failures, `--system`
for custom instructions, `--full` for long-form answers, persistent sessions,
tty markdown rendering, and machine context. The only difference is the backend
API.

## From the Telegram bot

Once `pos ai gemini ask` works, any non-command message starting with `ai ` is
answered by the model — no bot map entry needed:

```
you:    ai what is Nvidia
bot:    NVIDIA is a company best known for GPUs...
```

The bridge lives in the Telegram listener's `handle_message` (it calls
`pos ai gemini ask`); only the owner chat is served, so your key stays private.
Set a different model per message:

```
you:    ai --model gemini-2.5-flash explain a Raft consensus log
```

### Telegram memory & formatting

Each chat has its own persistent session (`telegram-<chat id>` — independent
of your terminal's `default` session), so the model
remembers the conversation; `ai /reset` clears it. The listener passes a system
prompt telling the model it is answering in a Telegram chat — so it uses emojis
and stays lively — and strips markdown (`**x**`, backticks, `#`, links…) from
the reply before sending it, since messages go out as plain text.

Replying to a message before `ai …` makes that message part of the prompt, so
the model can answer about it:

```
you:    /status                    → bot: (system health output…)
you:    ai check this details about my linux   ← reply to the /status message
```

## Recipes

- **Diagnose the last failed pos run:** `pos ai gemini ask --last "why did that fail?"` — every non-interactive `pos <cmd>` logs its output to `~/.local/share/linux_post_install/logs/`; `--last` attaches the newest one (tail, max 4096 chars, errors at the bottom kept) and says on stderr which log it grabbed (name, age, first line). Older than an hour? You get a `[!]` staleness warning — the newest log may predate your current problem, so pipe the fresh failure in instead
- **Pipe arbitrary output in:** `failing-cmd 2>&1 | pos ai gemini ask how do I fix this`
- **Answer from a file:** `pos ai gemini ask "$(cat notes.txt)"`
- **Answer in a cron job:** `pos ai gemini ask "summarize today's git log" > /tmp/ai_digest.txt`
- **Long-form on demand:** `pos ai gemini ask --full "compare ext4 and zfs in depth"`
- **Forget what the terminal asked:** `pos ai gemini sessions reset default`
- **Change the default model:**
  ```bash
  pos config ai          # set AI_GEMINI_MODEL, or:
  AI_GEMINI_MODEL=gemini-2.5-flash pos ai gemini ask "hi"
  ```

## Capturing any command's output for --last

By default, `--last` reads from pos dispatcher logs (only pos commands). To analyze
output from **any** command (`pip install`, `apt upgrade`, `make`, etc.):

**Option A — explicit capture:**
```bash
pos ai gemini capture pip install xyz
pos ai gemini ask --last "what happened"
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

- `ask` POSTs `contents:[…]` (prior turns of the active session plus the new
  user turn) to
  `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
  with the key in the `x-goog-api-key` header, and prints
  `.candidates[0].content.parts[].text` — nothing else.
- Sessions live as one JSON file per name under
  `~/.local/share/linux_post_install/ai/` (`default.json` unless `--session`);
  each turn is appended and the file is pruned to the last 40 turns.
- `chat` keeps the whole conversation in memory as a growing `contents[]`
  array (seeded from the session file), so later turns have earlier context.
  `/reset` drops it (and empties the session file).
- On a non-2xx response the API's `error.message` is shown and the exit code is
  non-zero — so scripts can rely on `ask` failing loudly.

## Troubleshooting

- `ask` errors "No Gemini API key — run 'pos config ai'" → the key isn't set
  (or `ai.env` isn't readable). Run `pos config ai`.
- `API error 400` → the model id is wrong or the prompt is too long for the
  model's context window; check `pos ai gemini models`.
- `API error 429` → rate limit (free tier); wait and retry, or use a different
  model.
- Nothing in Telegram for `ai …` → the listener daemon must be running
  (`pos communication telegram listener --status`); the bot token and owner
  chat id must match `pos config telegram`.

---

## Related

- Reference: [DOC/POS.md → ai](../POS.md#ai)
- Telegram bridge context: [communication.md](communication.md)
