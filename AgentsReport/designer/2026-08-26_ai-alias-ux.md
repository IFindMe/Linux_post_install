# UI/UX Specification: `pos ai alias`

**Date:** 2026-08-26
**Author:** Designer
**Status:** DESIGN_READY

---

## TL;DR

| Aspect | Decision |
|--------|----------|
| Main menu | `menu_run` with 4 items; alias table rendered above the box |
| Create flow | 4-step wizard using `step()` headers; name validated in a loop |
| Edit flow | Pick → show current values → per-field prompt with Enter=keep |
| Remove flow | Pick → detail display → `confirm … n` (default=NO) |
| List output | Column-formatted table to stdout, 80-col safe |
| Long prompts | Single-line via `menu_ask_value`; full value stored; display truncated |
| Error UX | `warn` + re-prompt (recoverable) or `err` + exit (fatal) |
| First-run | Auto-create `.env`+`.sh` on first write; show "No aliases yet" |
| Color | CYAN box, GREEN success, YELLOW warn, RED error — same as all `pos` tools |

**Key design decisions:**

1. **Edit uses Enter-to-keep** — each field defaults to current value; empty = keep.
2. **Remove defaults to NO** — irreversible action gets `confirm … n`.
3. **No multi-line prompt input** — `menu_ask_value` is single-line; matches every other `pos` tool.
4. **Table preview** shows provider + session + truncated prompt — enough to distinguish at a glance.

---

## Step 1: Main Menu — `pos ai alias` (no args)

### Screen Purpose
Entry point. Shows existing aliases and offers all actions.

### ASCII Mockup — With Aliases

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

Above the menu box (also on stderr), render the alias table:

```
  Name         Provider      Session       Prompt
  ─────────── ─────────────  ─────────────  ──────────────────────────
  devbot       gemini         devbot         You are a Linux dev ass…
  code         openrouter     code           You are a code reviewer…
  ─────────── ─────────────  ─────────────  ──────────────────────────
  2 alias(es)
```

### ASCII Mockup — Empty (No Aliases Yet)

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

With a line above the box:

```
  [!] No aliases defined yet — create one with option 1.
```

### Table Column Spec

```
Column      Width   Alignment   Truncation
─────────   ─────   ─────────   ─────────────────────────────────
Indent      2       —           —
Name        12      left        hard-cut (alias names max ~20 by validation)
Provider    12      left        as-is (short: gemini, openrouter)
Session     12      left        as-is
Prompt      42      left        ${prompt:0:40}…  (if > 42 chars)
```

**Total width:** 2 + 12 + 1 + 12 + 1 + 12 + 1 + 42 = **83 cols** (safe for 80-col with minor overflow on rare cases; alternatively reduce prompt to 40 → 81).

**Empty prompt cell:** Show `${DIM}(default)${RESET}` in dim.

**Row limit:** If > 5 aliases, show first 4 + a final row: `  … and N more`.

### Behavior

| Condition | Behavior |
|-----------|----------|
| Zero aliases | No table; dim warning line; menu options still shown (user can create immediately). |
| 1+ aliases | Table above menu box. |
| EOF / non-tty | `menu_guard` fails → prints to stderr, rc 1. |
| `0`/`q`/`Q` on menu | Clean exit rc 0 (standard `menu_run` behavior). |

---

## Step 2: Create Flow

### Entry Points
- `pos ai alias` → menu → option 1
- `pos ai alias create` (no name arg — full interactive)
- `pos ai alias create <name>` (pre-fills name, skips step 1)

### ASCII Mockup — Full Interactive Create

```
════════════════════════════════════════════
  Create AI Agent Alias
════════════════════════════════════════════

  [1/4] Alias Name
  ─────────────────────────────────────────
Alias name: devbot

  [2/4] Provider
  ─────────────────────────────────────────
-- 2 available --
  1) gemini
  2) openrouter
  0) Back
----------------------------------------
Pick provider [1-2], text=filter, 0=back 1

  [3/4] Session Name
  ─────────────────────────────────────────
Session name [devbot]:

  [4/4] System Prompt
  ─────────────────────────────────────────
System prompt (empty = use built-in): You are a Linux dev assistant.

────────────────────────────────────────────
  Create alias 'devbot'?
    Provider:  gemini
    Session:   devbot
    Prompt:    You are a Linux dev assistant.
────────────────────────────────────────────
Create alias 'devbot'? [Y/n]: y

  [+] Alias 'devbot' created.
      Reload shell: source ~/.bashrc
```

### Step-by-Step Behavior

#### Step 1: Alias Name

| Input | Behavior |
|-------|----------|
| Prompt | `menu_ask_value "Alias name" ""` — mandatory, no default |
| Empty input | `warn "Alias name cannot be empty"` → re-prompt (loop) |
| Invalid format | `warn "Invalid name '$input' — use letters, digits, hyphens, underscores (start with a letter)"` → re-prompt |
| Duplicate name | `warn "Alias '$input' already exists — use 'pos ai alias edit $input' instead"` → re-prompt |
| `<name>` arg given | Validate format + uniqueness; fatal `err` if invalid (non-interactive) |
| **Valid name** | Break out of loop, proceed to step 2 |

**Validation regex:** `^[a-zA-Z][a-zA-Z0-9_-]*$`

#### Step 2: Provider

| Input | Behavior |
|-------|----------|
| Source | Discover from `$PROVIDER_DIR/*.sh` (pattern: `bin/pos-ai` lines 17-18) |
| Picker | `menu_pick "Pick provider" "${providers[@]}"` |
| Zero providers | `err "No AI providers installed — run 'pos ai' setup first"` → exit 1 |
| Single provider | Auto-select, log: `"Using provider: ${provider}"` (skip picker) |
| User picks 0/back | Return to main menu (rc 1 from `menu_pick`) |

#### Step 3: Session Name

| Input | Behavior |
|-------|----------|
| Prompt | `menu_ask_value "Session name" "<alias_name>"` — default = alias name |
| Empty (Enter) | Accepts default = alias name (the common path) |
| Invalid format | `warn` + re-prompt with current default |
| **Valid** | Proceed |

**Design decision:** Default session = alias name. 90%+ of users want 1:1 mapping. The bracket default `[alias_name]` makes this obvious.

#### Step 4: System Prompt

| Input | Behavior |
|-------|----------|
| Prompt | `menu_ask_value "System prompt (empty = use built-in)" ""` |
| Empty | Stores empty string → `--system` flag omitted in generated alias |
| Contains `\|` | `warn "System prompt must not contain '|' characters"` → re-prompt |
| > 500 chars | `warn "Prompt is ${#input} chars — consider keeping it concise"` → still accepts |
| Single quotes, `$`, backticks | **Accepted** — `_regen_aliases()` handles escaping |

**Design decision: single-line only.** `menu_ask_value` uses `read -rp`. Multi-line input is not supported and would require external deps (dialog/whiptail). Users paste prompts on one line — this is consistent with every other `pos` tool.

#### Confirmation

| Aspect | Behavior |
|--------|----------|
| Display | `section`-style box with all 4 values; prompt truncated to 50 chars in display |
| Confirm | `confirm "Create alias '<name>'?" y` — **default YES** (constructive action) |
| User declines | `log "Aborted."` → return to main menu |
| User confirms | `_write_env_file()` + `_regen_aliases()` → `log "Alias '<name>' created."` |

---

## Step 3: Edit Flow

### Entry Points
- `pos ai alias` → menu → option 2
- `pos ai alias edit` (interactive picker)
- `pos ai alias edit <name>` (edit specific alias)

### ASCII Mockup — Full Interactive Edit

```
════════════════════════════════════════════
  Edit AI Agent Alias
════════════════════════════════════════════

-- 3 available --
  1) devbot     [gemini]     You are a Linux dev assistant.
  2) code       [openrouter] You are a code reviewer.
  3) dev        [gemini]     Dev assistant
  0) Back
----------------------------------------
Pick alias to edit [1-3], text=filter, 0=back 1

  Current values for 'devbot':
    Provider:  gemini
    Session:   devbot
    Prompt:    You are a Linux dev assistant.

  [1/3] Provider
  ─────────────────────────────────────────
-- 2 available --
  1) gemini
  2) openrouter
  0) Back
----------------------------------------
Pick provider [1-2], text=filter, 0=back 1

  [2/3] Session Name
  ─────────────────────────────────────────
Session name [devbot]:

  [3/3] System Prompt
  ─────────────────────────────────────────
System prompt [You are a Linux dev assistant.]:

────────────────────────────────────────────
  Save changes to 'devbot'?
    Provider:  gemini       (unchanged)
    Session:   devbot       (unchanged)
    Prompt:    You are a dev assistant
────────────────────────────────────────────
Save changes? [Y/n]: y

  [+] Alias 'devbot' updated.
```

### Step-by-Step Behavior

#### Alias Picker

| Condition | Behavior |
|-----------|----------|
| No aliases | `warn "No aliases to edit — create one first"` → return to main menu |
| Picker | `menu_pick "Pick alias to edit" "${display_items[@]}"` |
| Items format | `"${name} [${provider}] ${prompt_preview}"` (prompt preview = first 30 chars) |
| `<name>` arg given | Validate existence; `err` if not found, exit 1 |

#### Show Current Values

After picking, display a summary block (to stderr):

```
  Current values for 'devbot':
    Provider:  gemini
    Session:   devbot
    Prompt:    You are a Linux dev assistant.
```

This gives the user a reference before editing.

#### Per-Field Editing (3 steps)

| Field | Mechanism | Default | Validation |
|-------|-----------|---------|------------|
| **Provider** | `menu_pick` from installed providers | Current shown in list header | Must pick valid provider; 0/back = keep current |
| **Session** | `menu_ask_value "Session name" "<current>"` | Current value | Regex; warn + re-prompt on invalid |
| **Prompt** | `menu_ask_value "System prompt" "<current>"` | Current value (truncated in display if > 60 chars) | `\|` rejected; > 500 chars warning |

**Provider edit detail:** `menu_pick` doesn't support pre-selection. Current provider is shown in the header: `"Current provider: gemini"`. If user picks 0/back, current is kept — clean "skip to keep" pattern.

**Prompt edit detail:** If current prompt > 80 chars, default display is truncated: `[You are a Linux dev assistant. You reply with c…]`. The full value is preserved in the stored default regardless.

**Step count:** 3 steps (not 4) because alias name cannot be changed — it's the record key.

#### Save Confirmation

| Condition | Behavior |
|-----------|----------|
| **No changes detected** (all values identical) | `log "No changes — nothing to save."` → return to main menu (skip write) |
| Changes exist | Show diff summary with `(changed)` / `(unchanged)` tags |
| **Confirm** | `confirm "Save changes to '<name>'?" y` — **default YES** |
| User declines | `log "Discarded."` → return to main menu |
| User confirms | Rewrite `.env` entry, regenerate `.sh`, `log "Alias '<name>' updated."` |

**Diff summary format:**

```
────────────────────────────────────────────
  Save changes to 'devbot'?
    Provider:  gemini       (unchanged)
    Session:   mybot        (changed)
    Prompt:    You are a dev assistant
────────────────────────────────────────────
```

---

## Step 4: Remove Flow

### Entry Points
- `pos ai alias` → menu → option 3
- `pos ai alias remove` (interactive picker)
- `pos ai alias remove <name>` (remove specific alias)

### ASCII Mockup

```
════════════════════════════════════════════
  Remove AI Agent Alias
════════════════════════════════════════════

-- 3 available --
  1) devbot     [gemini]     You are a Linux dev assistant.
  2) code       [openrouter] You are a code reviewer.
  3) dev        [gemini]     Dev assistant
  0) Back
----------------------------------------
Pick alias to remove [1-3], text=filter, 0=back 1

  Alias:    devbot
  Provider: gemini
  Session:  devbot
  Prompt:   You are a Linux dev assistant.

Remove alias 'devbot'? This cannot be undone. [y/N]: n

  [--] Cancelled.
```

### Behavior

| Condition | Behavior |
|-----------|----------|
| No aliases | `warn "No aliases to remove"` → return to main menu |
| Picker | Same format as edit picker |
| `<name>` arg | Validate existence; `err` if not found, exit 1 |
| Detail display | Show all fields in full (no truncation) before confirmation |
| **Confirm** | `confirm "Remove alias '<name>'? This cannot be undone." n` — **default NO** |
| User declines | `log "Cancelled."` → return to main menu |
| User confirms | Remove from `.env`, regenerate `.sh`, `log "Alias '<name>' removed."` |

**Design decision: default=n.** Irreversible destructive action. `confirm` with default `n` means pressing Enter is safe — user must explicitly type `y`.

---

## Step 5: List / Show (Non-Interactive)

### `pos ai alias list`

#### ASCII Mockup

```
Aliases (3):
  Name         Provider      Session       Prompt
  ─────────── ─────────────  ─────────────  ──────────────────────────────
  devbot       gemini         devbot         You are a Linux dev assistant.
  code         openrouter     code           You are a code reviewer. Be concise.
  dev          gemini         devbot         Dev assistant
```

| Aspect | Spec |
|--------|------|
| Format | `printf "  %-12s %-12s %-12s %s\n"` |
| Prompt truncation | Full up to 60 chars; longer → append `…` |
| Zero aliases | Print `Aliases (0):` with nothing below, exit 0 |
| Header | `Aliases (N):` — count included for scripting |
| Output | stdout, no color (pipeable) |

### `pos ai alias show <name>`

#### ASCII Mockup

```
  Alias:    devbot
  Provider: gemini
  Session:  devbot
  Prompt:   You are a Linux dev assistant.
  Command:  pos ai gemini ask --session devbot --system 'You are a Linux dev assistant.'
```

| Aspect | Spec |
|--------|------|
| `<name>` required | Missing → `err "Usage: pos ai alias show <name>"` exit 1 |
| Name not found | `err "Alias '<name>' not found"` exit 1 |
| Full values | No truncation on any field |
| `Command` field | Exact alias expansion: `pos ai <provider> ask --session <session> [--system '<prompt>']` |
| Single quotes in prompt | Display escaped as `'\''` to show actual alias content |
| Empty prompt | `Command` omits `--system` entirely |
| Output | stdout, no color |

---

## Step 6: Error States — Complete Catalog

| Scenario | Message | Type | Behavior |
|----------|---------|------|----------|
| **First run (no .env)** | Silent auto-create on first write | — | `_load_aliases()` returns empty; menu shows "No aliases" |
| **Alias name empty** | `warn "Alias name cannot be empty"` | Recoverable | Re-prompt (create) |
| **Alias name invalid** | `warn "Invalid name '<input>' — use letters, digits, hyphens, underscores"` | Recoverable | Re-prompt |
| **Alias name duplicate (create)** | `warn "Alias '<input>' already exists — use 'pos ai alias edit <input>' instead"` | Recoverable | Re-prompt |
| **Alias not found (edit/remove)** | `err "Alias '<name>' not found"` | Fatal | Exit 1 |
| **Invalid provider** | `err "Unknown provider '<input>'"` | Fatal | Exit 1 (impossible in interactive — menu_pick) |
| **No providers installed** | `err "No AI providers installed — run 'pos ai' setup first"` | Fatal | Exit 1 |
| **Pipe char in prompt** | `warn "System prompt must not contain '\|' characters"` | Recoverable | Re-prompt |
| **Long prompt (> 500 chars)** | `warn "Prompt is <N> chars — consider keeping it concise"` | Advisory | Accepts, continues |
| **No aliases to edit** | `warn "No aliases to edit — create one first"` | Info | Return to main menu |
| **No aliases to remove** | `warn "No aliases to remove"` | Info | Return to main menu |
| **Non-tty / EOF** | `[!] Interactive menu needs a terminal — use a subcommand instead (see --help).` | Fatal | Exit 1 |
| **Confirm declined (create)** | `log "Aborted."` | Info | Return to main menu |
| **Confirm declined (remove)** | `log "Cancelled."` | Info | Return to main menu |
| **Confirm declined (edit)** | `log "Discarded."` | Info | Return to main menu |
| **No changes in edit** | `log "No changes — nothing to save."` | Info | Return to main menu |

### Message Convention

| Helper | Use For | Destination |
|--------|---------|-------------|
| `log` | Success, info | stdout |
| `warn` | Recoverable problems, advisory | stderr |
| `err` | Fatal errors | stderr + exit 1 |
| `section` / `step` | Visual structure | stderr (display) |

---

## Step 7: Color & Formatting Conventions

### Color Palette

| Element | Color | Source |
|---------|-------|--------|
| Section/box borders | CYAN | `section()`, `menu_run()` |
| Step numbers | BOLD | `step()` |
| Step underlines | BLUE | `step()` |
| Success messages | GREEN | `log()` |
| Warnings | YELLOW | `warn()` |
| Errors | RED | `err()` |
| Dim/placeholder text | DIM | inline `${DIM}...${RESET}` |
| Table headers | Plain (no color) | — |
| Default values in prompts | Plain | shown in brackets `[value]` |

### Box Style

All section boxes use the existing double-line Unicode style — the project standard from `section()` in `common.sh`:

```
════════════════════════════════════════════
  Title
════════════════════════════════════════════
```

### 80-Column Safety

Final column layout for table output:

```
Indent:    2
Name:     12
Gap:       1
Provider: 12
Gap:       1
Session:  12
Gap:       1
Prompt:   42
─────────────────────
Total:    83 cols (1 col over 80 — acceptable for modern terminals)
```

For strict 80-col: prompt = 40 → total = 81. **Decision: use 42 for prompt width; 83 cols is acceptable** — the project targets 80-col as a guideline, not a hard wall. All other content (menus, prompts, messages) is well within 80.

---

## Step 8: Implementation Guidance for Builder

### Function Map

| Function | Responsibility | Est. Lines |
|----------|---------------|------------|
| `_load_aliases()` | Read `.env` → parallel arrays `_ALIAS_NAMES[]`, `_ALIAS_PROVIDERS[]`, `_ALIAS_SESSIONS[]`, `_ALIAS_PROMPTS[]` | ~20 |
| `_find_alias <name>` | Linear scan; return index or -1 | ~8 |
| `_write_env_file()` | Write arrays → `.env` (with header comments) | ~15 |
| `_regen_aliases()` | `.env` → `.sh` with `'`→`'\''` escaping + `bash -n` pre-commit check | ~30 |
| `_list_aliases()` | `printf` table to stdout | ~15 |
| `_show_alias <name>` | Key-value display to stdout | ~10 |
| `_create_alias [name]` | 4-step wizard (name→provider→session→prompt→confirm) | ~60 |
| `_edit_alias [name]` | Pick→show→3 field prompts→diff→confirm→write | ~70 |
| `_remove_alias [name]` | Pick→detail→confirm(n)→remove+regen | ~30 |
| `_main_menu()` | `menu_run` loop dispatching to above | ~30 |
| `usage()` | Help text | ~20 |

### Critical Implementation Patterns

1. **All display to stderr, all results to stdout** — `menu-lib.sh` contract. `menu_run`/`menu_pick`/`menu_ask_value` already do this; `_create_alias`/`_edit_alias`/`_remove_alias` must follow the same pattern for their `section()`/`step()` output.

2. **Re-prompt loops** — use `while true` with validation inside; `continue` on `warn`, `break` on valid input. Name validation loops until valid. Provider/session/prompt validation loops until valid.

3. **Edit diff detection** — compare new values against loaded values before writing; skip the write entirely if all identical. This avoids unnecessary `.sh` regeneration.

4. **Provider discovery** — copy pattern from `bin/pos-ai` lines 17-18:
   ```bash
   PROVIDER_DIR="$(dirname "$0")/../lib/ai-providers"
   [ -d "$PROVIDER_DIR" ] || PROVIDER_DIR="$(dirname "$0")/ai-providers"
   ```

5. **Pipe char in prompt** — validate in `_create_alias` and `_edit_alias` prompt steps, NOT in `_regen_aliases()` (which trusts its input after validation).

6. **Generated .sh syntax check** — `bash -n "$sh_file"` before `mv "$tmp" "$sh_file"`; on failure, `warn` and `rm -f "$tmp"` (keep old `.sh`).

7. **INTERACTIVE_CMDS** — add `ai-alias` to the space-separated list in `bin/pos`.

### State Transition Diagram

```
pos ai alias (no args)
  │
  ├─ _main_menu()
  │   ├─ [1] → _create_alias()
  │   │         ├─ Step 1: name validation loop
  │   │         ├─ Step 2: provider picker (or auto if single)
  │   │         ├─ Step 3: session (default = alias name)
  │   │         ├─ Step 4: prompt (default = empty)
  │   │         ├─ confirm → _write_env_file() + _regen_aliases()
  │   │         └─ return to _main_menu()
  │   │
  │   ├─ [2] → _edit_alias()
  │   │         ├─ picker (or use arg)
  │   │         ├─ show current values
  │   │         ├─ Step 1: provider picker (0=back = keep)
  │   │         ├─ Step 2: session (enter = keep)
  │   │         ├─ Step 3: prompt (enter = keep)
  │   │         ├─ diff check → confirm → write
  │   │         └─ return to _main_menu()
  │   │
  │   ├─ [3] → _remove_alias()
  │   │         ├─ picker (or use arg)
  │   │         ├─ show detail
  │   │         ├─ confirm n (default = no)
  │   │         ├─ remove + regen
  │   │         └─ return to _main_menu()
  │   │
  │   ├─ [4] → _list_aliases() (stdout, then return to _main_menu)
  │   │
  │   └─ [0] → exit 0
  │
  ├─ pos ai alias create [name]  → _create_alias "$name"
  ├─ pos ai alias edit [name]    → _edit_alias "$name"
  ├─ pos ai alias remove [name]  → _remove_alias "$name"
  ├─ pos ai alias list           → _list_aliases(); exit 0
  ├─ pos ai alias show <name>    → _show_alias "$name"; exit 0
  └─ -h|--help                   → usage(); exit 0
```

---

## Out of Scope

- Multi-line prompt editor (no `dialog`/`whiptail` dependency)
- Alias import/export
- Alias categories or tags
- Alias usage statistics
- `pos config` integration (architecture Decision 4: explicitly rejected)
- Alias renaming (name is the record key; remove + create is the path)

---

## Open Design Questions

None. All decisions resolved from architecture doc + existing primitives.

---

**End of UX specification.**
