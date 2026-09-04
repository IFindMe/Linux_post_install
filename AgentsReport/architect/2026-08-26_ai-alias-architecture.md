# Architecture: `pos ai alias` — AI Agent Alias Manager

**Date:** 2026-08-26
**Author:** Architect (big-pickle)
**Status:** DECISION_READY

---

## TL;DR

| Decision | Choice |
|----------|--------|
| Storage | `~/.config/linux_post_install/ai-aliases.env` (pipe-delimited structured data) |
| Shell aliases | `~/.config/linux_post_install/ai-aliases.sh` (generated, never hand-edited) |
| Tool | `bin/pos-ai-alias` — new `ai` category tool |
| No POS_CONFIG scope | Alias management is CRUD, not env-key editing; `pos config` is not involved |
| Source of truth | `.env` file; `.sh` file is regenerated on every write |
| .bashrc integration | One conditional `source` line, added by postinstall.sh |
| INSTALL_CHANGES | `postinstall.sh` adds `.bashrc` source line; `bin/pos` adds `ai-alias` to INTERACTIVE_CMDS |

**Open items:**
- None — all decisions are evidence-backed from project conventions.

---

## Decision 1: Data Format

**Problem:** Store named AI aliases (provider, session name, system prompt) durably, with safe special-character handling and trivial parsing.

### Options Considered

**Option A: Shell alias format (one-liner shell aliases)**
```
alias devbot='pos ai gemini ask --session devbot --system "You are a dev assistant"'
```
- Architecture: Store raw shell alias lines; `.bashrc` sources the file directly.
- Advantages: No generation step; shell sources it natively.
- Costs: Parsing aliases back into components (for edit/list) requires fragile quote-aware shell parsing; single quotes inside system prompts break the syntax.
- Risks: Prompt containing `'` corrupts the file. Edit must read then reconstruct — fragile.

**Option B: Pipe-delimited structured data + generated .sh**
```
devbot|gemini|devbot|You are a dev assistant
```
- Architecture: `.env` file is the source of truth (pipe-delimited fields). A separate `.sh` file is regenerated from it on every write. `.bashrc` sources the `.sh` file.
- Advantages: Parsing is trivial (`IFS='|'`); single-quote escaping is handled at generation time; data is safe to `grep`/`sort`/`awk`.
- Costs: One extra file (`.sh`); a `_regen_aliases()` helper function.
- Risks: Generation must escape correctly — but this is a single, testable function.

**Option C: Individual env files per alias**
```
~/.config/linux_post_install/ai-aliases/devbot.env
```
- Architecture: One file per alias; load all at shell startup.
- Advantages: No parsing of multi-entry files.
- Costs: Directory management; glob at shell startup; harder to list all; no atomic operations.

### Decision: Option B

Pipe-delimited structured data is the cleanest separation. The `.env` file is the source of truth. The `.sh` file is a generated artifact. This matches the project's own pattern of "generated code between GEN markers" — except here the generator lives inside the tool itself, not `make gen`.

**Rationale:** The project already has a pattern of generated files (e.g., `GEN:START`/`GEN:END` blocks, `completions/pos.bash`). The tool owns its own generation. Parsing shell aliases is fragile and error-prone; pipe-delimited data is trivially safe.

### Data Format Specification

```
# ~/.config/linux_post_install/ai-aliases.env
# Managed by: pos ai alias (do not hand-edit)
# Format: alias_name|provider|session_name|system_prompt
# Pipe characters in system_prompt are not supported.
#
# agent_name|provider|session_name|system_prompt
devbot|gemini|devbot|You are a Linux dev assistant. Reply with commands only.
code|openrouter|codereview|You are a code reviewer. Be concise.
```

**Field constraints:**

| Field | Rules |
|-------|-------|
| `alias_name` | Shell-valid identifier: `[a-zA-Z][a-zA-Z0-9_-]*` |
| `provider` | Must match an installed provider: `gemini`, `openrouter`, etc. |
| `session_name` | Defaults to the alias name if empty; `[a-zA-Z0-9_-]+` |
| `system_prompt` | Free text; no `\|` (pipe) characters; may be empty (uses built-in prompt) |

**Header:** Two comment lines at the top (file description + format) are auto-maintained by the tool.

**Empty session_name convention:** When session_name is empty (field is blank between pipes), the alias uses the alias name as the session name. This avoids redundant repetition for the common case.

---

## Decision 2: File Layout

### New files

| File | Purpose |
|------|---------|
| `bin/pos-ai-alias` | New CLI tool (100755) |

### Modified files

| File | Change |
|------|--------|
| `bin/pos` | Add `ai-alias` to `INTERACTIVE_CMDS` list |
| `postinstall.sh` | Add `.bashrc` source line for `ai-aliases.sh` (conditional, no-clobber) |

### Runtime files (user config, NOT in repo)

| File | Purpose | Mutability |
|------|---------|------------|
| `~/.config/linux_post_install/ai-aliases.env` | Alias data (source of truth) | Created/modified by tool |
| `~/.config/linux_post_install/ai-aliases.sh` | Generated shell aliases | Regenerated on every write |

### Files NOT modified

| File | Why not |
|------|---------|
| `.gitignore` | `~/.config/linux_post_install/` is a user directory, not in the repo. No new repo files to ignore. |
| `config/` | No template file needed — the env file is user-created on first use. |
| `lib/` | No new library. Tool sources `common.sh` + `menu-lib.sh` from existing libs. |

---

## Decision 3: Tool Interface

### POS Header

```bash
# POS: ai alias — Create/edit/remove named AI agent aliases
# POS_SUBCMDS: create edit remove list show
```

No `POS_FLAGS:` — this is a subcommand-based tool, not a flag-based tool.

### CLI Interface

```
pos ai alias [subcommand] [args]

Subcommands:
  (no args)         Interactive menu (create/edit/remove/list)
  create            Create a new alias (interactive prompts)
  create <name>     Create with given name (interactive prompts for rest)
  edit              Pick an alias to edit (interactive)
  edit <name>       Edit a specific alias
  remove            Pick an alias to remove (interactive, with confirmation)
  remove <name>     Remove a specific alias (with confirmation)
  list              List all aliases (non-interactive, machine-readable)
  show <name>       Show one alias's details

Options:
  -h|--help         Show this help.

Examples:
  pos ai alias                              # interactive menu
  pos ai alias list                         # show all aliases
  pos ai alias create                       # interactive create
  pos ai alias create mybot                 # create 'mybot' alias
  pos ai alias edit mybot                   # edit the 'mybot' alias
  pos ai alias remove mybot                 # remove 'mybot' (with confirm)
  pos ai alias show mybot                   # show alias details
```

### Subcommand Details

**`pos ai alias` (no args):** Interactive menu using `menu_run` from `lib/menu-lib.sh`. Options:
1. Create new alias
2. Edit existing alias
3. Remove alias
4. List aliases

**`pos ai alias list`:** Non-interactive table output:
```
Aliases (3):
  mybot       gemini      mybot      You are a helpful assistant
  code        openrouter  code       You are a code reviewer
  dev         gemini      devbot     Dev assistant
```
Format: `%-12s %-12s %-12s %s` (name, provider, session, prompt-truncated-to-60).

**`pos ai alias show <name>`:** Full details including the resolved shell command.

---

## Decision 4: POS_CONFIG

**Decision: NO POS_CONFIG scope.**

**Rationale:** The `pos config` / `POS_CONFIG` system is designed for simple `KEY=VALUE` env files (like `ai.env`, `telegram.env`, `entertainment.env`). Aliases are structured, multi-field records, not key-value pairs. The `cfg_ui()` pattern from `lib/config-ui.sh` doesn't apply here — it renders a numbered menu of KEY=VALUE pairs, not CRUD operations on named records.

The alias tool is self-contained with its own interactive menus. It does not participate in `pos config`.

---

## Decision 5: Shell Alias Generation

### The `_regen_aliases()` function

This function reads `ai-aliases.env` and writes `ai-aliases.sh`:

```bash
_regen_aliases() {
    local env_file="$1" sh_file="$2" tmp
    tmp="$(mktemp)"
    printf '#!/usr/bin/env bash\n# Auto-generated by pos ai alias — do not hand-edit.\n# Source: %s\n\n' "$env_file" >"$tmp"

    if [ -f "$env_file" ]; then
        while IFS='|' read -r name provider session prompt _rest; do
            # Skip comments and empty lines
            [[ "$name" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$name" ]] && continue

            # Validate alias name
            [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || continue

            # Session defaults to alias name if empty
            [ -z "$session" ] && session="$name"

            # Escape single quotes in the system prompt for shell-safe embedding
            local escaped_prompt="${prompt//\'/\'\\\'\'}"

            printf "alias %s='pos ai %s ask --session %s" "$name" "$provider" "$session" >>"$tmp"
            if [ -n "$prompt" ]; then
                printf " --system '%s'" "$escaped_prompt" >>"$tmp"
            fi
            printf "'\n" >>"$tmp"
        done < <(grep -v '^[[:space:]]*#' "$env_file" | grep -v '^[[:space:]]*$' || true)
    fi

    mv "$tmp" "$sh_file"
    chmod 644 "$sh_file"
}
```

**Single-quote escaping:** `${prompt//\'/\'\\\'\'}` — bash `parameter expansion` replaces every `'` with `'\''` (close-quote, escaped-quote, open-quote). This is the standard and safe pattern for embedding arbitrary strings in single-quoted shell contexts.

**Edge case — empty prompt:** When the system prompt is empty, the `--system` flag is omitted entirely, letting `pos ai` use its built-in default prompt.

### Syntax validation before commit

After generating the `.sh` file, run `bash -n` to verify syntax:
```bash
if ! bash -n "$sh_file" 2>/dev/null; then
    warn "Generated alias file has syntax errors — keeping previous version"
    rm -f "$tmp"
    return 1
fi
```

### Shell integration in .bashrc

```bash
# AI aliases (managed by pos ai alias)
[ -f ~/.config/linux_post_install/ai-aliases.sh ] && source ~/.config/linux_post_install/ai-aliases.sh
```

This line is added by `postinstall.sh` with the standard no-clobber grep check.

---

## Decision 6: Interactive Flow

### Main Menu (`pos ai alias` — no args)

Uses `menu_run` from `lib/menu-lib.sh`:

```
════════════════════════════════════════════
  AI Agent Aliases
════════════════════════════════════════════
  1) Create new alias
  2) Edit existing alias
  3) Remove alias
  4) List aliases
  0) Exit
----------------------------------------
Choose:
```

### Create Flow

1. Prompt for alias name: `menu_ask_value "Alias name" ""` — validate format (`[a-zA-Z][a-zA-Z0-9_-]*`)
2. Check for duplicate name → warn and re-prompt if taken
3. Prompt for provider: show available providers (read from `$PROVIDER_DIR/*.sh`), default `gemini`
4. Prompt for session name: default = alias name
5. Prompt for system prompt: default = empty (uses built-in)
6. Confirm: `confirm "Create alias '<name>'?" y`
7. Write to `.env`, regenerate `.sh`, log success

### Edit Flow

1. List existing aliases (name + provider + first-40-chars of prompt)
2. Pick one (if no arg given): `menu_pick "Pick alias" "${names[@]}"`
3. Show current values
4. For each field, prompt with current value as default (Enter = keep)
5. Confirm changes
6. Rewrite `.env` entry, regenerate `.sh`

### Remove Flow

1. Pick alias: `menu_pick` or named
2. Show alias details
3. `confirm "Remove alias '<name>'? This cannot be undone." n` (default = no)
4. Remove from `.env`, regenerate `.sh`

### List Flow (non-interactive)

Prints formatted table to stdout. Provider column left-aligned, name left-aligned, prompt truncated to 60 chars with `...`.

### Show Flow (non-interactive)

Full details + resolved command:
```
Alias:    mybot
Provider: gemini
Session:  mybot
Prompt:   You are a helpful assistant
Command:  pos ai gemini ask --session mybot --system 'You are a helpful assistant'
```

---

## Decision 7: Edge Cases and Error Handling

| Edge Case | Handling |
|-----------|----------|
| **Duplicate alias name on create** | `warn "Alias '$name' already exists — use 'pos ai alias edit $name' instead"`; re-prompt |
| **Empty alias name** | `err "Alias name cannot be empty"` |
| **Invalid alias name** (contains spaces, starts with digit) | `err "Invalid alias name '$name' — use letters, digits, hyphens, underscores"` |
| **Invalid provider** | `err "Unknown provider '$p' — available: $(ls ...)"` — uses same provider discovery as `pos-ai` |
| **Empty system prompt** | Allowed — omit `--system` flag; `pos ai` uses its built-in default prompt |
| **Very long system prompt** | Truncate display in `list` output (60 chars + `...`); full value preserved in `.env` and `.sh`. Warn if > 500 chars during creation. |
| **Pipe character in system prompt** | Rejected on input: `err "System prompt must not contain '\|' characters"` |
| **System prompt with single quotes** | Handled by `_regen_aliases()` escaping: `'` -> `'\''` in the generated alias line |
| **Editing an alias "in use"** | No lock/detection needed. The user edits the `.env`; on next shell startup (or `source ~/.bashrc`), aliases update. No runtime state conflict. |
| **File doesn't exist yet** | First create auto-creates both `.env` and `.sh` |
| **Corrupted/invalid .env line** | Skipped by `_regen_aliases()` (name validation regex) |
| **Concurrent edits** | Not a concern — personal single-user tool. Last write wins. |
| **Missing pos-ai dependency** | Tool doesn't require `pos-ai` at runtime — it only writes config. No dep guard needed. |

---

## Decision 8: Security Considerations

### System prompt injection

System prompts are user-authored text that becomes a shell argument. Risks:
- **Shell injection via alias execution:** The prompt is single-quoted in the alias, so shell metacharacters (`$`, backtick, `!`) are literal — safe.
- **`pos ai` prompt injection:** This is a user's own prompt for their own AI. No trust boundary crossing.
- **File permissions:** `ai-aliases.env` gets `chmod 600` (user-only read; consistent with other config files). `ai-aliases.sh` gets `chmod 644` (needed by bash `source`).

### Escaping correctness

The single-quote escaping `${prompt//\'/\'\\\'\'}` is the only place where correctness matters critically. If it fails, the generated alias has a syntax error and `source` will report it. Mitigation:
- The tool runs `bash -n` on the generated `.sh` file before committing it.
- If syntax check fails, warn and skip the regeneration (keep the old `.sh`).

### No secrets in the alias file

System prompts are not secrets — they're user-authored instructions. API keys stay in `ai.env` (already managed by `pos config ai`). No new secret surface.

---

## Decision 9: Integration with pos-ai

### How aliases invoke pos-ai

Each generated alias calls:
```bash
alias <name>='pos ai <provider> ask --session <session> --system "<prompt>"'
```

This uses the existing `pos-ai` flags:
- `--provider <name>` — supported since the beginning (line 633 of `bin/pos-ai`)
- `--session <name>` — supported (line 639)
- `--system <text>` — supported (line 642)

**No changes to `bin/pos-ai` are required.** The alias tool is a standalone configuration tool that writes shell aliases calling `pos ai`.

### Provider validation

The alias tool must validate the provider name against installed providers. It reuses the same discovery logic from `pos-ai`:
```bash
PROVIDER_DIR="$(dirname "$0")/../lib/ai-providers"
# Fallback for installed layout
[ -d "$PROVIDER_DIR" ] || PROVIDER_DIR="$(dirname "$0")/ai-providers"
```

This is the same pattern used in `pos-ai` at line 17-18. The alias tool discovers providers independently (no dependency on `pos-ai` being sourced).

---

## Decision 10: Installation Changes

### postinstall.sh modification

Add a block after the existing `ai.env` installation (around line 50):

```bash
# ── AI aliases shell integration ───────────────────────────────
ALIAS_SRC_LINE='# AI aliases (managed by pos ai alias)
[ -f ~/.config/linux_post_install/ai-aliases.sh ] && source ~/.config/linux_post_install/ai-aliases.sh'
if ! grep -qsF "ai-aliases.sh" "$BASHRC" 2>/dev/null; then
    run printf '%s\n' "$ALIAS_SRC_LINE" >> "$BASHRC"
    log "Added AI aliases source to ~/.bashrc"
fi
```

### bin/pos modification

Add `ai-alias` to the `INTERACTIVE_CMDS` list (line 262). Current value:
```
INTERACTIVE_CMDS="docker-compose docker-vbox network-hotspot system-firewall media-mp4 media-sync system-backup system-uninstall share-usb-server share-smb-server share-smb-client share-nfs-client share-nfs-server communication-telegram-listener communication-matrix-listener ai ai-gemini ai-openrouter system-schedule entertainment-config config"
```

Add `ai-alias` to this space-separated list.

### No other installation changes

- No new apt packages (no deps beyond bash)
- No new lib files (tool sources `common.sh` + `menu-lib.sh` from existing libs)
- No systemd services
- No config template in `config/`

---

## Decision 11: Long Prompt Handling

System prompts can be arbitrarily long. Shell aliases have a practical limit (ARG_MAX, typically 2MB on Linux), so this is not a hard constraint. However:

- **Display:** `list` output truncates to 60 chars + `...`
- **Storage:** Full prompt in `.env` and `.sh` — no truncation
- **Interactive edit:** Shows full current value, allows full editing
- **Warning:** During creation, if prompt exceeds 500 chars: `warn "System prompt is long (${#prompt} chars) — consider keeping it concise"`

**Decision:** No artificial length limit.

---

## Implementation Phases

### Phase 1: Core tool (single commit)

1. Create `bin/pos-ai-alias` with:
   - Shebang, strict mode, `common.sh` source, `menu-lib.sh` source
   - `# POS:` header + `# POS_SUBCMDS:`
   - `CONFIG_FILE` and `ALIASES_SH_FILE` path constants
   - `_load_aliases()` — reads `.env` into parallel arrays (names, providers, sessions, prompts)
   - `_find_alias()` — lookup by name, returns index
   - `_write_env_file()` — writes entire `.env` from arrays
   - `_regen_aliases()` — reads `.env`, writes `.sh` with proper escaping
   - `_list_aliases()` — non-interactive table output
   - `_show_alias()` — non-interactive single alias details
   - `_create_alias()` — interactive create with validation
   - `_edit_alias()` — interactive edit with field-level prompts
   - `_remove_alias()` — interactive remove with confirm
   - `_main_menu()` — interactive menu via `menu_run`
   - Subcommand dispatch (`case` pattern)
   - `usage()` function
2. Add `ai-alias` to `INTERACTIVE_CMDS` in `bin/pos`
3. Add `.bashrc` source line to `postinstall.sh`

### Phase 2: Verification

1. `chmod +x bin/pos-ai-alias`
2. `bash -n bin/pos-ai-alias`
3. `make gen` — regenerate tables (new tool appears in dispatch table, bin tree, file table)
4. `make check` — self-consistency gate
5. `make lint` — convention gate (0 FAIL, 0 WARN)
6. Manual test: create, list, show, edit, remove aliases; verify `.sh` file is correct
7. Source `.bashrc` and verify aliases work

### Phase 3: Documentation

1. `DOC/POS.md` — add `ai alias` section (hand-written)
2. `DOC/HOWTO.md` — add index row
3. `DOC/howto/ai.md` — add aliases section (if ai.md exists; otherwise add to existing ai howto)
4. `DOC/AGENT_Context_Project.md` — regenerated by `make gen`; hand-add to Common Tasks table
5. Update `AGENT_TODO.md` Done section (dated)

---

## Architectural Constraints

1. **Tool must source `lib/common.sh`** via the fallback chain (not self-contained)
2. **Tool must source `lib/menu-lib.sh`** for interactive menus
3. **Tool MUST be in `INTERACTIVE_CMDS`** in `bin/pos`
4. **Generated `.sh` file must pass `bash -n`** before commit
5. **Env-seam:** all file paths use `${CONFIG_DIR:-...}` pattern (already in `common.sh`)
6. **`chmod 600`** for `.env`, `chmod 644` for `.sh`
7. **No dependency on `pos-ai`** being installed — tool writes config, doesn't run `pos ai`
8. **Pipe delimiter** — system prompts must not contain `|`; validated on input

---

## Verification Checklist

- [ ] `bash -n bin/pos-ai-alias` passes
- [ ] `shellcheck bin/pos-ai-alias` passes (or only known false positives)
- [ ] `make gen` regenerates tables correctly
- [ ] `make check` passes (bash -n, exec bits, doc sync, smoke)
- [ ] `make lint` passes (0 FAIL, 0 WARN)
- [ ] `pos ai alias --help` shows help
- [ ] `pos ai alias` shows interactive menu
- [ ] Create -> list -> show -> edit -> remove cycle works
- [ ] Generated `.sh` file has correct alias syntax
- [ ] `bash -n` on generated `.sh` passes
- [ ] `.bashrc` source line works (aliases available after source)
- [ ] Special chars in system prompt (single quotes, spaces, $) survive round-trip
- [ ] Duplicate name is rejected
- [ ] Invalid alias name is rejected
- [ ] Invalid provider is rejected

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Single-quote escaping fails for exotic prompts | Low | High (syntax error in .sh) | `bash -n` check before commit; warn + skip on failure |
| User has many aliases -> list becomes long | Low | Low | `menu_pick` already supports filtering |
| `.bashrc` source line conflicts with existing alias definitions | Very Low | Medium | Grep-check before adding; line is a conditional source, not an alias definition |
| `make lint` rejects the new tool for a convention violation | Low | Low (blocking) | Follow template exactly; deps guards before help; proper header |

---

**End of architecture document.**
