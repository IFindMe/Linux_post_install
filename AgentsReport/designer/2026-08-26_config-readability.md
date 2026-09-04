# Designer Report — `pos config <scope>` listing readability

Date: 2026-08-26 · Agent: Designer · Status: DESIGN_READY (spec complete, ready for Builder)

## TL;DR

- Status: **DESIGN_READY** — smallest change-set that fixes "the config not clear readable" while staying 100% generic.
- Root cause of complaint: the `ai` scope renders provider-specific keys from BOTH adapters flat and equal-weight (`*providers` expansion, lib/config-ui.sh:192-199), so 4 of 6 rows are noise for the active provider and nothing links `AI_PROVIDER`'s value to the relevant rows.
- Fix = 3 coordinated pieces, all inside `lib/config-ui.sh` (+ one header line in `bin/pos-ai`):
  1. **Group captions** via a new optional field type `@[<KEY>=<alts>] <caption>` in `# POS_CONFIG:` headers — backward compatible, zero per-tool branches.
  2. **Tagged wildcard** `*providers=<tag>` so per-provider groups are possible from pure metadata.
  3. **Typography tier** applied to ALL scopes uniformly: reuse existing `BOLD/DIM/CYAN/RESET` from common.sh (guarded fallbacks, menu-lib precedent), dim `(not set)`, hanging-indent wrapping at 80–120 cols, display routed to stderr, honest prompt text (`r=refresh` was invisible).
- Inactive groups stay visible-but-dimmed with a textual reason — never hidden — so numbering is stable across edits.
- No changes to masking, env-file formats, edit flow, gen-docs or completions output. Gates expected green after routine `make gen && make check && make lint`.

---

## Step 1: Evidence base

Read and cited throughout:

- `lib/config-ui.sh` (385 lines) — full render path: `cfg_scope_keys` (:176-204), `_cfg_key_line` (:92-112), `_cfg_plugin_keys` (:116-137), `_cfg_provider_keys` (:141-173), `cfg_value` (:207-214), `cfg_display` (:243-257), `_cfg_edit_one` (:301-332), `cfg_ui` (:335-385).
- Color helpers already defined by `lib/common.sh:3-10`: `CYAN GREEN YELLOW RED BLUE BOLD DIM RESET` (tput). **config-ui.sh uses none of them.**
- Guarded-color + stderr-display precedent: `lib/menu-lib.sh:29-31` (`CYAN="${CYAN:-}"` fallbacks) and :60-70 (render block `{ … } >&2`, "display goes to stderr, results to stdout" contract :19-20).
- `bin/pos-ai:6` — ai scope declaration: `AI_PROVIDER | *providers | AI_SYSTEM_PROMPT`.
- Provider adapters feed the expansion: `lib/ai-providers/gemini.sh:7-8`, `lib/ai-providers/openrouter.sh:7-8` (`# PROVIDER_CONFIG:` → AI_GEMINI_API_KEY/MODEL, OPENROUTER_API_KEY/MODEL). Expansion order follows glob order (`gemini.sh` before `openrouter.sh`), matching the user's live listing.
- Contrast scopes: `bin/pos-system-health:4` (scope `system`, 2 keys), `bin/pos-system-backup:6` (scope `notify`, 1 key, long description).
- Downstream consumers checked for blast radius:
  - `scripts/gen-docs.sh:153-164` — reads ONLY the scope field of `# POS_CONFIG:` (completion cache).
  - `completions/pos.bash:193-208` — same, scopes only.
  - `lib/registry.sh:107` — stores raw header lines verbatim (passthrough; no key-field parsing).
- Prompt string `Variable number [q to quit]` occurs exactly once repo-wide (config-ui.sh:371); no doc quotes it verbatim.
- No unit tests exist for config-ui.sh.

Other active `# POS_CONFIG:` headers scanned for syntax collisions: none contain `@`; wildcards in the wild are only `*plugins` / bare `*providers`. The proposed `@…` caption prefix and `=<tag>` wildcard argument collide with nothing.

[DONE]

## Step 2: Diagnosis — why the listing is unclear

Ordered by contribution to the complaint:

1. **Flat mixing of active/inactive provider keys (core defect).** `cfg_scope_keys` expands `*providers` inline (config-ui.sh:192-199); `_cfg_provider_keys` greps all adapters at once (:171). Result: `AI_GEMINI_*` and `OPENROUTER_*` rows interleave with equal visual weight regardless of `AI_PROVIDER`'s value. With openrouter active, rows 2-3 are dead weight; switch providers and different rows become dead weight. Nothing on screen expresses that relationship.
2. **No visual link between the selector value and any group.** Even a careful reader must mentally join `AI_PROVIDER=openrouter` (row 1's value column) to which other rows matter. That join lives only in the reader's head.
3. **Zero typographic hierarchy.** Keys, values, placeholders, descriptions all render at identical weight (plain printf, :362-368) even though `BOLD/DIM/CYAN` exist one file away in common.sh:3-10 and sibling libs use them (menu-lib). Scanning requires reading every line; nothing pops.
4. **`(not set)` looks like data.** cfg_display (:246) emits it with the same weight as a real value, so "which things are actually configured?" — arguably the #1 question a config screen answers — is unanswerable at a glance.
5. **Description vs example not differentiated.** Both print at the same 6-space indent and weight (:364, :367), yet they are different kinds of information (prose vs literal format hint).
6. **No rhythm / grouping whitespace.** Every entry is equally dense; there is no blank-line separation between logical sections, and the fixed 36-char dash rule (:356) is unrelated to content width or house style (menu-lib uses a CYAN rule).
7. **Prompt under-documents the actual affordances.** The loop supports `r/R` refresh and Enter-redraw (:374-375) but the prompt says only `[q to quit]`. "Variable number" is also stilted phrasing for "which row do you want to edit".
8. **Long descriptions wrap ragged.** `printf '      %s\n'` does no wrapping; at 80 cols the notify scope's 92-char description wraps into the next row's visual space with no hanging indent (verified against bin/pos-system-backup:6 text).
9. **Stream discipline inconsistency.** Menu body goes to stdout (:354-370) while `read -p` prompts go to stderr — under the dispatcher's logging tee the interactive UI can leak into logs. menu-lib's established contract (display→stderr) is violated.

Not defects: value column alignment via fixed `%-28s` pad is adequate for all declared keys today (longest = 25 chars); masking format is fine and out of scope anyway.

[DONE]

## Step 3: Specification

### 3.1 Header grammar extension (the only metadata change)

Current grammar (config-ui.sh:8) gains ONE new field type and ONE optional wildcard argument; everything existing keeps working byte-for-byte:

```text
# POS_CONFIG: <scope> | <env-file> | <field> | ...
  <field> := <KEY>=<flags>:<desc>[::<example>]      unchanged
           | @<caption>                             NEW — unconditional group caption
           | @[<KEY>=<alt>[|<alt>…]] <caption>      NEW — conditional group caption
           | *plugins                               unchanged
           | *providers[=<tag>]                     EXT — optional filter to adapter <tag>.sh
```

Semantics:

- A field starting with `@` is a **caption**, never a key. Optional condition bracket must be the first token: `@[KEY=alt1|alt2] Caption text`.
- **Condition evaluation:** caption is *active* iff current value of KEY (via existing `cfg_value`) equals any non-empty alt, or an empty alt segment is present (`trailing/double pipe`) and the value is unset/empty. One condition per caption — deliberately no boolean logic.
- Empty-alt support matters: `@[AI_PROVIDER=gemini|]` means "gemini explicitly, or unset (= default gemini)". Without it, a fresh install showing `AI_PROVIDER=(not set)` would wrongly dim the gemini group.
- **Inactive captions/rows are dimmed, never hidden** — see 3.3.
- `*providers=<tag>` contributes keys only from `lib/ai-providers/<tag>.sh`. Bare `*providers` behaves exactly as today (all adapters).
- Captions parse as whole fields: `::`, pipes-in-desc, examples etc. are untouched; `cfg_scopes`/`cfg_scope_envfile` only ever read fields 1-2, so old parsers (gen-docs, completions, registry passthrough) cannot notice the extension.

Exact new `bin/pos-ai:6` header:

```bash
# POS_CONFIG: ai | ai.env | AI_PROVIDER=:Provider (gemini or openrouter, default gemini) | @[AI_PROVIDER=gemini|] Gemini | *providers=gemini | @[AI_PROVIDER=openrouter] OpenRouter | *providers=openrouter | @General | AI_SYSTEM_PROMPT=:Custom system prompt (overrides built-in, empty to reset)
```

This is pure declarative metadata — no `if scope == ai` anywhere. Any future scope (e.g. notify platforms) can adopt captions; every scope that doesn't, renders as before plus the uniform typography tier.

### 3.2 Internal representation (Builder guidance, non-normative)

- Caption records enter the `keys[]` stream as `>|<cond>|<caption>|` (key position = `>`; keys are uppercase env names, so `>` is unambiguous). `cfg_ui` branches on `${k}` = `>`.
- Numbering: assign numbers only to non-caption records; keep a number→index map (~5 lines). Numbers therefore derive from static header order → **stable across renders and across provider switches**.
- Lazy caption flush: a pending caption prints only when a key actually follows it — a tag whose adapter is missing suppresses its caption instead of leaving an orphan heading. Additionally, an explicit `*providers=<tag>` matching zero files emits one `warn` (silent emptiness would hide authoring errors; bare `*providers` staying silent preserves today's behavior on installs without adapters).

### 3.3 Rendering rules (applied uniformly to ALL scopes)

Reuse tokens `BOLD DIM CYAN RESET` from common.sh with guarded fallbacks at the top of config-ui.sh, mirroring menu-lib.sh:29-31 (`DIM="${DIM:-}"` etc.) so standalone sourcing degrades to plain text, never an error.

| Element | Treatment |
|---|---|
| Title `pos config — <scope> (<envfile>)` | BOLD |
| Rule under title | CYAN, 40 × `─` (unicode precedent: menu-lib box) |
| Row number `%2d)` | DIM |
| Key name | BOLD |
| Value | default weight |
| `(not set)` | DIM |
| Masked secret `AIzaSy...fDp8 (39 chars)` | default weight (unchanged semantics) |
| Description line | default weight, 6-space hanging indent |
| Example line `e.g. …` | DIM, 6-space hanging indent |
| Caption | DIM, rendered `  ── <caption>` (2-space indent, dashes sit under the number column), preceded by one blank line |
| Caption when condition false | append DIM `— inactive while <KEY>=<value>` (or `— inactive (<KEY> not set)`); ALL rows until the next caption render DIM as well |
| Prompt | `Number to edit [r=refresh, q=quit]: ` |

Wrapping: descriptions, examples and caption lines word-wrap at `W = clamp(${COLUMNS:-80}, 60, 120)` minus the 6-column hang; break at spaces only, no hyphenation, over-long tokens pass through unbroken.

Stream routing: the whole render block goes to stderr (`{ … } >&2`, menu-lib.sh:60-70 pattern). Prompts already go to stderr via `read -p`. Rationale: dispatcher logging-tee hygiene; results/data on stdout unaffected (this UI returns nothing on stdout).

Why dim-not-hide inactive groups: hiding would renumber rows the moment `AI_PROVIDER` is edited mid-session (unpredictable, WCAG-cognitive predictability failure) and would hide the fact that those settings *exist*. Dimming + a literal textual reason carries the meaning without relying on color alone (WCAG 1.4.1).

### 3.4 Interaction specification

- Trigger: every loop iteration re-renders (entry, after each edit, after `r`, after Enter) — unchanged flow (cfg_ui:353 `while true`). Because conditions are evaluated per render from the env file, editing `AI_PROVIDER` to `gemini` flips group emphasis on the very next redraw automatically. No new keystrokes, no new states.
- Edge cases: EOF on prompt → existing clean-exit path (:371) kept; invalid number → existing warn kept; rapid repetition N/A (no async behavior); cancellation = `q` unchanged.
- Accessibility (terminal):
  - DIM reserved for secondary info (numbers, examples, placeholders, inactive labels); meaning never carried by dimness/color alone — inactive state always includes the words "inactive while …".
  - Monochrome/no-TTY (tee, pipe): tput vars fall back to empty → plain-text hierarchy survives via indentation, blank lines, numbering and wording.
  - Keyboard-only flow unchanged (digits, r, q); target-size/motor N/A; screen readers traverse linearly — caption lines act as spoken group headings.
  - WCAG 2.1 AA intent: contrast of body/default text is terminal-native; DIM applies only to redundant-or-secondary strings.

[DONE]

## Step 4: Rendered mockups

Notation: `[dim]`, `[bold]`, `[cyan]` mark spans that render with the corresponding tput attribute; unmarked = default weight. Column grid matches the current `'  %2d) %-28s %s\n'` layout (value starts col ~36). State assumed: `AI_PROVIDER=openrouter`, both API keys set, models/prompt unset.

### 4a. Scope `ai` — BEFORE (what the user flagged)

```text

pos config — ai (ai.env)
------------------------------------
   1) AI_PROVIDER                  openrouter
      Provider (gemini or openrouter, default gemini)
   2) AI_GEMINI_API_KEY            AIzaSy...fDp8 (39 chars)
      Gemini API key from aistudio.google.com
   3) AI_GEMINI_MODEL              (not set)
      Gemini model id (default: gemini-2.5-flash)
   4) OPENROUTER_API_KEY           sk-or-v...wXyZ (64 chars)
      OpenRouter API key from openrouter.ai
   5) OPENROUTER_MODEL             (not set)
      OpenRouter model id (default: openrouter/auto)
   6) AI_SYSTEM_PROMPT             (not set)
      Custom system prompt (overrides built-in, empty to reset)

Variable number [q to quit]:
```

Defects visible: 4 of 6 rows irrelevant right now, indistinguishable from load-bearing ones; no grouping; no hierarchy; placeholder looks like data; prompt hides `r`.

### 4b. Scope `ai` — AFTER

```text

[pos bold]pos config — ai (ai.env)
[cyan]────────────────────────────────────────
   [dim]1)[/] [bold]AI_PROVIDER[/]                openrouter
      Provider (gemini or openrouter, default gemini)

   [dim]── Gemini — inactive while AI_PROVIDER=openrouter        [/](whole group dim)
   [dim] 2)  AI_GEMINI_API_KEY          AIzaSy...fDp8 (39 chars)[/]
   [dim]       Gemini API key from aistudio.google.com[/]
   [dim] 3)  AI_GEMINI_MODEL            (not set)[/]
   [dim]       Gemini model id (default: gemini-2.5-flash)[/]

   [dim]── OpenRouter[/]
    4) [bold]OPENROUTER_API_KEY[/]         sk-or-v...wXyZ (64 chars)
          OpenRouter API key from openrouter.ai
    5) [bold]OPENROUTER_MODEL[/]           (not set)
          OpenRouter model id (default: openrouter/auto)

   [dim]── General[/]
    6) [bold]AI_SYSTEM_PROMPT[/]           (not set)
          Custom system prompt (overrides built-in, empty to reset)

Number to edit [r=refresh, q=quit]:
```

(Indentation above is schematic; normative grid = 3.3 table: numbers `%2d)` at current positions, keys padded as today, captions at 2-space indent.) Reading the AFTER top-to-bottom: selector first; the irrelevant group says in words why it's inactive; the active provider's two rows are the visually normal block; general behavior last. The complaint is resolved without touching edit flow.

### 4c. Scope `system` — BEFORE (contrast/genericity proof)

```text

pos config — system (system.env)
------------------------------------
   1) BACKUP_SERVICE_ROOTS        (not set)
      Roots scanned by backup --service and the health backup-age check (default: /srv $HOME/srv)
   2) HEALTH_BACKUP_MAX_AGE_DAYS  2
      Max backup age in days before health warns (default 2)

Variable number [q to quit]:
```

(desc of row 1 is 92 chars → ragged wrap into row 2's space on an 80-col terminal.)

### 4d. Scope `system` — AFTER (header UNCHANGED — proves backward compatibility)

```text

[bold]pos config — system (system.env)
[cyan]────────────────────────────────────────
   [dim]1)[/] [bold]BACKUP_SERVICE_ROOTS[/]        (not set)
       Roots scanned by backup --service and the health
       backup-age check (default: /srv $HOME/srv)
   [dim]2)[/] [bold]HEALTH_BACKUP_MAX_AGE_DAYS[/]  2
       Max backup age in days before health warns (default 2)

Number to edit [r=refresh, q=quit]:
```

No captions declared → no group machinery appears; the only differences are the uniform typography tier (title/rule/dim placeholder/wrap/prompt). Same holds for `telegram`, `matrix`, `scrcpy`, `ytsync`, `compose`, `notify`, `entertainment` — all headers stay valid as-is.

[DONE]

## Step 5: Impact map

**Code — `lib/config-ui.sh` (single implementation file):**

| Function / region | Change |
|---|---|
| Header grammar comment :7-15 | document `@caption`, `@[K=v1|v2] caption`, `*providers=<tag>` |
| Guarded helper fallbacks :24-28 area | add `BOLD/DIM/CYAN/RESET` guarded fallbacks (menu-lib.sh:29-31 pattern) |
| NEW caption parsing (inline in `cfg_scope_keys` field loop :188-199) | branch fields starting with `@` before the wildcard `case`; emit `>|cond|caption|` records; pass `<tag>` through to `_cfg_provider_keys` |
| `_cfg_provider_keys` :141-173 | optional tag arg: iterate files individually (or attribute grep output per file) and keep only `<tag>.sh`; warn on explicit-tag-zero-match |
| `cfg_value` :207-214 | unchanged, reused for condition evaluation |
| `cfg_display` :243-257 | unchanged (masking untouched per constraint) |
| `_cfg_edit_one` :301-332 | unchanged (never receives `>` records — numbering map guarantees it) |
| `cfg_ui` :335-385 | typography table 3.3, caption rendering + lazy flush + cond eval, number→index map, desc/example/caption wrapping, `{ … } >&2` render block, prompt text :371 |

Unchanged: `cfg_tools_dir`, `cfg_headers`, `cfg_scopes`, `cfg_scope_envfile`, `_cfg_key_line`, `_cfg_plugin_keys`, `cfg_validate`, `cfg_read_secret`, `cfg_write`, `_cfg_post_write`.

**Headers:** `bin/pos-ai:6` rewritten as in 3.1 (only tool header change; other scopes intentionally left as-is).

**Hand-maintained docs (doc-sync class, no GEN involvement):** `bin/pos-config` usage text (:25-30 grammar sample, :32 add "`r` redraws"); `DOC/POS.md` §`pos config` (~:486-492, one sentence on captions); `DOC/DEV.md` config-files bullet (~:158, mention caption/tag grammar); optional follow-up for the owner: add `@Plugins` caption before `*plugins` in `bin/pos-entertainment-config:4`.

**Generated artifacts:** `make gen` MUST be re-run because `bin/pos-*` changed (AGENTS.md definition of done), but expected diff is **empty**: gen-docs.sh:153-164 and completions/pos.bash:193-208 read only scope names; tree/dispatch tables read `# POS:` descriptions (untouched). `lib/registry.sh:107` passes header lines through verbatim → no consumer impact; its grammar comment may gain one line as courtesy.

**Gates/lint:** `make check` (bash -n, exec bits, doc-sync, dispatch smoke) — no new files, no header removals → expected green. `make lint` — config-ui.sh stays a sourced lib (no `POS:`-header/help requirements apply, same as today); new helpers follow `cfg_`/`_cfg_` naming; strict-mode-safe parsing required (no new stdin readers → `INTERACTIVE_CMDS` untouched). CI tag gate unaffected beyond the normal four commands.

**Tests:** none exist; recommend Builder smoke covers: old-style scope (e.g. telegram) renders with typography tier and NO group lines; caption condition true/false/unset-selector-with-empty-alt; `*providers=<unknown-tag>` warn + suppressed caption; numbering stability after switching `AI_PROVIDER` mid-session; installed-layout sourcing (`/usr/local/bin` fallback chain).

Estimated size: ~+45/−12 lines in config-ui.sh, 1 header line, 3 doc touchpoints.

[DONE]

## Step 6: Out of scope / rejected alternatives

Considered and rejected, with reasons:

- **Hiding inactive provider groups entirely** — renumbering churn mid-session + hides that the settings exist; dimming achieves clarity without unpredictability.
- **Inferring relevance from naming conventions** (e.g. "keys sharing a `_PROVIDER` suffix prefix") — implicit magic, breaks silently on renames; explicit metadata beats inference.
- **Per-key (non-caption) activity flags** like `secret,gemini:` flag values — overloads the flags grammar that validation switches on; caption-level grouping covers the actual complaint with less grammar.
- **Color-status encoding (green=active / red=inactive)** — color-only meaning fails monochrome terminals and color-blind users; implies judgement ("red = bad") inappropriate for merely-inactive config; DIM + textual reason is safer.
- **Two-column / box-drawing table layout** — fragile across the stated 80–120 col range, hostile to copy-paste and screen readers, high code cost for low gain.
- **Dynamic value-column width** (measure longest key) — marginal gain over the adequate fixed `%-28s`; adds a pre-pass over keys for cosmetic parity.
- **Alphabetical key sorting** — destroys declared/logical order and future grouping intent.
- **Hierarchical numbering (`2.1`, `2.2`)** — input-parsing complexity and wider number column for zero selection benefit.
- **Pagination / scrolling for long scopes** — largest scope today is 9 entries + descs ≈ fits a terminal page with scrollback; premature.
- **Masking redesign, env-file format changes, new keystrokes/flows** — excluded by task constraints; nothing above touches them.
- **Rewriting config-ui onto `lib/registry.sh`** while we're in here — a refactor, not a readability fix; registry passthrough already tolerates the new grammar.

[DONE]

---

## Handoff

Status: **DESIGN_READY**

- Objective: make `pos config <scope>` listings clearly readable without breaking genericity.
- Specification: §3 (grammar extension, rendering rules, interaction/a11y), mockups §4, impact map §5.
- Affected: `lib/config-ui.sh`, `bin/pos-ai` (header), 3 doc touchpoints; generated outputs unchanged.
- Constraints for Builder: keep masking/display formats and edit flow byte-compatible; no per-scope branches; reuse common.sh color tokens with guarded fallbacks; run `make gen && make check && make lint` (expect zero gen diff).
- Open design questions: none blocking. Risks: DIM legibility on exotic palettes (mitigated: secondary info only, meaning duplicated in text); typo'd condition keys yield a permanently dim group (visible, self-inflicted, documented).
- Recommended next agent: **Builder** — spec is implementable without further design decisions.
