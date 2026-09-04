# Builder Report — POS Command Registry, Phase 2

**Date:** 2026-08-26
**Status:** COMPLETE

---

## TL;DR

- **Status:** All 3 steps implemented and verified
- **Files changed (this phase):** `bin/pos` (`_pos_category_help()` migration), `bin/pos-network-download`, `bin/pos-media-sync`, `bin/pos-system-backup`, `bin/pos-docker-ps` (headers), `scripts/gen-docs.sh` (2 cell-rendering fixes), gen output in `DOC/AGENT_Context_Project.md`
- **Gates:** `make check` ✅ OK · `make lint` ✅ **0 FAIL, 0 WARN** · fast dispatch path unchanged (26 ms)
- **Key finding:** `pos help <command>` is a pure exec-redirect — no per-command dispatcher surface exists; per brief, nothing invented

---

## Baseline

- Phase 1 state on disk; `make check` → `check-sync: OK`
- Maintainer's uncommitted fixes present (`ai-alias` added to `INTERACTIVE_CMDS` at bin/pos:262, DOC updates) — **untouched**
- BEFORE category-help captured for all 10 categories → `/tmp/pos-phase2/h-*-before.txt`

[DONE]

---

## Step 1: Migrate `_pos_category_help()`

**File:** `bin/pos`, `_pos_category_help()` (~lines 68–100 post-edit)

**Changes:**
- Registry sourced + `reg_scan "$self"` called **lazily inside the function** — plain dispatch paths never pay scan cost (verified: fast path 26 ms before and after)
- Tool list from `reg_tools_in "$cat"`, stripped of leading `$cat-` → identical short display names
- All sed header reads replaced by `reg_lookup "<cat>-<short>" desc|subcmds|deps`
- Nested-tool enrichment loop, `is_nested` skip, printf layout: **byte-for-byte preserved**

**Preservation proof (pre-headers):** diff of before/mid captures across all 10 categories → **zero differences**.

**New behavior (fires only when headers exist):** second indented line `    [deps: <deps>]` directly under a tool's description line.

[DONE]

---

## Step 2: Registry metadata in `pos help`

**Finding:** the `help` meta-command (bin/pos ~lines 233–245) joins args into `pos-<cat>-<cmd>` and `exec`s the tool's own `--help`. There is **no per-command rendering surface in the dispatcher** — examples/deps shown there come from each tool's `usage()` heredoc. Per the brief's instruction ("do NOT invent new UX"), this step is limited to that finding: no dispatcher-side extension made. The category-help surface (Step 1) is where registry metadata surfaces.

[DONE]

---

## Step 3: Representative headers on existing tools

Guards re-verified by reading source before annotating:

| Tool | Hard guards found | Headers added |
|------|-------------------|---------------|
| `bin/pos-network-download` (lines 10–12: `err` ×3) | aria2c, jq, curl | `# POS_DEPS:` + 3 real-subcommand EXAMPLES (add/status/watch) |
| `bin/pos-media-sync` (lines 15–16: `err` ×2) | lsblk, jq | `# POS_DEPS:` + 2 EXAMPLES (`--mp3`, `--mp4 --dry-run` — straight from its usage()) |
| `bin/pos-system-backup` (line 60 `err`; 72–73 `warn`; 179 conditional `err`) | tar | `# POS_DEPS: tar` only |
| `bin/pos-docker-ps` (line 16: single `err`) | docker | `# POS_DEPS: docker` |

**Decision note (system-backup):** lsblk/jq are warn-only soft guards ("USB copy skipped", returns 0); gpg errors only when encryption is requested (`--no-encrypt` bypasses). Deps header = hard requirements only → `tar`.

4 tools total (cap 5 respected). Placement rule followed: metadata headers in comment block, `# POS:` first, new headers after existing POS_* lines, before any code.

[DONE]

---

## Verification (per budget)

```
bash -n bin/pos                                    ✅
category --help before/mid diff (10 categories)    ✅ zero diff (Step 1 preservation)
category --help before/after diff                  ✅ only [deps: …] lines added:
                                                     network +1, docker +1, system +1, media +1; others 0
make gen && git diff --stat                        ✅ GEN changes confined to expected blocks
make check                                         ✅ check-sync: OK
make lint                                          ✅ 0 FAIL, 0 WARN
bin/pos-tree | grep deps                           ✅ 4 annotations visible
bin/pos network --help | grep -i deps              ✅ [deps: aria2c jq curl]
fast path timing                                   ✅ 26 ms (no reg_scan cost)
completions/pos.bash                               ✅ untouched by gen
```

**GEN block inspection (as instructed):**
- Tree gains `[deps: …]` annotation lines under annotated tools ✓
- Dispatch table flipped to 6-column format (`_has_deps_examples=1`) ✓
- Two rendering defects found & fixed in `gen-docs.sh` during inspection:
  1. Examples cell contained raw inner pipes from the `cmd | desc` grammar → broke markdown column count. Fixed: inner ` | ` rendered as `→` within cells.
  2. Intended `//` example joiner actually produced single `/` (`paste -d'//'` cycles chars). Fixed: awk-based literal `//` join.
- Resulting cell sample: `…| lsblk jq | pos media sync --mp3 → Sync only MP3 files to USB//pos media sync --mp4 --dry-run → Preview MP4 sync without copying |` — valid 6-column row, readable ✓
- Docmap line ranges shifted accordingly (auto-generated) ✓

---

## Artifacts Summary

### Modified this phase
| File | Change |
|------|--------|
| `bin/pos` | `_pos_category_help()` → registry API + lazy source + deps line (Maintainer's INTERACTIVE_CMDS line preserved verbatim) |
| `bin/pos-network-download` | DEPS + 3 EXAMPLES headers |
| `bin/pos-media-sync` | DEPS + 2 EXAMPLES headers |
| `bin/pos-system-backup` | DEPS header (hard dep only) |
| `bin/pos-docker-ps` | DEPS header |
| `scripts/gen-docs.sh` | Examples-cell pipe escaping (`→`) + correct `//` joiner |
| `DOC/AGENT_Context_Project.md` | Gen output only (tree annotations, 6-col dispatch, docmap shift, filetable line counts) |

### Not touched (constraint compliance)
`lib/config-ui.sh` ✅ · `completions/pos.bash` ✅ · `INTERACTIVE_CMDS` ✅ · Maintainer's fixes ✅ · `bin/pos-tree` rendering ✅ · no new files except report ✅

### Findings / deferred
- `reg_scan` ≈ 1.3 s on this box (≈250 process forks / 41 tools) — acceptable on lazy help-only paths; single-pass awk scan remains the anticipated future optimization (Phase 1 Risk 2)
- `pos help <command>` has no dispatcher-side surface to enrich (pure redirect)

---

## Review-fix round

Two findings from the Phase 2 adversarial review; both fixed minimally.

### Finding 1 (MEDIUM): stale hand-written table header above the dispatch GEN block — FIXED

**Exact lines removed** from `DOC/AGENT_Context_Project.md` (were lines 275–276):

```
| Category | Command | Script | Description |
|----------|---------|--------|-------------|
```

The orphaned 4-column header + its underline row sat between `### Available Commands` and `<!-- GEN:START dispatch -->`, duplicating the GEN block's own 6-column header. Nothing else removed — the section now reads `### Available Commands` → blank line → `GEN:START dispatch` directly.

### Finding 2 (LOW): `//` example joiner collides with URL slashes — FIXED

**New separator:** `" · "` (space-middle-dot-space), replacing the literal `//` in `scripts/gen-docs.sh` line ~48. Awk literal-join approach unchanged.

Rationale for `·`: cannot appear in a URL path, reads as a list separator in a markdown cell, and stays clear of both the pipe grammar (` | ` inside a single example, rendered as `→` in cells) and the em-dash used by `# POS:` descriptions. Live case now renders:
`pos network download add https://example.com/file.zip → Enqueue an HTTP download (auto-starts daemon) · pos network download status → Daemon health + global transfer stats · pos network download watch → Live progress view`
— the URL's `//` survives intact and each example is cleanly delimited.

### Verification

```
bash -n scripts/gen-docs.sh                        ✅
make gen && make gen → md5 of generated files identical
                                                   ✅ double-gen idempotence: ZERO drift after second run
grep -c 'Category.*Command' DOC/…Project.md        ✅ = 1 (only the GEN block's own header)
sed -n '/GEN:START dispatch/,+4p'                  ✅ GEN header is first row in block
lines above GEN:START dispatch                     ✅ only "### Available Commands" + blank
make check                                         ✅ check-sync: OK
make lint                                          ✅ 0 FAIL, 0 WARN
```

Note: the earlier bare `git diff --exit-code` after gen exits 1 because ALL Phase 1+2 work is still uncommitted vs HEAD — checksum comparison of run-1 vs run-2 outputs is the correct idempotence measure and passes.

### Constraint compliance

Touched ONLY `DOC/AGENT_Context_Project.md` (2 stale lines) and `scripts/gen-docs.sh` (separator string). No bin/*, lib/*, or completions/ changes. Everything else regenerated via `make gen`.

[DONE]

---

## Alias generator quoting fix

**File:** `bin/pos-ai-alias` (`_alias_regen()`, new `_alias_quote_cmd()` helper, `_alias_show()` command line)

### Chosen mechanism + rationale

`printf '%q'` — the canonical bash mechanism — applied **per layer**:

1. `_alias_quote_cmd <provider> <session> <prompt>` builds the pos-ai command with `%q`-quoted prompt → the prompt is ONE shell word on expansion.
2. `_alias_regen` then `%q`s the ENTIRE value before emitting `alias name=<value>` → the assignment survives any bytes.

**Justified deviation from the brief's literal snippet:** the prescribed single-`%q`-over-whole-string form expands to multi-word args after `--system`, but `bin/pos-ai`'s parser takes exactly one value (`SYSTEM_PROMPT="$2"; shift 2`, bin/pos-ai:640–642) — multi-word prompts would truncate to their first word with the remainder leaking into question positionals. The original code had the identical latent defect (single-quote fragments never survive alias-expansion re-parsing). Double-`%q` is the same single mechanism, applied once per quoting layer — no manual fragment concatenation, no mixing of approaches. Verified by exact round-trip (A4/A7).

### Diff summary

| Function | Change |
|----------|--------|
| `_alias_quote_cmd()` (new, ~10 lines) | Shared builder: `%q` prompt as one word; empty prompt → no `--system`; used by regen + show |
| `_alias_regen()` | Naive `'…'<escaped>'…'` concatenation replaced by helper + whole-value `%q`; collects names; keeps `bash -n "$tmp"`; ADDS semantic per-name check in fresh shell: `bash --norc -c 'shopt -s expand_aliases; source "$1" && [[ $(type -t "$2") == alias ]]' _ "$tmp" "$n"`; failure → warn(alias name) + keep previous + rc 1 (mirrors existing path). Note: `expand_aliases` required — non-interactive shells define aliases but `type -t` only reports them when expansion is on (found during self-test) |
| `_alias_show()` | Command line now rendered via `_alias_quote_cmd` (display-only; structure untouched) — what users copy pastes verbatim |

Unchanged per constraints: ENV_FILE format, `|` ban, name/session regexes, chmod/mv semantics, interactive flows.

### Harness (exact commands)

```bash
export CONFIG_DIR=/tmp/pos-alias-test
rm -rf "$CONFIG_DIR"; mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_DIR/ai-aliases.env" <<'EOF'          # fixture as specified
# AI aliases — managed by pos ai alias (do not hand-edit)
assist|gemini|assist|You are assist, a concise and practical AI assistant.
evil|gemini|evil|It's a 'quoted' $(rm -rf /) `backtick` \backslash "dq" ;semi|pipe-less
plain|openrouter|plain|
EOF
# regen via function extraction (sanctioned approach):
bash -c 'source lib/common.sh
  ENV_FILE="$CONFIG_DIR/ai-aliases.env"; SH_FILE="$CONFIG_DIR/ai-aliases.sh"
  eval "$(awk "/^_alias_quote_cmd\(\)/,/^}/" bin/pos-ai-alias)"
  eval "$(awk "/^_alias_regen\(\)/,/^}/" bin/pos-ai-alias)"
  _alias_regen'
```

**Fixture nuance:** `evil`'s prompt contains `|`; the loader's `IFS='|' read … _rest` splits it off (pre-existing behavior — this is why prompts ban `|`). Round-trip asserts against the loader-stored string (`…;semi`), not the hand-edited tail.

### Assertion results

| # | Assert | Result |
|---|--------|--------|
| A1 | `bash --norc -c "source $SH"` → rc 0, **zero stderr** | ✅ |
| A2 | No execution while sourcing (`$CONFIG_DIR/pwned` absent) | ✅ |
| A3 | `type -t assist/evil/plain` == `alias` (fresh shell) | ✅ all three |
| A4 | evil expansion round-trip via `eval "set -- ${BASH_ALIASES[evil]}"` (no execution): post-`--system` words join to **exact original prompt**, delivered as one arg | ✅ byte-exact |
| A5 | `plain` emits no `--system` fragment | ✅ |
| A6 | Regen idempotence (second run md5-identical) | ✅ |
| A7 | `pos ai alias show evil` Command line, evaluated via `eval set -- $(cat …)`, yields exact prompt | ✅ byte-exact |

Also verified end-to-end: `bin/pos-ai-alias list`, `bin/pos ai alias show plain` (dispatcher path) behave normally.

### Gates

```
bash -n bin/pos-ai-alias   ✅ syntax OK (563 lines)
make gen                   ✅ (filetable row for pos-ai-alias updated automatically)
make check                 ✅ check-sync: OK
make lint                  ✅ 0 FAIL, 0 WARN
```

[DONE]
