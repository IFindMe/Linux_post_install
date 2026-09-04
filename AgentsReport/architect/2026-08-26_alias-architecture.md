# Architecture: `pos ai alias` — robust activation mechanism

**Date:** 2026-08-26
**Author:** Architect (ox-alpha)
**Status:** DECISION_READY (supersedes activation decisions in `AgentsReport/architect/2026-08-26_ai-alias-architecture.md`)

---

## TL;DR

| Decision | Choice |
|----------|--------|
| D1 — Activation artifact | **Option B**: executable wrapper scripts at `~/.local/bin/<name>`, generated from the ENV source of truth. No shell aliases. |
| D2 — Migration | Internal `_alias_sync()` runs on every `pos ai alias` invocation; reconciles wrappers ↔ ENV both directions; legacy `ai-aliases.sh` auto-removed when marker-guarded, else manual guidance. `.sh` generation stops entirely (no deprecated shim). |
| D3 — Edge cases | Name collisions refused (foreign file or other binary on PATH); empty set → sync deletes all owned wrappers; dead provider → existing `pos-ai:121` error is sufficient; list/show formats unchanged, show gains wrapper path. |
| D4 — Scope fence | Only `bin/pos-ai-alias` + small marker-scan addition to `bin/pos-system-uninstall` + docs. NOT: `bin/pos-ai`, ENV format, config-ui, postinstall.sh, menu flows. |
| Postinstall gap | The deferred `.bashrc` wiring is closed by **obsolescence**, not implementation — no wiring needed anymore. |

**Open items:** None blocking. One provisional nuance in D2 (legacy-file heuristic guard) flagged inline.

---

## Problem statement

- Aliases were frozen at source-time: editing provider gemini→openrouter left the stale alias live in running shells → Gemini 429 while `list` showed openrouter (live failure).
- Activation required a `.bashrc` source line that postinstall never wired — the feature was broken-by-omission even before staleness.
- Non-interactive contexts (cron, scripts, ssh non-login) could never use aliases at all.

## Evidence base

- `bin/pos-ai-alias:62-104` — current `_alias_regen()` writes `ai-aliases.sh`; success messages at :308 say "Reload shell: source ~/.bashrc".
- `postinstall.sh:80` — PATH export already includes `$HOME/.local/bin` on pos-managed machines (Debian default `~/.profile` also adds it when the dir exists).
- `bin/pos-system-uninstall:96,261` — established precedent for marker-managed user-local binaries (`$HOME/.local/bin/pos-ai-hook.sh`): discovery list + removal pass already exist as a pattern.
- `bin/pos-ai:658-665, :118-121` — provider resolution flag > env > default; unknown provider yields `err "Unknown provider '$p' — available: …"` (good runtime failure quality, no pos-ai change needed).
- Prior architect report D5/D10 chose `.sh` + `.bashrc` wiring; the wiring was never implemented. This report supersedes those two decisions; storage (ENV format) and CRUD UX decisions carry forward unchanged.

---

## Decision 1: Activation artifact

### Options evaluated

**Option A: keep generated bash aliases + wire `.bashrc` + louder hints + unalias guards**
- Advantages: smallest diff; familiar alias UX.
- Costs: staleness is *inherent* — the artifact is a snapshot copied into each shell at source time; the live failure (stale gemini alias) can only be mitigated, never eliminated. Requires postinstall `.bashrc` wiring (the deferred gap), reload-hint UX that demonstrably fails ("users miss it"), and per-shell unalias guard logic for a mechanism bash makes awkward to retract.
- Risks: cron/scripts/ssh non-interactive shells get nothing. Two truths (env file vs sourced copy) persist forever.
- Compatibility impact: none. Operational impact: permanent "did you re-source?" support burden.

**Option B: executable wrapper scripts at `~/.local/bin/<name>`**
- Architecture: ENV stays the single source of truth; tool renders one standalone script per alias:
  ```bash
  #!/usr/bin/env bash
  # Managed by pos ai alias — regenerated automatically; hand-edits are overwritten.
  # Alias: assist | provider: openrouter | session: assist
  set -euo pipefail
  exec pos ai openrouter ask --session assist --system <printf-%q-prompt> "$@"
  ```
  (empty prompt → omit `--system`; prompt embedded via existing double-layer `printf %q` mechanics, reused from `_alias_quote_cmd`, so it lands as exactly ONE shell word; `"$@"` passes user args through).
- Advantages: **staleness eliminated** — next invocation reads current file bytes; no shell integration of any kind (kills the postinstall gap instead of closing it); works identically in interactive shells, scripts, cron, ssh non-login; removal = delete one marker-identified file; no INTERACTIVE_CMDS/tee-pipe interaction changes; content edits bypass `hash` caching entirely (bash caches paths, not contents) and new names are found on first PATH scan.
- Costs: PATH-presence dependency (`~/.local/bin` must be on PATH — already guaranteed by `postinstall.sh:80` and Debian default `~/.profile`, but needs a runtime check + guidance); collision policy needed (scripts are filesystem entries, aliases weren't); ~40 lines more logic than Option A.
- Risks: name shadows a real binary → mitigated by refusal policy (D3); user hand-edits wrapper → healed by sync regeneration (D2), and the header says so.
- Compatibility impact: activation semantics change (documented). Operational impact: self-healing artifacts; zero shell-config coupling. Migration impact: handled by D2.

**Option C: hybrid — wrappers primary + optional still-generated alias file**
- Advantages: covers users attached to aliases.
- Costs: keeps the stale-snapshot mechanism alive alongside the fix — two activation paths, two truth-drift surfaces, double the validation matrix. Directly contradicts the motivation ("more robust" = fewer failure modes, not one more).
- Risks: the exact reported bug remains reachable through the optional path.

### Decision: Option B

Staleness was an architectural property of source-time snapshots, not an implementation bug — no amount of hints or guards fixes Option A. Option B removes the class of bug (artifact always equals source of truth at invocation time) and deletes the deferred `.bashrc` wiring requirement rather than implementing it. Option C preserves the bug class for zero new capability. Smallest robust design wins.

**Artifact specification (binding for Builder):**

| Property | Value |
|----------|-------|
| Location | `${HOME}/.local/bin/<name>` |
| Permissions | `0755` |
| Ownership marker | Line 2 contains literal `Managed by pos ai alias` (grep target for all ownership checks) |
| Body | `set -euo pipefail` + single `exec pos ai <provider> ask --session <session>[ --system <%q prompt>] "$@"` |
| Quoting | Reuse `_alias_quote_cmd` verbatim (double-layer `%q` mechanics preserved per brief) |
| Atomic write | mktemp in same dir → `mv` → `chmod 755` (same pattern as current `_alias_regen`) |
| Pre-commit validation | `bash -n` on rendered wrapper; on failure warn + keep previous file |
| Secrets | None inside (prompt is content, not credential) |

[DECIDED]

## Decision 2: Migration & back-compat

### Regeneration trigger: `_alias_sync()` on every invocation

New internal function, called at the top of **every** subcommand dispatch entry (`create`, `edit`, `remove`, `list`, `show`, interactive menu) before the subcommand's own logic. It reconciles `~/.local/bin` against the ENV file in both directions:

1. For each ENV entry: render expected wrapper content; if target is missing **or differs byte-wise** → atomically install. This means:
   - first run after upgrade materializes wrappers for all existing aliases (one-time migration happens on any command, including a harmless `list`);
   - every create/edit/remove leaves artifacts consistent by construction;
   - hand-edited or half-deleted wrappers are silently healed (idempotent, cheap for realistic alias counts).
2. Every executable in `~/.local/bin` bearing our marker whose name is **not** in ENV → deleted (covers remove, covers manual ENV edits, covers the empty-set case).
3. If ≥1 wrapper exists/installed and `$HOME/.local/bin` is absent from `$PATH` → loud `warn` with copy-paste fix (`export PATH="$HOME/.local/bin:$PATH"` + persist to `~/.profile`). Wrappers are still written regardless.
4. Legacy handling (below).

No public `sync` subcommand: every subcommand already syncs, so an explicit one adds surface without capability. `POS_SUBCMDS` header stays `create edit remove list show`.

### Existing `ai-aliases.sh`: stop writing entirely — no deprecated shim

A shim keeps two activation truths alive, and the sourced-alias-still-shadows-wrapper scenario is precisely the reported failure mode (in interactive bash, aliases take precedence over PATH lookups). The `.sh` artifact must die, not fade.

On detecting `SH_FILE`, sync emits a warning block explaining that activation moved to `~/.local/bin/<name>` scripts and that stale sourced aliases shadow them until cleaned. Then:

- **If line 1–3 of the file carry our generator marker** (`Auto-generated by pos ai alias`) → auto-remove the file and print remediation for *running* shells: an `unalias <names>` line with names extracted from the `.sh` contents themselves (the stale file inventories its own definitions — including names no longer in ENV), plus "or simply start a new shell". Auto-remove is safe because (a) the file is regenerable output, not user data, (b) postinstall never shipped the source line, so nothing references it at startup, and (c) the conditional-source idiom (`[ -f ] && source`) tolerates absence even if a user wired it manually.
- **If the marker does not match** (foreign/hand-built file) → leave untouched; advise manual review. Never delete files we didn't generate — same policy as wrapper collisions.

*[PROVISIONAL nuance]* The auto-remove guard currently checks only the generator-marker header; a user who appended private aliases into our generated file would lose them on upgrade-migration. Accepted risk: the file header says "do not hand-edit", likelihood is low, and the alternative (parsing full-file provenance) buys complexity the requirement doesn't need. Revisit only if a real case appears.

### What carries over unchanged

- `ai-aliases.env` format, location, chmod 600, comment conventions — untouched. Previously created aliases migrate with zero data conversion.
- `pos config` compatibility: no env-key semantics touched.
- All menu flows, name regex, non-tty guard behavior.

[DECIDED]

## Decision 3: Edge cases & subcommand semantics

### Name collisions with real binaries — refuse

Create-time check order (after existing ENV-duplicate redirect to `edit`):

1. `$HOME/.local/bin/<name>` exists **with** marker → not a collision; sync will overwrite (regeneration path).
2. `$HOME/.local/bin/<name>` exists **without** marker → refuse: `err "File '~/.local/bin/<name>' already exists and was not created by pos ai alias — pick another name"`. Never silently overwrite foreign files.
3. `command -v <name>` resolves to anything else on PATH (`ls`, `git`, `gcc`, …) → refuse with the conflicting path named.

No override flag. Shadowing an arbitrary binary is never a legitimate intent for an *alias* feature, a refusal error costs one rename, and a `--force` surface invites exactly the "surprise factor" this rework is meant to remove. Edit cannot collide (name is the record key); rename remains remove+create (Designer out-of-scope list already excludes renaming).

### Empty result set → wrappers fully retracted

With zero ENV entries, sync deletes every marker-bearing wrapper in `~/.local/bin`. `list` prints `Aliases (0):` as today. No empty husks left behind.

### Provider adapter deleted later → runtime failure is already good enough

Wrapper execs `pos ai <provider> …`; if the adapter vanished, `bin/pos-ai:121` errors: `Unknown provider '<p>' — available: gemini openrouter`. Actionable, names valid alternatives, zero changes to `pos-ai`. Sync does **not** prune wrappers whose provider directory entry disappeared (ENV is truth for existence; a temporarily missing adapter shouldn't silently eat user config). The provider picker at edit time only offers installed providers, so edit is the natural repair path.

### Subcommand semantics under Option B

| Subcommand | Change |
|------------|--------|
| `list` | Format unchanged; runs after sync so it always reflects disk truth |
| `show <name>` | Adds one line: `Wrapper:  ~/.local/bin/<name>` (or `(not installed)` if PATH check failed) |
| `create` | Gains collision refusals above; success message replaces "Reload shell: source ~/.bashrc" with `Available immediately: ~/.local/bin/<name>` (+ PATH warning when applicable) |
| `edit` | Unchanged flow; on save, sync refreshes the wrapper — change is live on next invocation (this kills the reported bug) |
| `remove` | Unchanged confirm(default=n); success message notes the script was deleted from `~/.local/bin`; add hint that running shells may need `hash -r` only if the name still autocompletes stale (rare; bash normally re-scans when a hashed file vanishes) |
| menu / `-h` | Help text updated: activation = executable scripts in `~/.local/bin`, no sourcing required |

[DECIDED]

---

## Decision 4: Scope fence for Builder

### Approved outcome
Alias activation via marker-managed wrapper scripts in `~/.local/bin`, synced against `ai-aliases.env` on every invocation, with legacy `.sh` auto-retirement.

### In-scope components/files
| File | Allowed changes |
|------|-----------------|
| `bin/pos-ai-alias` | Replace `_alias_regen()` with `_wrapper_path()` + `_wrapper_render()` + `_alias_sync()`; keep `_alias_quote_cmd` mechanics verbatim; add `_alias_check_path()`; wire sync into all dispatch entries; collision checks in `_alias_create`; message deltas in create/edit/remove/show/usage; legacy `.sh` retirement block; SH_FILE constant retained solely for migration detection |
| `bin/pos-system-uninstall` | Add marker-scan of `~/.local/bin` (grep for `Managed by pos ai alias`) to the discovery list (~line 96 area) and removal pass (~line 261 area), mirroring the existing `pos-ai-hook.sh` pattern — closes uninstall hygiene |
| `DOC/POS.md` | `ai alias` section: activation semantics, subcommand table unchanged otherwise (hand-maintained file) |
| `DOC/HOWTO.md` / relevant howto | Row/section wording update if it mentions sourcing/reload |
| `AGENT_TODO.md` | Move task to Done (dated) in same commit |

### Must NOT change
- `bin/pos-ai` — any file byte.
- `ai-aliases.env` format, fields, header comments, chmod 600.
- `lib/common.sh`, `lib/menu-lib.sh`, `lib/config-ui.sh`.
- `postinstall.sh` — the deferred `.bashrc` wiring stays unimplemented by design (obsoleted, not added).
- `# POS:` / `# POS_SUBCMDS:` headers (description and subcommand set unchanged → no gen churn beyond none).
- Menu structure, step counts, name regex, non-tty guard behavior (Designer spec remains authoritative).
- Other categories' tools; entertainment plugins; completions (no flag/subcmd changes).

### Architectural constraints
1. Atomic writes only (mktemp+mv), never in-place truncation of live wrappers.
2. Ownership established exclusively via the line-2 marker string; never delete/overwrite files failing the marker test.
3. All output discipline per Designer spec: tables/results stdout, display/warnings stderr (`log`/`warn`/`err`).
4. Sync must be idempotent and safe to run concurrently-lossy (single-user tool: last write wins, no locking).
5. Wrapper body contains no secrets and no absolute paths except the `pos` lookup by name (PATH-resolved, consistent with old aliases).

### Required verification (adversarial where it matters)
1. `bash -n bin/pos-ai-alias`; `make gen && make check && make lint` ending `0 FAIL, 0 WARN`.
2. **Quoting round-trip through the NEW artifact**: prompts containing `'`, `"`, backtick, `$()`, `%`, `\`, unicode, leading/trailing spaces → create each; execute wrapper under a stubbed `pos` shim on a temp PATH capturing argv; assert `--system` arrives as exactly one intact word and passthrough args (`assist "hi there"`) append correctly.
3. **Staleness kill-test**: create `assist`(gemini) → run wrapper via shim → edit provider→openrouter → run again → argv shows openrouter with **no shell reload** (the regression test for the live failure).
4. Sync idempotency: two consecutive runs → byte-identical artifacts, mtimes stable second run.
5. Orphan retraction: delete an ENV line manually → next `pos ai alias list` removes that wrapper; empty ENV → zero owned wrappers remain.
6. Collision tests: foreign file at `~/.local/bin/<name>` → refused; marker file → refreshed; `command -v` conflict (e.g. `gcc`) → refused with path named.
7. Legacy migration: plant prior-generator-format `ai-aliases.sh` with stale `alias assist=…gemini…` → any subcommand removes it, prints `unalias assist` remediation; plant foreign-content file → untouched, warned.
8. PATH-absent: strip `$HOME/.local/bin` from PATH → loud warn, wrappers still written.
9. Non-tty: `pos ai alias` (menu) still fails cleanly via `menu_guard`.
10. Dead-provider runtime: wrapper pointing at removed adapter produces `pos-ai:121` available-providers error (assert message quality manually once).

### Explicitly out of scope
Rename operation; multi-line prompt input; alias import/export; public `sync` subcommand; completion headers; `pos config` integration; systemd/cron integration examples beyond help text.

### Open risks
- Users who sourced `ai-aliases.sh` into `.bashrc` manually keep a dead reference — harmless under the conditional-source idiom; warning text covers it.
- `~/.local/bin` absent from PATH in exotic shells (non-login ssh without postinstall) — mitigated by persistent warning + fix line.

[DECIDED]

---

## Builder-ready step order

1. Core rewrite in `bin/pos-ai-alias`: `_wrapper_path`, `_wrapper_render` (reuse `_alias_quote_cmd`; marker line 2; `set -euo pipefail`; `exec … "$@"`), `_alias_check_path`, `_alias_sync` (render-diff-install, orphan sweep, legacy block). Delete `_alias_regen` body (keep SH_FILE constant for migration).
2. Wire `_alias_sync` into every dispatch entry before subcommand logic.
3. Create-flow collision refusals (marker-aware, `command -v` check) + success-message swap ("Available immediately", drop reload hints everywhere including menu flows).
4. Edit/remove/show/list/usage deltas per D3 table.
5. `bin/pos-system-uninstall`: marker-scan additions in discovery + removal passes.
6. Full verification suite (D4 list) — quoting round-trip and staleness kill-test are the acceptance gates.
7. Docs (`DOC/POS.md`, HOWTO row) + `AGENT_TODO.md` Done entry; conventional commit (`feat:` or `fix:`).

Recommended next agent: **Builder** — scope is fully determined; no architectural choices remain. Suggest a Reviewer pass afterward focused on the marker-guard logic (the only place where a bug could delete/overwrite a foreign file).

Architect changes: this report only.
