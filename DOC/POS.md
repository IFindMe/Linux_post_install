# `pos` CLI Reference

`pos` is the unified command-line interface installed to `/usr/local/bin/`. Every tool is a small script in `bin/` with a `pos-<category>-<command>` name. This document explains the dispatcher and every command.

- [The dispatcher — `bin/pos`](#the-dispatcher--binpos)
- [Logging behavior](#logging-behavior)
- [Commands](#commands)
  - [ai](#ai)
  - [network](#network)
  - [docker](#docker)
  - [media](#media)
  - [system](#system)
  - [ssh](#ssh)
  - [share](#share)
  - [communication](#communication)
  - [entertainment](#entertainment)
  - [flags](#flags)
  - [config](#config)
  - [tree](#tree)
- [Legacy wrappers](#legacy-wrappers)

---

## The dispatcher — `bin/pos`

**Purpose:** turn `pos <category> <command> [args]` into a call to the matching `pos-*` script.

### How it works

`pos` scans its own directory for executable `pos-*` files and tries **variable-length argument matching**, longest first. For `pos docker compose up jellyfin`:

```
tries pos-docker-compose-up-jellyfin   (not found)
tries pos-docker-compose-up            (not found)
tries pos-docker-compose               (found) → runs with args "up jellyfin"
```

`pos help <full command>` runs that tool's `--help` (e.g. `pos help communication telegram`, `pos help docker compose` — the words are joined with dashes). `pos <category>` and `pos <category> --help` list that category's subcommands (derived from `bin/pos-<category>-*` filenames, no script execution). Running `pos` with no args prints the built-in usage text (which doubles as the category cheat-sheet).

---

## Logging behavior

Every non-interactive `pos` invocation logs to `~/.local/share/linux_post_install/logs/`:

- Per-command files: `YYYYMMDD_HHMMSS_pos_<args>.log` (full stdout + stderr).
- `pos.log`: one line per invocation — command, log file, exit code.
- **Interactive** commands (`pos system firewall`, `pos media mp4`, `pos system backup`) only log the invocation, not their output.

---

## Commands

Category-less tools (`config`, `tree`) live outside any category and are documented in their own `###` sections below.

### ai

**File:** `bin/pos-ai` (provider-agnostic main tool), `bin/pos-ai-gemini` / `bin/pos-ai-openrouter` / `bin/pos-ai-llamacpp` (backward-compat forwarders → `pos ai --provider <name>`), `bin/pos-ai-hf` (Hugging Face model downloader), `bin/pos-ai-server` (llama.cpp inference server manager)
**Provider adapters:** `lib/ai-providers/gemini.sh`, `lib/ai-providers/openrouter.sh`, `lib/ai-providers/llamacpp.sh`
**Purpose:** AI assistant with pluggable providers. Six subcommands: `ask` (scriptable, persistent session), `capture` (run a command and save its output for `--last`), `chat` (interactive multi-turn REPL), `models` (list available models), `providers` (list providers and config status), and `sessions` (list/clear sessions). Providers handle API-specific logic; the main tool handles sessions, rendering, machine context, and all shared logic.

| Command | Behavior |
|---------|----------|
| `pos ai ask "<prompt>"` | Sends the prompt to the active provider (default: gemini) and prints the answer text to stdout. The prompt may also be piped in via stdin when no argument is given. Runs in the persistent `default` session (`~/.local/share/linux_post_install/ai/default.json`, capped at 40 turns, configurable via `AI_SESSION_TURNS`; `--session <name>` picks another). Terse by default: a built-in system instruction asks for commands-first minimal prose and to diagnose pasted errors/output with the fix first (`--system "<text>"` replaces it wholesale, `--full` skips it; `AI_SYSTEM_PROMPT` env/config provides a custom default). With `--last`, the output of the most recent logged pos command or captured output (tail, max 4096 chars) is appended to the question. On a tty the answer is rendered as markdown (`glow` if installed, else a built-in renderer); non-tty stdout gets the raw markdown bytes unchanged |
| `pos ai --provider openrouter ask "<prompt>"` | Same, but uses OpenRouter instead of the default Gemini provider |
| `pos ai capture <cmd..>` | Run a command, capture its stdout+stderr to screen and to `~/.local/share/linux_post_install/last_cmd_output` for `--last`. Each capture overwrites the previous one. Returns the command's exit code |
| `pos ai chat` | Interactive REPL with multi-turn history (the `messages[]` array is appended per turn and persisted to the session file — `default` unless `--session`); replies are rendered like `ask` on a tty; `q`/`quit`/`exit` or Ctrl+C quit, `/reset` clears the history, empty input re-prompts |
| `pos ai sessions` | Lists session files with turn counts; `sessions reset <name>` clears one (e.g. `reset default`) |
| `pos ai models` | Lists available models for the active provider and flags the configured default |
| `pos ai providers` | Lists available providers, their config status, and the active provider |
| `pos ai --model <id> …` | Overrides the model for one invocation |
| `pos ai --provider <name> …` | Selects the provider for one invocation (gemini\|openrouter\|llamacpp) |
| `pos ai alias` | Interactive alias manager (`bin/pos-ai-alias`): menu loop (create / edit / remove / list) that shows the alias table (Name/Provider/Session/Prompt, prompts truncated) between picks |
| `pos ai alias create [name]` | Interactive 4-step wizard: alias name (leading letter, then letters/digits/-/_; unique across aliases), provider pick (from installed `lib/ai-providers/*.sh` adapters), session name (defaults to the alias name), optional system prompt (must not contain `\|`; warns above 500 chars); confirm defaults to yes, then the alias is saved |
| `pos ai alias edit [name]` | Edits an existing alias (pick from list or pass the name): provider/session/prompt are re-prompted pre-filled with the current values — Enter keeps the current value; a per-field changed/unchanged summary is confirmed (default yes) before saving; nothing is written if nothing changed |
| `pos ai alias remove [name]` | Removes an alias (pick from list or pass the name); the confirmation defaults to **no** and removal cannot be undone |
| `pos ai alias list` | Non-interactive: prints all aliases as a Name/Provider/Session/Prompt table (prompts truncated at 42 chars) |
| `pos ai alias show <name>` | Prints one alias's details including the wrapper path and the resolved command: `pos ai <provider> ask --session <session>[ --system '<prompt>']` |

Alias storage & activation: records live in `~/.config/linux_post_install/ai-aliases.env` — one `name\|provider\|session\|system_prompt` line per alias, chmod 600, managed by the tool (do not hand-edit); an empty session falls back to the alias name. **Activation needs no shell sourcing**: every `pos ai alias` invocation syncs the ENV file (the single source of truth) against executable wrapper scripts at `~/.local/bin/<name>` (chmod 755) — missing or changed wrappers are atomically rewritten, wrappers pos owns but ENV no longer lists are deleted, and hand-edited wrappers are healed. A wrapper re-reads its bytes on every run, so an edit is **live on the next invocation** (no reload), and the scripts work identically in interactive shells, scripts, cron, and non-login ssh sessions (`~/.local/bin` must stay on `PATH` — a loud warning with a copy-paste fix appears when it isn't). Create refuses name collisions: a foreign file at `~/.local/bin/<name>` and names resolving to another binary on `PATH` are never overwritten. The legacy generated `~/.config/linux_post_install/ai-aliases.sh` is no longer written; on the next invocation pos removes it automatically (marker-guarded — a foreign-content file is left untouched with a warning) and prints an `unalias <names>` remediation hint for already-running shells (or simply start a new shell).

Backward compatibility: `pos ai gemini`, `pos ai openrouter`, and `pos ai llamacpp` still work as shorthands for `pos ai --provider gemini`, `pos ai --provider openrouter`, and `pos ai --provider llamacpp`.

`pos ai` with no subcommand prints usage (never blocks on stdin). `ask`/`chat` time out after 60s per request; on a non-2xx response the API's `error.message` is shown and the tool exits non-zero.

**Configuration** (`~/.config/linux_post_install/ai.env`, edit with `pos config ai`):

| Key | Required | Default | Purpose |
|-----|----------|---------|---------|
| `AI_PROVIDER` | no | `gemini` | Active provider (gemini\|openrouter\|llamacpp) |
| `AI_API_KEY` | no (legacy fallback) | — | Legacy shared API key, used when the active provider's key is empty; not part of the `pos config ai` prompt (set via env or hand-edit); secret |
| `AI_MODEL` | no | per provider | Model id used by `ask`/`chat`/`models` |
| `AI_SYSTEM_PROMPT` | no | built-in terse prompt | Custom system prompt (overrides built-in; empty to reset) |
| `AI_MAX_TOKENS` | no | `2048` | Max output tokens per request (OpenRouter/Gemini cost cap) |
| `AI_SESSION_TURNS` | no | `40` | Session message cap — 2 per exchange; 10 = last 5 exchanges |
| `AI_GEMINI_API_KEY` | yes (gemini) | — | Gemini API key (the active key when provider is gemini; secret — masked in `pos config ai`) |
| `AI_GEMINI_MODEL` | fallback | `gemini-2.5-flash` | Legacy: Gemini model id (used when `AI_MODEL` is empty) |
| `OPENROUTER_API_KEY` | yes (openrouter) | — | OpenRouter API key (the active key when provider is openrouter; secret — masked in `pos config ai`) |
| `OPENROUTER_MODEL` | fallback | `openrouter/auto` | Legacy: OpenRouter model id (used when `AI_MODEL` is empty) |

Model precedence: `--model` flag > `AI_MODEL` env > provider-specific fallback (`AI_GEMINI_MODEL`/`OPENROUTER_MODEL`) > provider default. API key precedence: `<provider>_API_KEY` (`AI_GEMINI_API_KEY` for gemini / `OPENROUTER_API_KEY` for openrouter) > legacy `AI_API_KEY` fallback > error. `AI_API_KEY` is an internal adapter shim and a backward-compat input — it is not offered by `pos config ai`. `postinstall.sh` copies the repo's `config/ai.env` template to `~/.config/linux_post_install/ai.env` on install (no clobber). Dependencies: `curl` + `jq` (both in `preinstall.sh` PACKAGES). Sessions are stored in OpenAI `messages` format universally; old Gemini-format sessions (`contents[]`) are auto-migrated on load.

**Messaging bridges:** the Telegram and Matrix listeners forward non-command messages starting with `ai ` (case-insensitive) to `pos ai ask` and reply with the model's answer — see [communication → listener](#communication). The Telegram bridge uses one session per chat (`telegram-<chat id>`), the Matrix bridge one per room (`matrix-<room>`).

**Command execution posture:** when an `ask`/`chat` answer contains a ``sh/shell`` fenced code block, `pos ai` offers to run it and the default is **deny**. On an interactive terminal it prompts `Run this command? [y/N]` — only an explicit `y`/`Y` runs it; anything else (including Enter) declines and adds the command to shell history. Without an interactive tty (pipes, scripts, cron, chat bridges) commands are **never** executed — the block is neither printed nor run. `--trust` auto-executes without the confirmation prompt, but only on an interactive terminal (no effect in a non-tty/bridge context). `--no-command-execution` disables execution entirely: the detected command is neither printed nor run and no prompt appears — this is the structural guard the chat bridges rely on so a future refactor cannot auto-execute. When both `--trust` and `--no-command-execution` are passed, the last one on the command line wins.

`pos ai hf` — Hugging Face model downloader:

| Command | Behavior |
|---------|----------|
| `pos ai hf search <query>` | Search Hugging Face models by query (sorted by downloads); prints model ID, download count |
| `pos ai hf download <repo-id> [filename]` | Download a file or entire repo from Hugging Face. Creates `<namespace>-<model-name>/` under `HF_DOWNLOAD_DIR` (default `~/.local/share/linux_post_install/ai/models/`). Options: `--branch <rev>` (specific branch/revision; alias `--revision`, when both are given the later one wins), `--gguf` (only `.gguf` weight files; lists recursively and excludes mmproj/imatrix/vision/MTP artifacts), `--quant <dir>` (with `--gguf`: pick one quant directory when a repo groups weights into several, e.g. `--gguf --quant Q8_0`), `--include <pattern>` / `--exclude <pattern>` (glob filters applied after the gguf/filename filter, in the order gguf → include → exclude, e.g. `--include "*.gguf" --exclude "*Q4_*"`), `--list` (list remote repository files without downloading — shows exactly what download would fetch), `--output <dir>` (override download dir). A filename may be a full path (`Q8_0/model.gguf`) or a bare name (`model.gguf`) — bare names matching files in multiple directories error and ask for the full path. Progress bars to stderr; summary with path and size to stdout. Writes `.hf-meta` JSON (repo-id, branch, files, timestamp) for `list` and `remove` |
| `pos ai hf list` | List all downloaded models with size and date |
| `pos ai hf remove <repo-id>` | Remove a downloaded model directory and show freed space |
| `pos ai hf cache [status\|clear]` | `status` shows the cache directory, model count and total on-disk size of all downloaded models; `clear` lists the downloaded models, asks for confirmation (destructive default **n**) and removes them, printing the freed space |

Auth: `HF_TOKEN` in `~/.config/linux_post_install/ai.env` (same scope as `pos ai`; edit via `pos config ai`). Even for public repos, a token increases rate limits from 500/5min to 1000/5min. Resume: `curl -C -` resumes interrupted downloads. Rate limit handling: on HTTP 429, sleeps `Retry-After` or 60s, retries once.

`pos ai server` — llama.cpp local inference server manager:

| Command | Behavior |
|---------|----------|
| `pos ai server start [model]` | Generate and start a systemd user service running llama-server. Model resolution: explicit arg > `LLAMACPP_MODEL` config > interactive pick (TTY only). Auto-detects GPU (CUDA via `nvidia-smi`); sets `--n-gpu-layers` accordingly. Writes unit to `~/.config/systemd/user/pos-ai-server.service`, runs `daemon-reload && enable --now`. Warns about linger if needed |
| `pos ai server stop` | Stop and disable the systemd user service, remove the unit file |
| `pos ai server status` | Show service state, loaded model (from `/v1/models`), port, host, GPU, context, threads, autostart, endpoint, and health (from `/health`) |
| `pos ai server models` | List `.gguf` files found in `HF_DOWNLOAD_DIR` with sizes |
| `pos ai server logs [lines]` | Show recent server logs via `journalctl --user -u pos-ai-server` (default 50 lines) |

Flags: `--port <port>` (default 8088), `--host <addr>` (default 127.0.0.1), `--model <path>` (overrides arg/config), `--ctx <size>` (context window, default 4096), `--gpu <layers>` (-1=auto, 0=CPU, N=explicit, default -1), `--threads <n>` (default nproc), `--gpu-layers`/`--n-gpu-layers <n>` (GPU layers override), `--gpu-threads <n>`, `--tensor-split <n>`, `--batch-size <n>`, `--ubatch-size <n>`, `--temperature <n>`, `--top-k <n>`, `--top-p <n>`, `--repetition-penalty <n>`, `--mmap`, `--mlock`, `--kv-cache <size>`, `--ctx-size <n>`, `--metrics`, `--health`, `--slots <n>`, `--no-unit` (run the server directly under nohup with a pidfile in `$XDG_RUNTIME_DIR`/`/tmp` instead of installing a systemd unit — for headless/SSH boxes whose user systemd bus is unreachable; `stop`/`status` still work via the pidfile). Without `--no-unit`, `start` pre-flights the user systemd bus (`ensure_user_bus`) and aborts with remediation (`export XDG_RUNTIME_DIR=…`, `sudo loginctl enable-linger …`) before writing any unit. **Every flag that enters `ExecStart` is validated** against the installed llama.cpp's `--help` (word-boundary match, version-aware). Flag validation is split by intent: flags the user explicitly **requested** (via CLI, `LLAMACPP_*` config, or exported env) that are unsupported cause a **hard error** naming the flag + detected version; always-emitted **default** flags (`--port`, `--host`, `--n-gpu-layers`, `--ctx-size`, `--threads`) that the user did not request and that are unsupported are **omitted from the unit with a single warning** (never a hard error, never silently passing an unsupported flag). If `--help` cannot be read the tool warns and proceeds (all flags accepted). The generated unit and `--dry-run` contain only flags that passed validation. Config keys in `ai.env`: `LLAMACPP_PORT`, `LLAMACPP_HOST`, `LLAMACPP_MODEL`, `LLAMACPP_CTX_SIZE`, `LLAMACPP_GPU_LAYERS`, `LLAMACPP_THREADS`. Requires `curl` + `jq` and a `llama-server` binary on PATH (install via `bash apps/install.sh llamacpp`).

### network

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos network ip` | `bin/pos-network-ip` | Show interfaces, default route, public IP + location | None. Public IP via `https://ifconfig.me`; location via `ip-api.com` (5s timeouts) |
| `pos network checkport <ip:port>` | `bin/pos-network-checkport` | Check if a TCP port is open | None. Uses `/dev/tcp` with a 2s timeout; exit 0/1 via OPEN/CLOSED |
| `pos network scan <cidr> [--full] [--retries N]` | `bin/pos-network-scan` | Two-phase nmap scan | See below |
| `pos network hotspot [cmd]` | `bin/pos-network-hotspot` | Wi-Fi hotspot via `create_ap` (CLI) or `wihotspot-gui` (GUI) | Uses the precompiled binaries from `x64_bin/`; see below |
| `pos network download <cmd>` | `bin/pos-network-download` | aria2 RPC daemon + queue control (add/torrent/metalink, watch, limits) | `aria2c`/`jq`/`curl`; daemon = systemd user service; secret in `~/.config/linux_post_install/download.env`; see below |

**`pos network scan` in detail:**

- Phase 1 — fast host discovery (`nmap -sn -T5`), prints the live host list.
- Phase 2 (only with `--full`) — service/version scan (`-sV -sC`), plus OS detection and NSE scripts if run with privileges; shows ports, OS, SSH host keys, HTTP titles, NetBIOS/SMB info.
- Accepts a bare IP (treated as `/32`) or a CIDR.
- Auto-raises to `sudo nmap` when possible (root, passwordless sudo, or an interactive terminal with `--full`).
- `--retries N` tunes discovery retries (default 1).

**`pos network hotspot` in detail:**

Backed by the precompiled binaries shipped in `x64_bin/` (see [SCRIPTS.md → x64_bin/](SCRIPTS.md#x64_bin--precompiled-binaries)). Needs root for the CLI commands (uses `sudo`):

| Command | Behavior |
|---------|----------|
| `pos network hotspot` | Launches the `wihotspot-gui` (GTK3 GUI) |
| `pos network hotspot start <wifi-iface> [<internet-iface>] <ssid> [<passphrase>]` | Asks whether to run in the background; `y` starts `create_ap --daemon` (logs to `/var/log/linux_post_install_hotspot.log`), `n` runs in the foreground (blocks until Ctrl+C) |
| `pos network hotspot start --foreground <wifi-iface> [<internet-iface>] <ssid> [<passphrase>]` | Skips the prompt, runs in the foreground |
| `pos network hotspot stop [<id>]` | Stops the running access point via `create_ap --stop`; `<id>` is an interface name or PID, auto-detected if omitted |
| `pos network hotspot status` | Runs `create_ap --list-running` |

**`pos network download` in detail:**

Runs a persistent `aria2c` JSON-RPC daemon (`localhost:6800`) as a **systemd user service** (`pos-aria2.service`, enabled with `systemctl --user enable --now`; prints a linger warning on headless boxes). `start` installs the unit and generates a random `RPC_SECRET` into `~/.config/linux_post_install/download.env` (chmod 600); the secret is also respected as the `RPC_SECRET` env var. Unit flags: `--continue=true --max-connection-per-server=16 --split=16 --seed-time=0 --dir=$HOME/Downloads`.

| Command | Behavior |
|---------|----------|
| `pos network download start` / `stop` | Install+enable the systemd user service / stop and remove it |
| `pos network download status` | Daemon health + global transfer stats (`getGlobalStat`) |
| `pos network download add <url>...` | Enqueue HTTP/FTP downloads (auto-starts the daemon); options `--dir`, `--out`, `--split`, `--tmux` |
| `pos network download torrent <file|magnet>...` | Enqueue `.torrent` files (base64 via `addTorrent`) or magnet links; `--seed` keeps seeding (default `--seed-time=0`), `--dir`, `--tmux` |
| `pos network download metalink <file|url>...` | Enqueue `.metalink` files or URLs; `--tmux` |
| `pos network download list` | Table of active / waiting / finished downloads (GID, status, %, dl/up speeds, name) |
| `pos network download info <gid>` | Full `tellStatus` dump (status, progress, speeds, ETA, error) |
| `pos network download files <gid>` / `peers <gid>` | Files of a download / peers of a torrent |
| `pos network download pause\|resume [gid\|all]` | Pause/resume one or all (default `all`) |
| `pos network download remove [gid\|all]` | Remove one or all; `--force` = `forceRemove` (kills immediately) |
| `pos network download purge` | Clear finished/error history |
| `pos network download move <gid> <pos>` | Reorder the waiting queue (`changePosition`) |
| `pos network download limit [gid] <speed>` | Speed limit, global or per-download (`--upload` = upload speed; `0` = unlimited); accepts `2M`/`512K` |
| `pos network download set <k=v>...` | Set global aria2 options (`--gid <gid>` = per-download) |
| `pos network download watch [gid]` | Live table, 2 s refresh; with a GID it exits when that download completes |
| `pos network download restart <gid>` | Re-queue a finished/errored download from history: torrents re-add via magnet (info-hash + trackers), HTTP via their original URLs — `--continue=true` resumes partial files, a complete file re-verifies instantly. Options `--dir`, `--seed`, `--split`, `--tmux` |
| `pos network download retry <gid\|all>` | Smart retry of errored downloads: waits out internet outages (poll `--interval`, give up after `--max-wait`), then re-queues and re-verifies. Sources failing with aria2 error 3 are marked permanent in `~/.config/linux_post_install/download.retry` (id = `url:<uri>` / `bt:<infohash>`) and skipped by `retry all` — manual `restart` overrides. `--once` (healer timer mode) skips the wait and exits 0 even on failure; `--quiet` silences output. Options `--dir`, `--seed`, `--split`, `--tmux` |
| `pos network download replace <gid> <url>` | Give a dead download a fresh URL: re-queues with the same `dir` + file name (so `--continue=true` resumes the partial), forgets the old dead source from `download.retry`, and verifies the new link — a dead replacement is diagnosed and marked permanent. `status` lists downloads needing this. Single-file HTTP/FTP only (torrents: `restart`); options `--dir`, `--split`, `--tmux` |

**`pos network download menu`** — bare invocation on a terminal (or the explicit `menu` subcommand) opens an interactive hub over the top verbs: daemon status, overview (status + queue snapshot), list, add URL (asked via a prompt, with an optional `--tmux` handover), gid-pick → info / pause / resume / remove / restart (remove behind an explicit y/N confirm naming the download), purge (typed-`purge` confirm), live watch (Ctrl-C leaves the menu), and daemon start/stop (stop behind a y/N confirm). Queue views are gated on a non-fatal RPC liveness probe — with the daemon down you get a graceful hint and stay in the menu instead of an error exit. Arguments stay scriptable; without a terminal the menu fails closed with a pointer to these subcommands.

**`--tmux`:** after enqueueing, `add`/`torrent`/`metalink` open a detached tmux session `dl-<name>` running `watch <gid>` (name from `--out` or the URL basename, sanitized and truncated to 40 chars; `-2` suffix on collision). The session closes itself when the download finishes — attach with `tmux attach -t dl-<name>`.

**Outage resilience:** `watch <gid>` auto-restarts its download when the network comes back (it polls `NET_PROBE`, default `timeout 3 bash -c 'exec 3<>/dev/tcp/$1/$2' _ 8.8.8.8 53` — host/port are positional args, never interpolated into the probe's shell source; the `NET_PROBE` env override is operator-controlled). For unattended machines the **retry healer** timer (`pos-aria2-retry.timer`, systemd **user** scope) runs `retry all --once --quiet` every 2 min; it arms automatically whenever a download starts (`add`/`torrent`/`metalink`/`restart`) and disables itself when no active, waiting, or errored downloads remain. When a source is genuinely gone (aria2 error 3, e.g. a 404), the download is marked permanent — `status` prints a `needs fresh link: <name> (<gid>)` line and `replace <gid> <url>` resumes it with a new URL. Both are dry-run aware.

### docker

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos docker ps` | `bin/pos-docker-ps` | Enhanced container list: name, image, health, uptime, IPs, ports, ID, plus a healthy/unhealthy summary | None. Requires Docker + Python 3 |
| `pos docker health` | `bin/pos-docker-health` | One-glance health dashboard; **exits 1** if any container is unhealthy | None. Checks all containers including stopped ones |
| `pos docker stack [-a]` | `bin/pos-docker-stack` | Containers grouped by compose stack (project); `-a` includes stopped; non-compose containers under `Standalone` | None. Requires Docker |
| `pos docker compose …` | `bin/pos-docker-compose` | ScaleTail service manager | See [Docker Compose / ScaleTail](#docker-compose--scaletail) below |

**`pos docker stack [-a|--all]`** — containers grouped by their Docker Compose project (stack). Each stack is a section (project name, sorted) whose lines show container name, status, and port mappings (`-` when none — e.g. ScaleTail sidecar containers). Containers with no compose project land in a `Standalone` section at the end. Default shows running containers; `-a|--all` includes stopped/exited (like `docker ps -a`). Status is colored when output goes to a terminal: `Up*` green, `Exited*`/`Dead*`/`Created*` red, `Paused*`/`Restarting*` yellow. Ends with a summary line (`Stacks: N  containers: N  standalone: N`); exit 0 even when no containers exist.

#### Docker Compose / ScaleTail

**`pos docker compose ls`** — list available ScaleTail service templates.

**`pos docker compose installed`** — list deployed services under `$SERVICES_BASE`.

**`pos docker compose up <service>`** — deploy a service:

1. If not yet deployed, creates `$SERVICES_BASE/<service>/` with `config/` and `data/`, copies the template's `compose.yaml`.
2. If no `.env` exists, copies the template's `.env` (or writes a default) and fills in your global config values (`TS_AUTHKEY`, `TZ`, `DNS_SERVER`).
3. If `TS_AUTHKEY` is still empty, prompts for it.
4. Offers to edit `.env` before starting (default **yes** on first deploy).
5. Runs `docker compose up -d`.

**`pos docker compose down/restart/logs <service>`** — stop, restart, or tail logs of a deployment.

**`pos docker compose update`** — `git pull` the ScaleTail templates, then refresh the `compose.yaml` of every deployed service. **Per-service `.env` files are never touched.**

**`pos docker compose config [show]`** — show the global config file and `SERVICES_BASE`.

**`pos docker compose config set KEY=VALUE`** — set/update a global default in `~/.config/linux_post_install/compose.env`.

**`pos docker compose config edit`** — open the global config in `$EDITOR` (creates a default file first).

**`pos docker compose menu`** — bare invocation on a terminal (or the explicit `menu` subcommand) opens an interactive hub wrapping these commands: list templates / deployed stacks (+ status), `up` (pick a template — first-deploy `.env`/TS_AUTHKEY prompts included), `down`/`restart` (each behind an explicit y/N confirm naming the stack), follow logs (`-f`; Ctrl-C returns to the menu), `update` (y/N confirm naming `$SERVICES_BASE`; `.env` never touched), and global config show/edit. Arguments stay scriptable; without a terminal the menu fails closed with a pointer to these subcommands.

Configuration (three layers, most specific wins):

| Layer | File | Notes |
|-------|------|-------|
| Template defaults | `/usr/local/share/linux_post_install/scale-tail/services/<name>/.env` | Read-only |
| Global config | `~/.config/linux_post_install/compose.env` | Edited via `config set` / `config edit` |
| Per-service | `$SERVICES_BASE/<service>/.env` | Created on first `up`, **never overwritten** |

Global config keys:

| Key | Required | Default | Purpose |
|-----|----------|---------|---------|
| `TS_AUTHKEY` | yes | — | Tailscale auth key for the sidecar |
| `TZ` | no | `Europe/Amsterdam` | Service timezone |
| `DNS_SERVER` | no | `9.9.9.9` | DNS server |
| `SERVICES_BASE` | no | `/srv` | Deployment root |

#### Docker vbox

**File:** `bin/pos-docker-vbox`
**Purpose:** manage disposable Docker containers as lightweight "VMs". Each container gets a bind-mounted host directory so files persist after the container is removed. Containers carry the label `linux_post_install.vbox=true`.

| Command | Behavior |
|---------|----------|
| `pos docker vbox create <name> [image] [--dir <path>]… [--device </dev/node>]… [--gpu] [--port H:C]… [--cpus N] [--memory SIZE] [--network MODE]` | Creates a container from `ubuntu:22.04` (or the given image), bind-mounting `~/<name>` (or the first `--dir`; repeatable for extra same-path mounts) as the working directory; optional flags add GPU (`--gpus all`), device passthrough, port publishes and cpu/memory limits; prompts to enter immediately |
| `pos docker vbox enter <name>` | Shell into the container (auto-starts it if stopped); detects the working dir from the container mounts |
| `pos docker vbox start/stop/rm <name>` | Start, stop, or force-remove the container |
| `pos docker vbox ls` | List vbox containers only (label filter) |

**`pos docker vbox menu`** — bare invocation on a terminal (or the explicit `menu` subcommand) opens an interactive hub wrapping these verbs: list, create (categorized flow: name → category hub with live basket counts — image quick-picks, GPU/Nvidia with automatic toolkit/device-node detection, host devices, dir mounts, ports, CPU/RAM → review screen rendering the exact `docker create` plan before anything runs; 'n' returns to the hub with edits preserved), enter (hands the terminal to the container shell — `exit` returns to the menu), start/stop (pick a VM), and remove (y/N confirm naming the VM; `rm -f` removes the container, the host folder is kept). Arguments stay scriptable; without a terminal the menu fails closed with a pointer to these subcommands.

The standalone `vbox` command still works and forwards to `pos docker vbox` (see [Legacy wrappers](#legacy-wrappers)).

### media

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos media yt` | `bin/pos-media-yt` | YouTube download tools dispatcher (mp3/mp4/grab/ytsync/subtitles); bare invocation prints help listing subcommands | Subcommands resolved via `bin/pos-media-yt-<sub>` files |
| `pos media yt mp3 <url>` | `bin/pos-media-yt-mp3` | Download audio as MP3 via yt-dlp, with thumbnail + metadata | Output to `~/Music/%(title)s.%(ext)s`, `--audio-quality 0`; `--by-artist` organizes as `<dir>/<artist>/<title>.mp3`. Env seam: `YT_OUT_DIR` overrides the default output dir |
| `pos media yt mp4 <url>` | `bin/pos-media-yt-mp4` | Download video via yt-dlp with **interactive format selection** | Lists formats (`yt-dlp -F`), asks for a format ID, saves to `~/Videos/`; `-f/--best/--worst` skip the prompt. Env seam: `YT_OUT_DIR` overrides the default output dir. Reads stdin (interactive format pick) → in `INTERACTIVE_CMDS` |
| `pos media yt grab <url>` | `bin/pos-media-yt-grab` | Auto-download a URL as audio or video (classify + route to yt-mp3/yt-mp4) | Domain-based classification (YouTube Music/SoundCloud/Bandcamp → audio; YouTube/Vimeo/Twitch → video); `--audio`/`--video` force the mode; `--best` default for video (non-interactive); prints a clean summary (🎵/🎬 title, path, size). Config: `GRAB_DEFAULT` (`pos config grab`, default `video`) for unknown domains |
| `pos media yt ytsync [add\|sync\|list\|remove]` | `bin/pos-media-yt-ytsync` | Thin forwarder → `pos media ytsync` (incremental YouTube channel/playlist sync into `~/Videos`) | See `bin/pos-media-ytsync` below |
| `pos media yt subtitles <url>` | `bin/pos-media-yt-subtitles` | Extract subtitles/captions from a URL (yt-dlp) | Default `--write-subs --write-auto-subs --sub-langs best`; `--lang en,ar` (comma = single `--sub-langs` arg); `--format srt` (default) / `vtt` / `txt` (srt→txt post-conversion); `--auto-only` drops manual subs; `--list-subs` probe; output to current dir (`-o ./%(title)s.%(sub_lang)s.%(ext)s`), `--output <dir>` overrides. Non-interactive; needs only yt-dlp (no ffmpeg) |
| `pos media mp3 <url>` | `bin/pos-media-mp3` | **Forwarder** → `pos media yt mp3` (backward-compat alias) | Legacy spelling still works |
| `pos media mp4 <url>` | `bin/pos-media-mp4` | **Forwarder** → `pos media yt mp4` (backward-compat alias) | Legacy spelling still works |
| `pos media grab <url>` | `bin/pos-media-grab` | **Forwarder** → `pos media yt grab` (backward-compat alias) | Legacy spelling still works |
| `pos media sync [--mp3\|--mp4]` | `bin/pos-media-sync` | Incremental Music → USB sync (add/update only — never deletes) | Copies mp3/mp4 from `$HOME/Music` (or `--source <dir>`) into `<usb>/Music/`, preserving the tree; missing or changed (size/mtime) files are copied, identical ones skipped. Same USB detection as `pos system backup` (lsblk TRAN + lsusb/by-id, mount offer for unmounted sticks, multi-stick picker). `--mp3`/`--mp4` filter by extension, neither = both; `--dry-run` previews. Config: `MEDIA_SYNC_SOURCE`, `MEDIA_SYNC_DEST`, shared `USB_MOUNT_BASE`/`USB_BYID` from `~/.config/linux_post_install/system.env`. Result notified via `lib/notify.sh`. Bare invocation on a terminal (or the `menu` subcommand) opens an interactive menu wrapping these actions (sync now mp3+mp4, dry-run preview, mp3-only, mp4-only, change source folder); flags stay scriptable |
| `pos media ytsync [add\|sync\|list\|remove]` | `bin/pos-media-ytsync` | Incremental YouTube channel/playlist sync — first run asks for a URL (bare invocation = interactive menu; empty state goes straight to the prompt), repeat runs fetch only new videos | One yt-dlp call per new video (`bestvideo*+bestaudio/best` → MP4, metadata/chapters/thumbnail embedded, `--no-overwrites`, `--windows-filenames --trim-filenames 120`); per-source `--download-archive` (`~/.local/share/linux_post_install/ytsync/archive/<slug>.txt`) makes runs crash-safe and idempotent; registry tracks slug/type/url/subdir. Verbs never prompt (scheduler/timer safe); non-tty interactive entry prints a guard line and exits 0. `--dry-run` probes + plans with zero writes. Notify digest only when new>0 or failed>0 via `lib/notify.sh`. Config: `YTSYNC_VIDEOS_DIR`, `YTSYNC_EXTRA_ARGS` via `pos config ytsync`; automate with `pos system schedule` (`COMMAND=pos media ytsync sync`, `NOTIFY=never`) |

A watch link carrying **both** `?v=` and `&list=` downloads only that single video
(`--no-playlist`) — nobody accidentally backfills a 500-video playlist from a watch
link; `youtu.be/<id>` short links count as watch links too. A pure playlist link
becomes a tracked playlist source with numbered
`<NNN> - <title>.mp4` files. `pos media ytsync remove <name>` stops tracking but
keeps the downloaded files AND the archive — re-adding the same source later
resumes incrementally instead of re-downloading. Members-only/age-gated videos are
reported as "N videos require sign-in — skipped" (escape hatch:
`YTSYNC_EXTRA_ARGS="--cookies …"` in `ytsync.env`). Research details:
`tools-docs/ytsync.md`.

### system

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `sudo pos system firewall` | `bin/pos-system-firewall` | Interactive UFW ("UFW POWER") menu: add/delete rules, status, enable/disable/reset, default policies | Must run as root. Every command is previewed and confirmed before execution; supports `--dry-run`; keeps a history of executed commands. Executed mutating changes are announced via `lib/notify.sh` |
| `pos system backup <folder-path>` | `bin/pos-system-backup` | Create a gpg-encrypted (AES-256) `tar.gz` snapshot of a folder and verify it | Prompts twice for a password (never stored; the passphrase is fed to gpg on an internal fd — `--passphrase-fd`, never via argv, so it cannot leak through `ps`). Uses `sudo tar`; needs `gnupg` (in `preinstall.sh` PACKAGES) only when encrypting. Artifact `<name>_<date>.tar.gz[.gpg]` in the current directory, `chmod 600`; `--no-encrypt` (or `BACKUP_ENCRYPT=0`) keeps a plain `.tar.gz` with no password prompt (headless/cron safe). Once the archive verifies, connected USB storage is offered (detected via `lsblk` TRAN with `lsusb`/by-id cross-check; unmounted sticks get a mount offer first — see `DOC/howto/system.md`; or pinned with `BACKUP_USB_ROOT`): the copy lands in `<usb>/backups/` and is proven 100% by sha256 before it is announced. Success/failure are announced via `lib/notify.sh`. Bare invocation on a terminal (or the `menu` subcommand) opens an interactive menu wrapping these modes (encrypted backup with typed folder, encrypted backup picked from the service roots, unencrypted variant) — each runs only after an explicit y/N confirm naming the folder; arguments stay scriptable |
| `pos system backup --service` | `bin/pos-system-backup` | Lists folders under `/srv` and `~/srv`, lets you pick one, then runs the same backup | Roots via `BACKUP_SERVICE_ROOTS` (space-separated, default `/srv $HOME/srv`) or `~/.config/linux_post_install/system.env` |
| `pos system health` | `bin/pos-system-health` | Host health dashboard: disk per mount, RAM/swap, failed systemd units, backup age, fail2ban, docker containers. Exits 1 if any check FAILs | Console-only reporter — health itself never sends notifications; forward the output with a wrapper (e.g. the Telegram/Matrix listener map `/status=pos system health`) or schedule it via `pos system schedule` with a `NOTIFY` policy. `HEALTH_BACKUP_MAX_AGE_DAYS` (default 2) and `BACKUP_SERVICE_ROOTS` come from `~/.config/linux_post_install/system.env`; `--help` shows the effective values |
| `pos system schedule <cmd>` | `bin/pos-system-schedule` | Scheduled jobs — run a command on a timer, notify (or stay silent): `run [name\|all]`, `list`, `config`, `enable [name\|all]`, `disable [name\|all]`, `status`, `migrate`. Each job is a file in `~/.config/linux_post_install/schedule.d/<name>.env` with `INTERVAL` (`5m…59m`, `1h…23h`, `hourly`, `daily`, `weekly`, `OnCalendar=…`), `NOTIFY` policy, optional `MSG`, `RULE` (threshold only), and `COMMAND` = the literal rest of the line (pipes/quotes/`sudo` fine). Policies: `always` (full output every run), `onchange` (send when output differs from the last run; first run always sends), `onerror` (non-zero exit or empty output), `threshold` (first numeric output vs `RULE`, alert on false→true + one recovery — the old event-trigger behavior), `never` (side-effect jobs, no notify) | One systemd **user** timer pair per job (`pos-schedule-<name>.timer` + oneshot `.service`, `Persistent=true`), reconciled on `enable`/`disable`; the legacy single `pos-event-trigger` timer is auto-removed. `migrate` converts a pre-existing `event.env` rule set into `schedule.d/rule-N.env` threshold jobs. `config` is an interactive editor (add/edit/remove/enable/disable, validates interval + threshold); alerts via `lib/notify.sh`; `--dry-run` previews runs/writes/sends; jobs are arbitrary shell commands (chmod 600, same trust model as the Telegram map); starter jobs in `config/schedule.d/` auto-installed no-clobber by postinstall. Bare invocation on a terminal (or the `menu` subcommand) opens an interactive hub over these verbs (list, timer status, run-now, enable, disable, config editor) — a menu run-now asks y/N first and goes through the same `run <name>` path the systemd timers use |
| `pos system uninstall` | `bin/pos-system-uninstall` | Safe, interactive uninstaller for the pos toolkit — scans and removes binaries, services, shell integration, config, and data in three tiers | Tier 1 (always): binaries in `/usr/local/bin/` (pos, pos-*, libs, ai-providers, entertainment plugins, prebuilt, features), systemd services (disable+remove) including runtime-created `~/.config/systemd/user/pos-*` user units, ScaleTail templates + feature-flag store under `/usr/local/share/linux_post_install/`, shell integration in `~/.bashrc` (PATH, completion, pos-ai-hook source), completion file. Tier 2 (`--config`): `~/.config/linux_post_install/` (.env files, schedule.d/, authorized_keys, rclone.conf). Tier 3 (`--data`): `~/.local/share/linux_post_install/` (ai sessions, logs, captured output). Flags: `--yes` (skip prompts, tier 1 only), `--config` (include tier 2), `--data` (include tier 3). Combine all three for nuclear removal. Git repo is never removed |
| `pos system bank` | `bin/pos-system-bank` | Persistent command bank for saving and running shell commands — list, add, show, run, edit, remove, alias | Commands stored in `~/.config/linux_post_install/bank.env` (pipe-delimited: `name\|description\|command`, chmod 600, managed by the tool). Parameterized `{param}` templates are substituted at run time. Interactive menu on a TTY with no args. `BANK_FILE` env seam overrides the path. `alias` subcommand manages bash aliases in `~/.bashrc` inside a managed `# >>> pos bank aliases …` block (`BASH_RC_FILE` env seam) |

A scheduled job is the recommended way to run the health dashboard on a timer: a `daily` job with `COMMAND=pos system health` and `NOTIFY=always` sends the dashboard output as the alert — no separate systemd unit needed (the old `pos-health.{service,timer}` units are gone; a legacy install may still have them failed/leftover — disable and remove them).

#### system bank

**File:** `bin/pos-system-bank`

Persistent command bank for saving and running shell commands. Commands are stored in `~/.config/linux_post_install/bank.env` (pipe-delimited: `name|description|command`, chmod 600, managed by the tool). Supports parameterized templates with `{param}` placeholders that are substituted at run time (quoted for safe shell evaluation).

On a TTY with no arguments, `pos system bank` opens an interactive menu (list / add / run / edit / remove).

| Command | Purpose |
|---------|---------|
| `pos system bank list` | List all saved commands |
| `pos system bank add <name> [desc] [cmd]` | Add a new command (interactive for missing args) |
| `pos system bank show <name>` | Show command details and detected parameters |
| `pos system bank run <name> [key=val …]` | Run a command (interactive for missing params) |
| `pos system bank edit <name>` | Edit an existing command |
| `pos system bank remove <name>` | Remove a command (also drops aliases pointing at it) |
| `pos system bank alias <name> [alias_name]` | Add/update a bash alias for a bank command (default alias name = bank name) |
| `pos system bank alias list` | List bash aliases from `~/.bashrc` |
| `pos system bank alias remove <alias_name>` | Remove a bash alias |

Aliases are bash aliases written into `~/.bashrc` inside a managed block
(`# >>> pos bank aliases … <<<`, `bashrc`-path seam: `BASH_RC_FILE`), as
`alias <alias_name>='pos system bank run <name>'` — retyping the same alias
name retargets the line; removing the last alias removes the whole block.
An alias name already defined outside the block is refused, and aliasing a
command that also exists on `PATH` prints a non-blocking warning (the alias
will shadow it in interactive shells).

Example with parameters:

```
pos system bank add convert "Convert video" "ffmpeg -i {input} -crf {quality} {output}"
pos system bank run convert input=clip.mp4 quality=23 output=clip.mkv
```

### ssh

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos ssh load-keys` | `bin/pos-ssh-load-keys` | Load all `~/.ssh/id_*` private keys into the ssh-agent | Uses `SSH_AUTH_SOCK` (default `/run/ssh-agent/socket`, provided by `ssh-agent.service`); skips `.pub`, `known_hosts`, `authorized_keys`, `config`; validates keys before adding |

### share

Share files and devices over the network (USB over network, NFS, SMB/Samba, WebDAV via rclone).

**File:** `bin/pos-share-usb-server`
**Purpose:** control the USB Redirector server (`usbsrv`) — share local USB devices over the network and manage connected clients. Requires `usbsrv` (manual install from incentivespro.com — not in `PACKAGES`).

| Command | Behavior |
|---------|----------|
| `pos share usb server --ls` | List host USB devices and connected clients |
| `pos share usb server --ls-shared` | List shared or in-use devices only |
| `pos share usb server --share [dev-id] [client-id]` | Share a device and connect it to a client; interactive picker when IDs are omitted (`-share` + `-connect-to CLIENT-DEV`) |
| `pos share usb server --unshare [dev-id]` | Stop sharing a device |
| `pos share usb server --auto-share on\|off` | Toggle automatic sharing of new devices |
| `pos share usb server --callback [addr:port]` | Create a callback connection to a client |
| `pos share usb server --close-callback [target\|all]` | Close a client callback |
| `pos share usb server --auto-connect on\|off [client]` | Toggle remote auto-connect for a client |
| `pos share usb server --disconnect [dev-id\|all]` | Disconnect a device from its clients |
| `pos share usb server --nickname [dev-id] [nick]` | Set a device nickname (empty nick removes it) |
| `pos share usb server --timeout [dev-id] [sec]` | Set device inactivity timeout (0 disables) |
| `pos share usb server --port [num]` | Set the TCP port (restart server to apply) |
| `pos share usb server --info` / `--version` | Show server info / version |

Subcommands that need input prompt interactively when args are omitted. Bare invocation (`pos share usb server`, no args) opens an interactive menu wrapping all of the above — device/client pickers parse the server listing, and when the listing can't be read it is shown raw with manual ID entry as fallback.

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos share nfs server <cmd>` | `bin/pos-share-nfs-server` | Manage the NFS kernel server: `status`, `share <path> [client]`, `unshare <path>`, `list`, `reload`, `enable`, `disable` | Requires `nfs-kernel-server` (added to `preinstall.sh` PACKAGES). Exports live in `/etc/exports`; `share` is idempotent (replaces any existing line for the path) and runs `exportfs -ra`. Default client `*(rw,sync,no_subtree_check)` — the tool warns you to restrict it; help prints Tailscale CGNAT (`100.64.0.0/10`), WireGuard (`10.10.0.0/24`) and LAN examples. Mutating commands announce via `lib/notify.sh`. Bare invocation opens an interactive menu (share/unshare/list/reload/enable/disable) — the share flow picks a folder from mounted candidates, names it, and offers client-spec presets (open/WireGuard/LAN/single-IP); inactive-service and UFW conflicts are surfaced as optional fixes |
| `pos share nfs client <cmd>` | `bin/pos-share-nfs-client` | Mount and manage NFS shares: `mount <server:export> <local-dir>`, `unmount <local-dir>`, `list`, `persist <server:export> <local-dir>`, `unpersist <local-dir>` | Requires `nfs-common` (added to `preinstall.sh` PACKAGES). `persist` writes a systemd `.mount` unit (`systemd-escape --path --suffix=mount`) with `After=network-online.target` / `Wants=network-online.target` — mounts only once all interfaces are up, no fstab edits to break boot — then `daemon-reload` + `enable --now`. `unpersist` stops/disables/removes the unit. `mount`/`persist` announce via `lib/notify.sh`. Bare invocation opens an interactive menu (mount/persist/unmount/unpersist/list) with mountpoint candidates + manual entry; unmount/persist removals are idempotent (already-absent targets are reported, not errors) |
| `pos share smb server <cmd>` | `bin/pos-share-smb-server` | Manage the Samba server: `status`, `share <path> [name] [--read-only|--guest|--users u1,u2]`, `unshare <name>`, `list`, `adduser <user>`, `deluser <user>`, `reload`, `enable`, `disable` | Requires `samba` (added to `preinstall.sh` PACKAGES). Shares are idempotent marker blocks (`# >>> pos-managed share: <name>` … `# <<< end pos-managed share`) in `/etc/samba/smb.conf` — hand edits outside the markers survive; `share` validates with `testparm` before applying and hot-reloads via `smbcontrol smbd reload-config`. Defaults rw + browsable; warns when unrestricted (guest or no `valid users`). `adduser`/`deluser` manage Samba accounts via `smbpasswd`. Mutating commands announce via `lib/notify.sh`. Bare invocation opens an interactive menu (share/unshare/list/users/reload/enable/disable) — the share flow picks a folder from mounted candidates and walks through read-only/guest/valid-users confirms; UFW conflicts are surfaced as an optional fix |
| `pos share smb client <cmd>` | `bin/pos-share-smb-client` | Mount and manage SMB/CIFS shares: `mount <//server/share> <local-dir> [user]`, `unmount <local-dir>`, `list`, `persist <//server/share> <local-dir> [user]`, `unpersist <local-dir>` | Requires `cifs-utils` (added to `preinstall.sh` PACKAGES). With a user you are prompted for the Samba password — one-shot mounts use a throwaway chmod-600 credentials file, `persist` keeps one at `/etc/samba/credentials/<name>` (chmod 600). `persist` writes systemd `.mount` **and** `.automount` units (`systemd-escape --path --suffix=mount`) with `_netdev` — the automount defers the actual mount until first access, never blocks boot — then `daemon-reload` + `enable --now` the automount. `unpersist` stops/disables/removes both units + credentials. `list` shows active mounts (`findmnt -t cifs`) **and** persistent units (as automount shares aren't mounted until first access, they'd otherwise be invisible). `mount`/`persist` announce via `lib/notify.sh`. Bare invocation opens an interactive menu (enumerate/mount/persist/unmount/unpersist/list): it can enumerate Disk shares via smbclient (empty user = guest try, auth retry on denial), pick a share + mountpoint from candidates (manual entry fallback), and reuses the authenticated account for the mount |
| `pos share webdav <cmd>` | `bin/pos-share-webdav` | Serve folders over WebDAV via rclone: `status`, `share <path> [opts]`, `unshare <path>`, `list`, `enable <path> [opts]`, `disable [path]` | Requires `rclone` (already in `preinstall.sh` PACKAGES). Single Basic-auth user, no config file, no user database — auth is mandatory by default with precedence flags > environment > `~/.config/linux_post_install/webdav.env` (chmod 600, values masked in all output): `--user` names the user, the password comes from `WEBDAV_PASS` (env or file) or a TTY prompt (there is no `--pass` flag — the password is never passed on argv), and a missing password errors out non-interactively. `--no-auth` serves WITHOUT authentication and warns (ANY network client can read and write the folder, like the NFS open export); `--read-only` restricts a share to reads; `--port`/`--addr` set the listen address (default `:8080`); `--cert`/`--key` serve over TLS (HTTPS). Plain HTTP is documented-OK only for Tailscale clients (`100.64.0.0/10`) — serving an address reachable beyond it without TLS warns. There is deliberately no `reload` (`rclone serve webdav` reads no config file — re-run `share`/`enable` to apply changed settings). `share` serves a folder now in the background (restarts the serve when already serving the same path); `unshare`/`disable` are idempotent (rc 0 when nothing exists, bare `disable` removes all WebDAV units). `enable` writes a persistent user systemd unit ordered after `network-online.target` (auth is persisted to `webdav.env` and referenced via `EnvironmentFile`, so the secret stays out of the unit). `status` shows running serves + persistent units (addresses shown, passwords masked) + masked defaults + a firewall advisory; UFW conflicts are surfaced as an optional fix. Mutating commands announce via `lib/notify.sh`. Bare invocation opens an interactive menu (folder → scope → auth) |

### communication

| Command | File | Purpose | Configuration |
|---------|------|---------|---------------|
| `pos communication telegram sender send "text"` | `bin/pos-communication-telegram-sender` | Send a message, link, or media file (auto-detects the type) to a Telegram chat via the Bot API | Token + chat ID from `~/.config/linux_post_install/telegram.env` (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`, chmod 600). Precedence: `--token`/`--chat-id` flags > env > config file |
| `pos communication telegram listener` | `bin/pos-communication-telegram-listener` | Telegram bot listener: map `/command` → bash commands and `<prefix>` → apps, run them from chat; interactive editor for the map | Same `telegram.env` (the bot is the owner, `TELEGRAM_CHAT_ID`; commands also require `TELEGRAM_OWNER_ID` — see the detail block). Map lives in `~/.config/linux_post_install/telegram_commands.env` (`/cmd=bash command` lines); text-prefix app map in `telegram_prefixes.env` (`<word>=command` lines) — both chmod 600 |
| `pos communication matrix sender send "text"` | `bin/pos-communication-matrix-sender` | Send a text message (plain or `--markdown`) to a Matrix room via the client-server API; also `login` (password → access token) and `test` | Homeserver + room from `~/.config/linux_post_install/matrix.env` (`MATRIX_HOMESERVER`, `MATRIX_ACCESS_TOKEN`, `MATRIX_USER_ID`, `MATRIX_ROOM_ID`, chmod 600, secrets masked by `pos config matrix`). Precedence: `--room` flag > env > config file |
| `pos communication matrix listener` | `bin/pos-communication-matrix-listener` | Matrix listener: map `/command` → bash commands and run them from room messages; interactive editor for the map | Same `matrix.env` (reacts to `MATRIX_USER_ID`'s own messages only, in the room set by `MATRIX_ROOM_ID` — unset = fail-closed, no commands run). Map lives in `~/.config/linux_post_install/matrix_commands.env` (`/cmd=bash command` lines, chmod 600) |
| `pos communication scrcpy [cmd]` | `bin/pos-communication-scrcpy` | Mirror/control an Android device via scrcpy+adb: `devices`, `record`, `tcpip`, `connect`, `push`, `pull`, `screenshot`, `info` (bare = mirror) | `scrcpy.env` (`SCRCPY_SERIAL`, `SCRCPY_MAX_SIZE`, `SCRCPY_MAX_FPS`, `SCRCPY_BIT_RATE`, `SCRCPY_FULLSCREEN`, `SCRCPY_RECORD_DIR`, `SCRCPY_PUSH_TARGET`, `SCRCPY_EXTRA_FLAGS`) via `pos config scrcpy` |

`pos communication telegram sender` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication telegram sender send "text"` | POSTs `sendMessage` to the Bot API (60s timeout); prints `[+] message sent to chat <id>` or fails with a nonzero exit |
| `pos communication telegram sender send <value>` | **Auto-detects the type** when `--type` is omitted: existing file → `file` (except `.webp` → sticker, `.gif` → animation, images → photo, video/audio/voice extensions → their type), value starting with `http://`/`https://`/`www.` → `link`, otherwise `message` |
| `pos communication telegram sender send <path> --type file [--caption "…"]` | Uploads a file as a `sendDocument` via multipart (`document=@path`); `--caption` adds a caption. Path must exist and be readable |
| `pos communication telegram sender send <path> [--caption "…"]` | Media uploads via their Bot API endpoint: `--type photo` → `sendPhoto`, `video` → `sendVideo`, `audio` → `sendAudio`, `voice` → `sendVoice`, `animation` → `sendAnimation`, `sticker` (`.webp`) → `sendSticker` (captions not supported for stickers) |
| `pos communication telegram sender send "url" --type link [--no-preview]` | Sends a link as a message (URLs auto-linkify); `--no-preview` adds `disable_web_page_preview=true` |
| `pos communication telegram sender send "text" --parse-mode <mode>` | Send with Telegram formatting; `<mode>` is `plain` (default), `markdown`, or `html` (passed as `parse_mode` to the API — also applies to captions). Markdown/HTML use raw Telegram syntax — unescaped characters may be rejected by the API (400) |
| `pos communication telegram sender send … --token <t> --chat-id <id>` | One-shot override of token/chat ID |
| `pos communication telegram sender test` | Sends a canned test message using the current config |

`send` option validation: `--caption` is only valid with media types (file/photo/video/audio/voice/animation), `--no-preview` only with `--type message`/`link`, and `--type` only accepts `message|file|link|sticker|photo|video|audio|voice|animation`. An explicit `--type` always overrides auto-detection.

The bot token is a secret — it is stored only in `~/.config/linux_post_install/telegram.env` and never in the repo. Edit `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` interactively with `pos config telegram` (masked input + display). Requires network access to `api.telegram.org`.

`pos communication telegram listener` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication telegram listener` | Interactive editor for the `/command` → bash map (`a`dd / `e`dit / `r`emove / `t`est / `q`uit); test-runs run `bash -n` first and may execute the command live |
| `pos communication telegram listener --status` | Shows service state (running/autostart), config + map file paths, and the mapped commands |
| `pos communication telegram listener --enable` | Installs + starts a systemd **user** service (`pos-telegram-listener.service`); the daemon polls `getUpdates` and runs mapped commands + text-prefix apps |
| `pos communication telegram listener --disable` | Stops, disables, and removes the service |
| `pos communication telegram listener --sync-commands` | Push the mapped `/commands` to the bot's `/` menu (`setMyCommands`) — also run automatically after every map edit, on `--enable`, and at daemon start |
| `pos communication telegram listener --run` | Run the polling loop in the foreground (what the service executes) |
| `pos communication telegram listener prefix` | List the text-prefix map (`telegram_prefixes.env`: `<word>=command` lines) plus the built-in Gemini bridge word |
| `pos communication telegram listener prefix <word>` | Show one mapping, or map `<word>` to a command with `prefix <word> <command...>` — non-command messages `<word> <text>` run the command with `<text>` appended as ONE quoted argument (e.g. `prefix opencode opencode` → "opencode check cpu" runs `opencode "check cpu"`). `prefix -r <word>` removes. Mapped words shadow the Gemini bridge; the bridge word itself (`TELEGRAM_AI_PREFIX`, default `ai`) is set via `pos config telegram` |

The map file is re-read for every message — edits apply without a restart. A command runs only when the message is sent to the owner chat (`TELEGRAM_CHAT_ID`) BY the owner account (`TELEGRAM_OWNER_ID`) — both must match, so a forwarded message or an impersonator can't trigger commands; with `TELEGRAM_OWNER_ID` unset the daemon starts but refuses every command (fail-closed). `/help` lists mapped commands; an unmapped command replies "Unknown command".

**Text-prefix map** (`telegram_prefixes.env`, managed via the `prefix` verb): for apps, not bash snippets — a non-command message `<word> <text>` runs the mapped command with `<text>` appended as ONE quoted argument, e.g. `opencode=opencode` turns "opencode check cpu" into `opencode "check cpu"`. First match wins (file order), matching is case-insensitive and the word must be space-delimited (bare `<word>` with no trailing space replies Unknown command). Values are syntax-checked on save; `@quiet ` values suppress the reply; the 120s timeout + empty→`OK` + `exit <rc>` reply mirror the command map. Routing order on every non-command message: text-prefix map → AI bridge → `/command` map → "Unknown command".

**AI bridge**: non-command text starting with `<word> ` — default `ai `, configurable via `pos config telegram` → `TELEGRAM_AI_PREFIX` (a text-prefix entry with the same word shadows it) — is forwarded to Gemini via `pos ai gemini ask` (case-insensitive, e.g. `ai what is Nvidia` or `BOT what is Nvidia` with prefix `bot`) and the answer is replied verbatim; an AI failure replies the error. Commands run as your user via `timeout bash -c "…"` (stdout + stderr are replied, truncated to ~3800 chars; empty output → `OK`), so `sudo` inside them needs a NOPASSWD rule. A map value prefixed with `@quiet ` runs the command but does NOT reply — for commands that already send their own notification (e.g. `pos system backup` self-notifies, so `/backup=@quiet pos system backup $HOME/Documents` avoids a double message). `--enable` warns if linger is off — the service stops when you log out unless you run `sudo loginctl enable-linger $(whoami)`.

Map entries may carry an optional **description** shown in the bot's `/` menu: `/cmd::short description=bash command` (the description falls back to the bash command, truncated to ~40 chars, when omitted). After every add/edit/remove the command list is pushed to the bot via `setMyCommands`, so the menu stays in sync; an empty map clears the menu. Telegram only registers lowercase `[a-z0-9_]` names (1–32 chars) — commands like `/Status` or `/my-cmd` are skipped from the menu with a warning but still resolve when typed.

`pos communication matrix sender` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication matrix sender send "text"` | PUTs an `m.room.message` (`m.text`) to the homeserver's client-server API v3 (60s timeout); prints `[+] m.text sent to room <room>` or fails with a nonzero exit. Room id/alias is URL-encoded automatically; a unique transaction id (`<timestamp>ns`) is generated per message |
| `pos communication matrix sender send "text" --markdown` | Sends with `format: org.matrix.custom.html` — a best-effort markdown → HTML conversion (`**bold**`, `__bold__`, `*em*`, `_em_`, `` `code` ``, ``` ```fences``` ``, `~~strike~~`, `[link](url)`, headers, list items). Deliberately simple; it never fails the send |
| `pos communication matrix sender send "text" --room <id\|alias>` | One-shot override of the room for this send only (e.g. `--room '#ops:example.org'`) |
| `pos communication matrix sender login --user <@id>` | Prompts (masked) for the account password, POSTs `m.login.password` to `/login`, and saves the returned `access_token` + `user_id` to `matrix.env` |
| `pos communication matrix sender test` | Sends a canned test message (`Test message from pos <timestamp>`) using the current config |

The access token is a secret — it is stored only in `~/.config/linux_post_install/matrix.env` and never in the repo. `pos config matrix` edits `MATRIX_HOMESERVER`, `MATRIX_ACCESS_TOKEN` (masked), `MATRIX_USER_ID`, `MATRIX_ROOM_ID`. Requires network access to your homeserver. The sender implements the `lib/notify.sh` sender contract, so `matrix` can be added to `NOTIFY_PLATFORM` for multi-platform alerting.

`pos communication matrix listener` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication matrix listener` | Interactive editor for the `/command` → bash map (`a`dd / `e`dit / `r`emove / `t`est / `q`uit); test-runs run `bash -n` first and may execute the command live |
| `pos communication matrix listener --status` | Shows service state (running/autostart), config + map file paths, and the mapped commands |
| `pos communication matrix listener --enable` | Installs + starts a systemd **user** service (`pos-matrix-listener.service`); the daemon long-polls `/sync` and runs mapped commands |
| `pos communication matrix listener --disable` | Stops, disables, and removes the service |
| `pos communication matrix listener --run` | Run the polling loop in the foreground (what the service executes) |

The daemon long-polls `/sync` (30s timeout, per-sync `since` token, compact filter that drops presence/account_data/device noise and only requests `m.room.message` timeline events). It reacts only to messages **from `MATRIX_USER_ID`** (your own account — resolved via `/account/whoami` if unset), and only in the room set by `MATRIX_ROOM_ID` — without it the daemon starts but runs no commands (fail-closed), so a bot account in many rooms can't be tricked. `/` and `!` prefixes both resolve (`!status` = `/status`). `/help` lists mapped commands; an unmapped command replies "Unknown command". Non-command text starting with `ai ` (case-insensitive, e.g. `ai what is Nvidia`) is forwarded to Gemini via `pos ai gemini ask` with a per-room session (`matrix-<room>`; `ai /reset` clears it) and the answer is replied verbatim with markdown stripped. Replies are sent as `m.text` threaded with `m.in_reply_to` on your message. Commands run as your user via `timeout 60 bash -c "…"` (stdout + stderr are replied, truncated to ~3800 chars; empty output → `OK`; non-zero exit is prefixed with `exit <rc>`), so `sudo` inside them needs a NOPASSWD rule. A map value prefixed with `@quiet ` runs the command but does NOT reply — for commands that already send their own notification (e.g. `pos system backup` self-notifies, so `/backup=@quiet pos system backup $HOME/Documents` avoids a double message). Map lines may carry a `/cmd::description=…` description. `--enable` warns if linger is off — the service stops when you log out unless you run `sudo loginctl enable-linger $(whoami)`.

`pos communication scrcpy` in detail:

| Command | Behavior |
|---------|----------|
| `pos communication scrcpy` | Mirror the device: opens the scrcpy window (needs a display — over ssh use `ssh -X`). Built from `scrcpy.env` defaults plus any pass-through scrcpy flags (`pos communication scrcpy --turn-screen-off --stay-awake`) |
| `pos communication scrcpy --new-display[=…]` | Mirror to a new virtual display on the phone (no need to mirror the real screen): `--new-display` (default size/dpi), `--new-display=1920x1080`, `--new-display=1920x1080/420` or `--new-display=/240`. Also settable persistently via `SCRCPY_NEW_DISPLAY` || `pos communication scrcpy devices` | `adb devices -l` — the source of serials for `SCRCPY_SERIAL` |
| `pos communication scrcpy record [file] [--headless]` | Record a session to an mp4 — default `$SCRCPY_RECORD_DIR/<device>_<date>.mp4`; `--headless` adds `--no-playback` (no window — headless-server friendly) |
| `pos communication scrcpy tcpip [port]` | `adb tcpip <port>` (default 5555) — switch the USB device to wireless adb, prints the reconnect command with the detected device IP |
| `pos communication scrcpy connect <ip[:port]>` | `adb connect` then mirror over WiFi (`-s <ip:port>`) |
| `pos communication scrcpy push <local> [remote]` | `adb push` — default destination `$SCRCPY_PUSH_TARGET` (`/sdcard/Download`, scrcpy's own default) |
| `pos communication scrcpy pull <remote> [local]` | `adb pull` — default local dir is the current directory |
| `pos communication scrcpy screenshot [file]` | `adb exec-out screencap -p` → a PNG, default `$SCRCPY_RECORD_DIR/<device>_<date>.png` |
| `pos communication scrcpy info` | Device model, Android version, SDK, serial (`adb shell getprop`) |

A device must have **USB debugging** enabled (Developer options) and the phone's "allow USB debugging" dialog accepted on first connect. `devices`, `record --headless`, `tcpip`, `connect`, `push`/`pull`, `screenshot`, `info` work without a display; the bare mirror needs one.

**Configuration** (`~/.config/linux_post_install/scrcpy.env`, edit with `pos config scrcpy`):

| Key | Required | Default | Purpose |
|-----|----------|---------|---------|
| `SCRCPY_SERIAL` | no | — | Default device serial/`ip:port` (from `devices`) — passed as `-s` to adb/scrcpy |
| `SCRCPY_MAX_SIZE` | no | — | Limit video size, e.g. `1920` (scrcpy `--max-size`) |
| `SCRCPY_MAX_FPS` | no | — | Limit frame rate, e.g. `60` (scrcpy `--max-fps`) |
| `SCRCPY_BIT_RATE` | no | — | Video bit rate, e.g. `8M` (scrcpy `--video-bit-rate`) |
| `SCRCPY_FULLSCREEN` | no | `false` | `true` adds `--fullscreen` |
| `SCRCPY_NEW_DISPLAY` | no | — | New virtual display on the phone (`--new-display`): `true` (default size/dpi), `1920x1080`, `1920x1080/420` or `/240` |
| `SCRCPY_AUDIO` | no | `true` | Forward device audio to the desktop (scrcpy default). `false` adds `--no-audio` |
| `SCRCPY_RECORD_DIR` | no | `~/Videos/scrcpy` | Output dir for `record`/`screenshot` defaults |
| `SCRCPY_PUSH_TARGET` | no | `/sdcard/Download` | Default `adb push` destination |
| `SCRCPY_EXTRA_FLAGS` | no | — | Extra scrcpy flags appended to every mirror |

Requires `scrcpy` + `adb`. `adb` is in `preinstall.sh` PACKAGES; `scrcpy` is **not** — apt rarely ships it on Debian/Ubuntu without contrib/universe (and it's older there anyway), so it installs via the optional app `apps/media/scrcpy.sh` (GitHub latest release, bundles `adb`); run it via `./install.sh --apps` or directly. The tool errors with that hint when `scrcpy` is missing.

### entertainment

**File:** `bin/pos-entertainment-send` (management subcommands: `bin/pos-entertainment-config`, `bin/pos-entertainment-enable`, `bin/pos-entertainment-disable`, `bin/pos-entertainment-status`)
**Purpose:** run a public-API plugin and send its output via `notify_send` — the platform follows `NOTIFY_PLATFORM` (default Telegram, silent-fail when none configured). Plugins are standalone scripts in `entertainment/` that fetch a public API and **print the message to stdout** — that stdout is what gets sent.

| Command | Behavior |
|---------|----------|
| `pos entertainment send` | List available plugins + usage |
| `pos entertainment send <plugin> [--print] [--markdown] [args…]` | Run the plugin, send its output via `notify_send` (silent) |
| `pos entertainment send <plugin> --print` | Print the output locally; do not send |
| `pos entertainment send <plugin> --markdown` | Send with Markdown parse_mode (via the notify senders) |
| `pos entertainment config` | Show the config file (`~/.config/linux_post_install/entertainment.env`) |
| `pos entertainment config get KEY` | Print one key's current value (`(not set)` if absent) |
| `pos entertainment config set KEY=VALUE…` | Set keys (any UPPER_SNAKE key; warns if no installed plugin uses it) and re-sync the schedule |
| `pos entertainment config unset KEY` | Remove a key from the config file |
| `pos entertainment config ls` | Declared keys with their current values, aligned |
| `pos entertainment config edit` | Interactive editor for the scope (via `pos config` UI) |
| `pos entertainment enable <plugin> [interval]` | Add plugin to `ENABLED` + schedule it as a systemd user timer |
| `pos entertainment disable <plugin>` | Remove plugin from `ENABLED` + remove its scheduled job |
| `pos entertainment status` | Enabled plugins (each with interval + last run), installed-but-not-enabled plugins, scheduler + timers |

**Plugin lookup order:** `$ENTERTAINMENT_DIR` → repo `entertainment/` → `/usr/local/bin/` (installed by `install.sh` Phase 2, beside the runner). A plugin name matches the file name with or without the `.sh` suffix.

Plugins:

| Plugin | Source API | Config |
|--------|-----------|--------|
| `weather` | Open-Meteo (no API key) | `~/.config/linux_post_install/entertainment.env`: `WEATHER_LAT`, `WEATHER_LON` (required), `WEATHER_CITY` (optional label) |
| `joke` | icanhazdadjoke.com (no API key) | None |
| `gold` | goldprice.dev (no API key, anonymous free tier) | None |

**Config auto-install:** `postinstall.sh` copies the repo's `config/entertainment.env` (a commented template showing each key's syntax) to `~/.config/linux_post_install/entertainment.env` on install — but only if you haven't already created your own (no clobber), and prints the template so you can fill in your location. Fill in `WEATHER_LAT`/`WEATHER_LON` (and optionally `WEATHER_CITY`) to enable the weather plugin.

**Adding a plugin:** drop an executable script in `entertainment/` (e.g. `myfeed.sh`) with a `# POS_PLUGIN: <name>` marker — the runner lists and validates plugins by this marker, so non-plugin `.sh` files in the shared `/usr/local/bin` are ignored. The plugin must be non-interactive and print the message to stdout; errors go to stderr (exit nonzero). Source `lib/entertainment-plugin-lib.sh` for the standard helpers — `plugin_load_config` (reads `entertainment.env`, env precedence), `plugin_have <cmd>`, `plugin_require KEY <desc>`, `plugin_http_json <url> [--key <jq>] [-H <header>]` (curl, 2 retries, timeout) — it never writes to stdout, so the message stays clean. No registration needed. Dependencies beyond `curl`/`jq` (both in `preinstall.sh` PACKAGES) should be guarded with `plugin_have`.

**Declaring config keys (pattern):** document every key the plugin reads with one `# POS_KEYS:` line right after `# POS_PLUGIN:` — `KEY`, a description, and `(required)`/`(optional)`:

```
# POS_PLUGIN: myfeed
# POS_KEYS: MYFEED_URL <feed url> (required)
# POS_KEYS: MYFEED_TAG <filter tag> (optional)
```

The plugin itself still reads the keys as plain env vars (`${MYFEED_URL:-}`). The declaration is what `pos entertainment config` uses to print its Keys section and to decide whether `config set` warns about an undeclared key — add the line whenever a plugin gets a new config key.

**Automation (auto-trigger):** enable plugins on a schedule via the `ENABLED` key in the config — a comma-separated list of `plugin, interval` pairs:

```
ENABLED="weather, 5m gold, 1h joke, daily"
```

`pos entertainment enable <plugin> [interval]` appends/updates one entry and re-syncs; `pos entertainment disable <plugin>` removes it; `pos entertainment config set ENABLED="…"` replaces the whole list. Scheduling uses **systemd user timers** (requires a reachable user systemd manager):

- One **user timer** per enabled plugin (`~/.config/systemd/user/pos-entertainment-<plugin>.{service,timer}`), running `pos entertainment send <plugin>` as your user on that schedule (`OnCalendar` + `Persistent=true`). `pos entertainment enable` also tries `sudo loginctl enable-linger $USER` once so timers fire without login.

The job runs as you, so it reads your `$HOME` configs (weather location, notify platform) natively — no `Environment=HOME=` hacks.

Intervals: `5m 10m 15m 30m 45m hourly 2h 6h 12h daily weekly`, or a raw `OnCalendar=…` spec. Default when omitted: `daily`.

`pos entertainment status` shows the enabled plugins (each with interval + last run), the installed-but-not-enabled plugins, the scheduler, and each plugin's next fire time (`systemctl --user list-timers`). Last run is recorded by `pos entertainment send` on every non-`--print` run (`~/.local/share/linux_post_install/entertainment/last/<plugin>`); a run that fails while fired by a timer also notifies the configured platforms.

Notes:
- The runner is headless/timer-friendly — no TTY prompts, exit 0 on success / 1 on failure.
- Scheduling is per-user for the user who runs `enable`; if you manage a different machine's user (e.g. via `runuser`/`sudo -u`), run the `enable`/`disable` commands as that user.
- The unit template (`TimeoutStopSec=5s`, `Persistent=true`, network-online deps) is shared with the system scheduler via `lib/user-timers-lib.sh`.

### flags

Feature-flag management CLIs (see [SCRIPTS.md → lib/flags.sh](SCRIPTS.md#libflagssh--feature-flags)):

| Command | Purpose |
|---------|---------|
| `flag-reader` | List all flags + status (`set: <name>` / `unset: <name>`) |
| `flag-reader <name>` | Check one flag; exit 0 if set, 1 if not |
| `flag-reader --raw <name>` | Print only the stored value (script-friendly) |
| `flag-set <name> [value]` | Set a flag, optionally with a value (requires sudo) |
| `flag-clear <name>` | Unset a flag (requires sudo) |

### config

**File:** `bin/pos-config`

`pos config` is the interactive editor for the tools' runtime config (see [DEV.md](DEV.md#config-files) and §10 of AGENT_Context). Every tool exposes its configuration by declaring a `# POS_CONFIG:` header; `pos config` reads those at runtime — it knows nothing about the variables themselves. Values live in `~/.config/linux_post_install/<scope>.env` (chmod 600).

Headers may also declare **group captions**: `@Caption` starts a visual group, and `@[KEY=v1|v2] Caption` makes the group conditional — while `KEY`'s current value matches none of the listed alternatives, the group stays visible but dimmed with a textual reason (`— inactive while KEY=…`), so row numbering never changes mid-session. Wildcards can be tagged: `*providers=<tag>` pulls keys from a single AI provider adapter instead of all of them. The listing renders uniformly for every scope (bold title/keys, dim numbers/examples/placeholders, word-wrapped descriptions); at the prompt type a number to edit, `r` to refresh, or `q` to quit.

| Command | Purpose |
|---------|---------|
| `pos config` | Scope picker (on a TTY), otherwise the scope list |
| `pos config <scope>` | Edit that scope's variables (masked secrets, validation, `-` to clear) |
| `pos config <scope> set KEY=VALUE` | Set a value non-interactively (each tool's `config set` form) |

### tree

**File:** `bin/pos-tree`

`pos tree` prints the `pos` command tree — every category, command, and subcommand the dispatcher can reach, annotated with each tool's `# POS:` description. Data is derived live from the `bin/pos-*` filenames and their `# POS_SUBCMDS:` headers, so it always matches what `pos` can actually run.

| Command | Purpose |
|---------|---------|
| `pos tree` | Full command tree |
| `pos tree --depth N` | Limit nesting depth (1 = root only) |

---

## Legacy wrappers

Thin 2-line scripts that `exec pos … "$@"`. All of them still work:

| Wrapper | Forwards to |
|---------|-------------|
| `wr-ip` | `pos network ip` |
| `wr-checkport` | `pos network checkport` |
| `wr-scan-ping` | `pos network scan` |
| `wr-docker` | `pos docker` |
| `wr-compose` | `pos docker compose` |
| `wr-ufw` | `pos system firewall` |
| `mp3` | `pos media mp3` |
| `mp4` | `pos media mp4` |
| `vbox` | `pos docker vbox` |
| `ssh-load-all` | `pos ssh load-keys` |
