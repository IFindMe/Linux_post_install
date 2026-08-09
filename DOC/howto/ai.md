# How-To: `pos ai`

Chat with Google Gemini — from the terminal and through the Telegram bot.
Tools: `gemini` (`ask`, `chat`, `models`).

| Tool | What it does |
|------|--------------|
| `pos ai gemini ask "<prompt>"` | One-shot answer to stdout (scriptable) |
| `pos ai gemini chat` | Interactive multi-turn conversation |
| `pos ai gemini models` | List available model ids |

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

## Recipes

- **Answer from a file:** `pos ai gemini ask "$(cat notes.txt)"`
- **Pipe into it:** `echo "fix this: $(cat error.log)" | pos ai gemini ask`
- **Answer in a cron job:** `pos ai gemini ask "summarize today's git log" > /tmp/ai_digest.txt`
- **Change the default model:**
  ```bash
  pos config ai          # set AI_GEMINI_MODEL, or:
  AI_GEMINI_MODEL=gemini-2.5-flash pos ai gemini ask "hi"
  ```

## How it works

- `ask` POSTs `contents:[{role:user, parts:[{text:"…"}]}]` to
  `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
  with the key in the `x-goog-api-key` header, and prints
  `.candidates[0].content.parts[].text` — nothing else.
- `chat` keeps the whole conversation in memory as a growing `contents[]` array,
  so later turns have earlier context. `/reset` drops it.
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
