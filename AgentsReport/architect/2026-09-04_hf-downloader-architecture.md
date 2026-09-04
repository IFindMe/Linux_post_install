# Architecture Report — `pos ai hf` (Hugging Face Model Downloader)

**Date:** 2026-09-04
**Status:** DECISION_READY

---

## TL;DR

| Decision | Choice | Rationale |
|----------|--------|-----------|
| File location | `bin/pos-ai-hf` | Subcommand of `ai` category — models are AI infrastructure |
| Subcommands | `download`, `search`, `list`, `remove` | Core + discovery + local management |
| Config scope | `ai` (existing) | No new scope needed — `HF_TOKEN` and `HF_DOWNLOAD_DIR` fit the existing `ai.env` |
| Default download dir | `~/.local/share/linux_post_install/ai/models/<repo-id>` | Follows XDG data conventions, matches `SESSION_DIR` parent |
| Dependencies | `curl`, `jq` | Already in `preinstall.sh` PACKAGES — no changes |
| Progress | curl `--progress-bar` | Native, no extra deps, works for multi-GB files |
| Resume | curl `-C -` | Automatic resume on interrupted downloads |
| New files created | `bin/pos-ai-hf` (1 file) | Minimal scope — everything else is doc updates |
| Open items | HOWTO.md + howto/ai.md updates (Writer task) | Not blocking implementation |

---

## Decision 1: File Location — `bin/pos-ai-hf`

**Problem:** Where does a Hugging Face model downloader live in the `pos` hierarchy?

**Evidence:**
- Existing AI tools: `bin/pos-ai` (692 lines), `bin/pos-ai-alias` (760 lines), `bin/pos-ai-gemini`/`bin/pos-ai-openrouter` (7-line forwarders) — all under the `ai` category
- The `ai` category covers AI providers, sessions, models, and assistants
- Downloading models is AI infrastructure — it feeds ollama, llama.cpp, and similar local inference tools
- The user's explicit context: "download AI models for local inference"

**Options:**

| Option | Architecture | Pros | Cons |
|--------|-------------|------|------|
| A: `bin/pos-ai-hf` | Subcommand of `ai` category | Consistent with existing AI tool hierarchy; `pos ai hf download` is natural; `pos ai --help` shows it alongside other AI tools | Slightly longer invocation path |
| B: `bin/pos-ai-download` | Named after the action, not the provider | Action-first naming | Conflates "AI download" with "HF download"; would need renaming when adding other model sources (e.g., CivitAI, Ollama registry) |
| C: `bin/pos-hf` | Own category | Shortest invocation | Breaks `ai` category coherence; HF is not a general tool category |

**Decision:** Option A — `bin/pos-ai-hf`

**Reasoning:** HF is a provider/source within the AI domain. The `ai` category already contains provider-specific tools (`pos-ai-gemini`, `pos-ai-openrouter`). Adding `pos-ai-hf` for model downloading fits this pattern perfectly. The tool name communicates both the domain (`ai`) and the source (`hf`).

**Convention compliance:**
- `# POS: ai hf — Download AI models from Hugging Face (search, download, manage)`
- No new category in `pos --help`
- Auto-discovered by `pos` dispatcher

[DECIDED]

---

## Decision 2: Subcommands

**Problem:** What operations should `pos ai hf` support?

**Evidence:**
- `pos media grab` pattern (file:83-141): thin classifier + delegator — minimal surface area
- `pos network download` (18 subcommands): comprehensive but for a complex download manager with queuing, torrents, retry logic
- `pos ai` pattern (file:1-10): flag-based with subcommands (`ask`, `chat`, `sessions`, `models`, `providers`)
- User goal: "Download AI models for local inference" — primary operation is download; search and local management are secondary

**Options:**

| Option | Subcommands | Pros | Cons |
|--------|-------------|------|------|
| A: download + search + list + remove | 4 subcommands | Full lifecycle; covers discovery, download, local management, cleanup | More surface area to maintain |
| B: download + list + remove | 3 subcommands | Core + local management; search can be done via `curl` manually | User must leave `pos` for discovery |
| C: download only | 1 subcommand | Minimal; simplest to implement and maintain | No local management; user must track paths manually |

**Decision:** Option A — `download`, `search`, `list`, `remove`

**Reasoning:**
- `download` is the primary operation (user goal)
- `search` is low-cost to implement (one API call, jq formatting) and high-value for discovery
- `list` shows what's already downloaded — essential for a model management workflow
- `remove` lets users clean up without manually tracking paths
- Total surface area is manageable — each subcommand is a single function, not a complex state machine

**Subcommand contracts:**

```
pos ai hf download <repo-id> [filename]     # Download a file or entire repo
pos ai hf download <repo-id> --files         # List files, then download selected
pos ai hf download <repo-id> --branch <rev>  # Download from a specific branch/commit
pos ai hf download <repo-id> --gguf          # Download only .gguf files (inference-ready)
pos ai hf search <query>                     # Search HF models
pos ai hf list                               # List downloaded models
pos ai hf remove <repo-id>                   # Remove a downloaded model
```

[DECIDED]

---

## Decision 3: Config Scope — Extend `ai.env`

**Problem:** Where do `HF_TOKEN` and `HF_DOWNLOAD_DIR` live?

**Evidence:**
- `# POS_CONFIG:` header format: `scope | file | KEY=:description | ...`
- Existing `ai` scope: `bin/pos-ai` line 6 — `# POS_CONFIG: ai | ai.env | AI_PROVIDER=…`
- HF download is an AI tool — its config logically belongs with other AI config
- Creating a new `hf` scope would add another `pos config` entry and `.env` file for just 2 keys
- The `pos config ai` command already exists and users would expect AI-related config there

**Options:**

| Option | Architecture | Pros | Cons |
|--------|-------------|------|------|
| A: Extend `ai.env` (existing scope) | `HF_TOKEN` and `HF_DOWNLOAD_DIR` added to `# POS_CONFIG: ai` in `bin/ai-hf` | One config location for all AI tools; user runs `pos config ai` to see everything | Mixes provider keys (GEMINI_API_KEY) with download config |
| B: New `hf.env` (new scope) | `# POS_CONFIG: hf | hf.env | HF_TOKEN=…` | Clean separation; `pos config hf` is self-contained | Another `.env` file; users must know which scope has the token |
| C: `system.env` (shared scope) | `HF_TOKEN` and `HF_DOWNLOAD_DIR` in system.env via `load_system_env()` | Centralizes shared config | Wrong semantic — HF is AI-specific, not system-wide |

**Decision:** Option A — Extend existing `ai` scope

**Reasoning:**
- The `ai` scope already holds `AI_PROVIDER` and `AI_GEMINI_API_KEY` — adding HF keys keeps all AI config in one place
- Users run `pos config ai` once to configure everything they need for AI tools
- No new scope registration, no new `.env` file, no new completion entry
- The `# POS_CONFIG:` header in `bin/pos-ai-hf` adds its keys to the same `ai` scope

**Header addition (in `bin/pos-ai-hf`):**
```bash
# POS_CONFIG: ai | ai.env | HF_TOKEN=:Hugging Face API token (https://huggingface.co/settings/tokens) (secret) | HF_DOWNLOAD_DIR=:Model download directory (default ~/.local/share/linux_post_install/ai/models)
```

[DECIDED]

---

## Decision 4: Download Directory Layout

**Problem:** Where do downloaded files land, and what directory structure?

**Evidence:**
- `SESSION_DIR="$HOME/.local/share/linux_post_install/ai"` (bin/pos-ai line 12) — data convention for AI tools
- `DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/Downloads}"` (bin/pos-network-download line 22) — general download convention
- Ollama expects models in `~/.ollama/models/` — not our concern (user moves files)
- llama.cpp uses `--model <path>` — just needs the path printed
- HF repos use `<namespace>/<model-name>` format (e.g., `meta-llama/Llama-3.1-8B-Instruct`)

**Decision:** Flat layout under XDG data directory

```
~/.local/share/linux_post_install/ai/models/
├── meta-llama-Llama-3.1-8B-Instruct/
│   ├── config.json
│   ├── model.safetensors
│   ├── tokenizer.json
│   └── .hf-meta          # our metadata: repo-id, branch, download date, files
├── Qwen-Qwen2.5-7B-Instruct/
│   ├── model-00001-of-00003.safetensors
│   └── ...
└── TheBloke-Mistral-7B-v0.1-GGUF/
    ├── mistral-7b-v0.1.Q4_K_M.gguf
    └── .hf-meta
```

**Key decisions:**
- **Folder name:** `<namespace>-<model-name>` (dash-joined, slashes replaced). Clean, filesystem-safe, human-readable.
- **Default base:** `~/.local/share/linux_post_install/ai/models/` (overridable via `HF_DOWNLOAD_DIR`)
- **`.hf-meta` file:** JSON metadata (repo-id, branch, download timestamp, file list). Enables `list` and `remove` without API calls.
- **No nesting by namespace:** Flat is simpler — users can see all models at a glance.

**Out of scope:** Integrating with ollama's model directory or llama.cpp's model directory. Users move files themselves or use `--output` flag.

[DECIDED]

---

## Decision 5: Download Logic

**Problem:** How to download files from HF repos reliably.

**Evidence:**
- HF REST API: `GET /api/models/{ns}/{repo}` returns file list (`siblings[].rfilename`)
- `GET /api/models/{ns}/{repo}/tree/{rev}/{path}` returns sizes + LFS info
- Large files (7GB+): curl `-L` transparently handles LFS, Xet, CDN redirects
- Rate limits: 500/5min anonymous, 1000/5min with token
- No single "download all" endpoint — must loop through file list
- `curl -C -` handles resume for interrupted downloads
- `--progress-bar` gives native progress for large files

**Download flow:**

```
1. Validate repo-id (must contain /)
2. Call GET /api/models/{ns}/{repo} → extract siblings
3. Filter files (by filename arg, --gguf flag, or download all)
4. For each file:
   a. Create target directory (mkdir -p)
   b. Construct download URL: https://huggingface.co/{ns}/{repo}/resolve/{rev}/{filename}
   c. curl -L -C - --progress-bar -H "Authorization: Bearer $HF_TOKEN" → target
   d. Verify file exists and is non-empty
5. Write .hf-meta (repo-id, branch, files, timestamp)
6. Print summary: path, total size, file count
```

**Key implementation details:**

| Concern | Solution |
|---------|----------|
| Auth | Always pass `Authorization: Bearer $HF_TOKEN` header — even public repos get better rate limits |
| Large files | `curl -L` handles LFS/Xet transparently; `--progress-bar` shows native progress |
| Resume | `curl -C -` resumes interrupted downloads automatically |
| Rate limiting | Sleep 1s between files; on 429, wait `Retry-After` header value or 60s default |
| Disk space | Pre-flight check: `df` available space vs estimated total (from `/tree/` endpoint) |
| Partial download | If curl fails mid-file, the partial file remains (resume on next run) |
| Gated repos | API returns 403 without token; with valid token, same flow works |

**File listing (for `--files` flag):**
```
GET /api/models/{ns}/{repo}/tree/main/ | jq to extract filenames + sizes
```

**Progress for multi-file downloads:**
- Single file: curl `--progress-bar` is sufficient
- Multi-file: Print `[N/M]` counter before each file's download, curl `--progress-bar` for each

**Avoided complexity:**
- No aria2 dependency (pos-network-download pattern) — curl is sufficient for sequential downloads
- No parallel downloads — complexity not justified for single-user homelab use
- No streaming/progress tracking library — curl's native progress bar is enough

[DECIDED]

---

## Decision 6: Output Contract

**Problem:** What does the tool print?

**Evidence:**
- `pos media grab` prints: emoji + title + path + size (file:202-226)
- `pos network download add` prints: GID for tracking
- User goal: "Print the path so the user knows where files landed"
- Tool output goes to stdout (captured by `tee` for logging)

**Decision:** Structured, parseable output with human-friendly summary

```
# Single file download:
📥 Downloaded: meta-llama/Llama-3.1-8B-Instruct/model.safetensors (4.7 GB)
📁 ~/.local/share/linux_post_install/ai/models/meta-llama-Llama-3.1-8B-Instruct/model.safetensors

# Multi-file download:
📥 Downloaded: meta-llama/Llama-3.1-8B-Instruct (7 files, 4.7 GB)
📁 ~/.local/share/linux_post_install/ai/models/meta-llama-Llama-3.1-8B-Instruct/

# Search results:
Found 5 models for "llama 7b":
  meta-llama/Llama-2-7b-chat-hf         12.3k downloads  13.5 GB
  NousResearch/Llama-2-7b-hf             8.2k downloads   13.5 GB
  ...

# List:
Downloaded models (3):
  meta-llama-Llama-3.1-8B-Instruct    4.7 GB   2026-09-04
  Qwen-Qwen2.5-7B-Instruct            4.2 GB   2026-09-03
  TheBloke-Mistral-7B-v0.1-GGUF       4.1 GB   2026-09-02

# Remove:
Removed: meta-llama-Llama-3.1-8B-Instruct (freed 4.7 GB)
```

**stdout contract:**
- Summary lines go to stdout (logged by `tee`)
- Progress bars go to stderr (not logged)
- Errors go to stderr via `err()` (exits 1)

[DECIDED]

---

## Decision 7: Error Handling

**Problem:** How to handle failure modes gracefully.

**Evidence:**
- `pos network download` has comprehensive error handling for RPC failures, dead sources, outages
- `pos media grab` has URL validation and delegation failure summary
- `err()` from common.sh exits 1 with red message
- Network tools need to handle transient failures

**Error matrix:**

| Error | Detection | Response |
|-------|-----------|----------|
| Missing deps | `command -v` guard before `--help` | `err "curl not found (install curl)"` — exits before help |
| Invalid repo format | No `/` in repo-id | `err "Invalid repo format: use namespace/model-name"` |
| 404 (repo not found) | HTTP status from API | `err "Model not found: {repo-id}"` |
| 401/403 (auth) | HTTP status | `err "Authentication failed — check HF_TOKEN (pos config ai)"` |
| 429 (rate limit) | HTTP status | Sleep `Retry-After` or 60s, retry once, then fail |
| Network timeout | curl exit code 28 | `err "Connection timed out — check network"` |
| Disk space | `df` pre-flight | `warn "Low disk space: need {N} GB, only {M} GB available"` then continue (user's call) |
| Partial download | curl exit code != 0 | `warn "Download interrupted for {file} (resume with same command)"` — partial file stays |
| jq parse error | jq exit code | `err "Failed to parse API response — check network or HF status"` |
| Token not set | Empty after config load | `warn "No HF_TOKEN set — using anonymous access (lower rate limits)"` — continue for public repos |

**Design principle:** Never fail silently. Always tell the user what happened and how to fix it. For transient errors, offer resume guidance.

[DECIDED]

---

## Decision 8: Dependencies and Lint Compliance

**Problem:** What deps are needed, and how to satisfy the lint gate?

**Evidence:**
- `curl` and `jq` are in `preinstall.sh` PACKAGES (line 29: `git curl wget aria2 vim nano tmux tree jq`)
- Deps guards must sit **before** `-h|--help` case (DEV.md line 110, lint rule)
- `set -euo pipefail` required (lint rule)
- `# POS:` header required (lint rule)
- No stdin reading → not in `INTERACTIVE_CMDS` (lint rule)

**Lint compliance checklist:**

| Rule | Requirement | Implementation |
|------|-------------|----------------|
| Shebang | `#!/usr/bin/env bash` | Line 1 |
| Strict mode | `set -euo pipefail` | Line 2 |
| `# POS:` header | After shebang/strict-mode | Lines 3-7 |
| Deps guards before `--help` | `command -v` guards before case | After source, before case |
| `-h|--help` via case | `case "${1:-}" in -h\|--help) usage ;;` | Standard pattern |
| Exec bits | 100755 | `chmod +x` on creation |
| No stdin | Not in `INTERACTIVE_CMDS` | True — non-interactive tool |
| Source chain | `source "$(dirname "$0")/../lib/common.sh" 2>/dev/null \|\| source "$(dirname "$0")/common.sh"` | Standard pattern |

**No new packages needed.** `curl` and `jq` are already installed by `preinstall.sh`.

[DECIDED]

---

## Decision 9: Testing Strategy

**Problem:** How to verify the tool works without a live HF token or network.

**Evidence:**
- DEV.md (line 196-214): Stub PATH approach — fake binaries, temp HOME, assert on output
- `pos network download` test pattern: fake curl/systemctl stubs with JSON fixtures
- `pos system backup` test pattern: per-test lsblk JSON fixtures in temp dirs
- Env-overridable paths: `HF_DOWNLOAD_DIR` is the seam

**Test architecture:**

```
/tmp/opencode/hf-test/
├── run-tests.sh          # Test runner with check() helper
├── stubs/
│   ├── curl              # Fake curl: returns fixtures based on URL pattern
│   └── jq                # Pass-through (real jq with fixture data)
└── fixtures/
    ├── model-meta.json   # GET /api/models/{ns}/{repo} response
    ├── model-tree.json   # GET /api/models/{ns}/{repo}/tree/ response
    └── search.json       # GET /api/models?search=... response
```

**Test cases (target: ~40-50 cases):**

| Category | Cases |
|----------|-------|
| Argument parsing | Missing repo-id, invalid format (no /), unknown subcommand, unknown flag |
| download | Single file download, whole repo download, --gguf filter, --branch, resume (partial file exists), 404 error, 401 error, 429 rate limit |
| search | Successful search, empty results, network error |
| list | Empty list, populated list, corrupted .hf-meta |
| remove | Successful remove, nonexistent model, remove frees space |
| Config | Token from env, token from file, download dir override |
| Output | Summary format matches contract, paths are correct |
| Edge cases | Empty repo, very long filename, special characters in repo-id |

**Stub `curl` behavior:**
- Intercepts calls to `huggingface.co`
- Routes `/api/models/` to fixture files
- Routes `/resolve/` to a fake download (creates a small file)
- Simulates error codes (401, 403, 404, 429)
- Tracks call count for assertion

**No changes to the repo's test infrastructure** — tests live in `/tmp/opencode/` per convention.

[DECIDED]

---

## Function Signatures

### Config

```bash
load_hf_config()
# Reads HF_TOKEN and HF_DOWNLOAD_DIR from:
#   1. Already-exported env vars (highest precedence)
#   2. ~/.config/linux_post_install/ai.env (HF_TOKEN, HF_DOWNLOAD_DIR)
#   3. Defaults: HF_DOWNLOAD_DIR=~/.local/share/linux_post_install/ai/models
```

### API Helpers

```bash
hf_api()  # hf_api <endpoint> → JSON response (GET only)
# Calls: curl -fsS -H "Authorization: Bearer $HF_TOKEN" "https://huggingface.co/api$endpoint"
# Handles: 401/403 auth errors, 429 rate limit (sleep + retry once), network errors

hf_repo_files()  # hf_repo_files <repo-id> [branch] → JSON array of {rfilename, size}
# Calls: GET /api/models/{ns}/{repo}/tree/{branch}/ for sizes, falls back to /api/models/{ns}/{repo} for file list

hf_search()  # hf_search <query> [limit] → JSON array of {id, downloads, likes}
# Calls: GET /api/models?search={query}&sort=downloads&direction=-1&limit={N}
```

### Download

```bash
hf_download_file()  # hf_download_file <url> <target> → 0/1
# curl -L -C - --progress-bar -H "Authorization: Bearer $HF_TOKEN" -o "$target" "$url"
# Returns: 0 on success, 1 on curl failure

hf_download_repo()  # hf_download_repo <repo-id> [branch] [filename|--gguf]
# Orchestrates: API call → file list → loop → download → write .hf-meta → summary
```

### Subcommands

```bash
cmd_download()  # cmd_download <repo-id> [args...]
# Dispatches: single file / whole repo / --files interactive / --gguf filter

cmd_search()    # cmd_search <query>
# Calls hf_search, formats table

cmd_list()      # cmd_list
# Scans $HF_DOWNLOAD_DIR, reads .hf-meta, prints table

cmd_remove()    # cmd_remove <repo-id>
# Validates exists, rm -rf, prints freed space
```

### Utilities

```bash
hf_repo_dir()      # hf_repo_dir <repo-id> → filesystem path (dash-joined)
# "meta-llama/Llama-3.1-8B-Instruct" → "$HF_DOWNLOAD_DIR/meta-llama-Llama-3.1-8B-Instruct"

hf_human_size()    # hf_human_size <bytes> → "4.7 GB" / "12.3 MB" / "1024 B"
# Same pattern as pos-media-grab (file:213-221)

hf_resolve_branch() # hf_resolve_branch <repo-id> [branch] → resolved branch
# Default "main"; calls API to get model metadata defaultBranch if not specified
```

---

## Config Keys

| Key | Scope | File | Default | Secret | Description |
|-----|-------|------|---------|--------|-------------|
| `HF_TOKEN` | `ai` | `ai.env` | (empty) | Yes | Hugging Face API token. Generate at huggingface.co/settings/tokens. Even for public repos, a token increases rate limits from 500/5min to 1000/5min. |
| `HF_DOWNLOAD_DIR` | `ai` | `ai.env` | `~/.local/share/linux_post_install/ai/models` | No | Base directory for downloaded models. Each repo gets a subdirectory named `<namespace>-<model-name>`. |

**Precedence:** env var > `ai.env` file > default (standard `load_config` pattern).

---

## File List and Responsibilities

### New files

| File | Purpose | Lines (est.) |
|------|---------|-------------|
| `bin/pos-ai-hf` | Main tool: download, search, list, remove | ~350-400 |

### Modified files

| File | Change | Scope |
|------|--------|-------|
| `DOC/POS.md` | Add `ai hf` to `ai` category table + detail block | Hand-written |
| `DOC/HOWTO.md` | Add row to AI category in index | Hand-written |
| `DOC/howto/ai.md` | Add Hugging Face download section (recipes, config, troubleshooting) | Hand-written |
| `DOC/AGENT_Context_Project.md` | GEN blocks auto-regenerated by `make gen` | Auto |

### NOT modified

| File | Reason |
|------|--------|
| `preinstall.sh` | `curl` and `jq` already in PACKAGES |
| `lib/common.sh` | No shared helpers needed — tool is self-contained |
| `bin/pos` | No `INTERACTIVE_CMDS` change (non-interactive tool); usage EXAMPLES updated by hand |
| `install.sh` | No new lib files to install |

---

## Approved Scope

### In scope

1. **Create `bin/pos-ai-hf`** — single file, ~350-400 lines
   - Subcommands: `download`, `search`, `list`, `remove`
   - Config: `HF_TOKEN`, `HF_DOWNLOAD_DIR` via `# POS_CONFIG: ai`
   - Deps guards for `curl` and `jq`
   - Full `--help` text
   - Error handling for all failure modes listed in Decision 7
   - Resume support (`curl -C -`)
   - Rate limit handling (sleep + retry on 429)
   - `.hf-meta` metadata tracking per downloaded repo

2. **Documentation updates** (Writer task, not blocking)
   - `DOC/POS.md`: `ai hf` row + detail block
   - `DOC/howto/ai.md`: Hugging Face section
   - `DOC/HOWTO.md`: index row

3. **Run gates**
   - `make gen && make check && make lint` must pass (0 FAIL, 0 WARN)

### Explicitly out of scope

- **Ollama integration** — no `ollama import` or model registration; user moves files manually
- **llama.cpp integration** — no quantization or conversion; just download
- **Parallel downloads** — sequential is sufficient for homelab use
- **Download queuing/history** — no aria2 dependency; simple curl-based downloads
- **Model conversion** — pure download tool, not a model pipeline
- **CivitAI/other sources** — HF only; other sources get their own tools if needed
- **Interactive file picker** — `--files` lists files and downloads all (or filtered); no interactive selection menu
- **New config scope** — extends existing `ai` scope, no new `pos config` entry
- **`pos ai` changes** — `bin/pos-ai` is not modified; `pos-ai-hf` is independent

---

## Architectural Constraints for Builder

1. **Start from template:** `cp templates/pos-tool.sh bin/pos-ai-hf`
2. **POS header must be on line ~4:** `# POS: ai hf — Download AI models from Hugging Face (search, download, manage)`
3. **Deps guards before `-h|--help` case:** `command -v curl` and `command -v jq` before the case
4. **Source chain:** Standard `source "$(dirname "$0")/../lib/common.sh" 2>/dev/null || source "$(dirname "$0")/common.sh"`
5. **Config loader pattern:** Copy `load_config()` from `bin/pos-ai` (lines 130-160) — read `ai.env`, env-var precedence, strip CR
6. **All file paths must be seam-guarded:** `HF_DOWNLOAD_DIR="${HF_DOWNLOAD_DIR:-$HOME/.local/share/linux_post_install/ai/models}"`
7. **Output to stdout only:** Summary lines. Progress bars and curl output to stderr.
8. **No INTERACTIVE_CMDS change:** Tool does not read stdin
9. **`make gen && make check && make lint` must pass** before handoff to Writer

---

## Verification

| Check | Command | Expected |
|-------|---------|----------|
| Syntax | `bash -n bin/pos-ai-hf` | No output, rc=0 |
| Exec bit | `ls -la bin/pos-ai-hf` | `-rwxr-xr-x` |
| POS header | `head -10 bin/pos-ai-hf` | Contains `# POS: ai hf —` |
| Help | `bin/pos-ai-hf --help` | Prints usage, rc=0 |
| Deps guard | Remove curl, run `bin/pos-ai-hf --help` | Error about curl, rc=1 |
| Dispatch | `bin/pos help ai hf` | Shows pos-ai-hf help |
| Category | `bin/pos ai --help` | Lists `hf` subcommand |
| Gen | `make gen` | Regenerates tree/dispatch/completions |
| Check | `make check` | 0 failures |
| Lint | `make lint` | 0 FAIL, 0 WARN |
| Stub tests | `/tmp/opencode/hf-test/run-tests.sh` | 40+ cases green |

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| HF API changes endpoint format | Low | Medium | Pin to v0 API (`/api/models/`); monitor HF changelog |
| Token exposure in logs | Medium | High | Token passed via header, not URL; never printed in output; `HF_TOKEN` marked as secret in POS_CONFIG |
| Very large repos (100+ files) | Low | Low | Sequential download with progress; user can Ctrl+C and resume |
| LFS pointer files downloaded instead of content | Low | Medium | `curl -L` follows LFS redirect; test with known LFS repo |
| Disk full during multi-file download | Medium | Medium | Pre-flight `df` check; partial files preserved for resume |
