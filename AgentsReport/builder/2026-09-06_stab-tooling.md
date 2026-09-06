# Builder Report — 2026-09-06 — Stabilization: Tooling track (lint perf, D-E uninstall, H-002/H-003)

**Scope (per brief):** `scripts/lint-conventions.sh`, `bin/pos-system-uninstall`, `DOC/POS.md` (system uninstall row only if factual); NOT touched: other files listed in the brief. `lib/install-manifest.sh` is **NOT** created — see D-E.

**TL;DR**
- Status: **DONE** — all 3 steps implemented, probed, gated.
- Files in scope changed by me: `scripts/lint-conventions.sh` (rewrite), `bin/pos-system-uninstall` (D-E/H-002/H-003), `DOC/POS.md` (system-uninstall row only), plus gen output in `DOC/AGENT_Context_Project.md` + `completions/pos.bash` (reflecting the whole shared tree, incl. parallel tracks).
- D-E explicitly says **do NOT** create `lib/install-manifest.sh` — the brief's manifest is conditional ("if D-E specifies it"); it does not, so I implement D-E's actual decision (extend `bin/pos-system-uninstall` directly, no manifest file).
- Baseline `make lint` = **145.9 s** (measured, `time`); final = **4.38 s**, `0 FAIL, 0 WARN`, output byte-identical to original (differential test). `make check` OK; `make gen` idempotent.
- H-002/H-003 probes pass: exact-literal + anchored `awk` removal removes only pos-owned lines; comments, user PATH/MY_POS_REPO lines, `repos`/`dispose`/`compose` completion, and `unrelated.service` all survive.
- Remaining risk: real-machine removal path validated via fixtures only (no live uninstall run) — see Step 3.

## Step plan
1. Lint performance rewrite (Task 1).
2. D-E uninstall extensions + H-002/H-003 + surviving-artifacts docs (Tasks 2, 3).
3. Probes + full gates.

---

## Step 1: Lint performance rewrite

Refactored `scripts/lint-conventions.sh` hot paths to bash-native parsing:
- Merged per-line `uses_stdin` + top-level-`local` scans (was `printf | sed | tail` × 3 forks per line) into ONE single-pass per-file read with heredoc-delimiter state via `[[ =~ ]]`.
- Folded `# POS:` header / em-dash / posline / first `-h|--help` line into the same loop.
- Shebang via `read -r first < "$f"`; POS.md coverage via one preloaded `cat` + `[[ ]]`; secret-literal + system-path scans → bash `[[ =~ ]]` with cheap string gates; deleted dead `last_line()`.
- System-path outer filter (`(\btee\b|>>?)[^#]*?(path)`) reimplemented faithfully (`_syspath_outer` — no fork, global `_SI`), preserving the no-`#`-between-operator-and-path semantics that bash `=~` cannot replicate.

**Verification:**
- `bash -n` OK.
- Differential test vs `git show HEAD:scripts/lint-conventions.sh`: **outputs byte-identical** (both exit 0, `0 FAIL, 0 WARN`).
- Negative test (broken tool): all expected FAIL/WARNs fire; skipped per-file checks on missing POS header match original `continue`.
- Timings (`time bash scripts/lint-conventions.sh`): **before 145.9 s → after 4.79 s (~30x)**. `time make lint` before: >120 s (timed out at 145.9 s for the bare script); after: see gates below.

[DONE]

---

## Step 2: D-E install/uninstall + H-002/H-003

### D-E reconciliation — NO `lib/install-manifest.sh`
D-E (architect decision `stabilization-design.md:399-401`) explicitly says: *"Do NOT introduce a full manifest abstraction (like `lib/install-manifest.sh`) — that would be a larger refactor inconsistent with the current 'list-based' approach"*. The brief's manifest requirement was conditional ("If D-E specifies `lib/install-manifest.sh`"); it does not. Per the scope rule (necessary-to-complete vs better-design), I implemented D-E's actual decision: **one** source of truth inside `bin/pos-system-uninstall` (singleton `POS_LIBS` array + `PATH_LINE`/`COMPLETION_LINE`/`HOOK_PATTERN` constants + `installed_plugins()` helper) used by both scan and remove — the removal list is no longer two hardcoded places. Nothing else in the codebase was introduced.

### Changes to `bin/pos-system-uninstall`
- **Libs (D-E 1):** `POS_LIBS` = all 12 libs from install.sh phase 2 (`common.sh flags.sh notify.sh entertainment-lib.sh scheduler-lib.sh config-ui.sh user-timers-lib.sh entertainment-plugin-lib.sh usb-lib.sh share-lib.sh menu-lib.sh registry.sh`); scan + remove loops both read the single array. Verified **byte-identical** to install.sh:143.
- **ScaleTail + flags store (D-E 2):** scan + remove for `/usr/local/share/linux_post_install/scale-tail/` and `/flags/`, then `rmdir` the parent if empty.
- **User systemd units (D-E 3):** scan + remove `$XDG_CONFIG_HOME/$HOME/.config/systemd/user/pos-*` (`disable --now` + `rm`, `|| true` wrapped; `daemon-reload` at end). `unrelated.service` probe survives.
- **De-hardcoded entertainment plugins (D-E 4):** `installed_plugins()` discovers installed plugins by `# POS_PLUGIN:` marker (matching install.sh's directory-driven install), used by scan + remove.
- **H-002 (D-E 5):** `.bash_completion` `sed -i '/pos/d'` replaced with anchored `awk '/^[[:space:]]*source[[:space:]].*pos\.bash/ { next } { print }'` + mktemp + `chmod --reference` + count.
- **H-003 (D-E 6):** `.bashrc` sed removals replaced with exact-literal `awk` removal of postinstall.sh's `PATH_LINE` + `COMPLETION_LINE` and anchored `HOOK_PATTERN='^[[:space:]]*source[[:space:]].*pos-ai-hook\.sh'` (comment-safe per D-E acceptance criterion 5). Note: the old `/linux_post_install.*PATH/d` never removed the real PATH_LINE anyway (that literal has no `linux_post_install` substring); the new code removes the installer's actual line.
- **Surviving artifacts (D-E 7):** usage() documents deliberately NOT removed: apt packages, `/usr/local/bin/yt-dlp`, `~/.config/rclone/`, `~/.ssh/authorized_keys` additions, config/data tiers.
- **DOC/POS.md:** system-uninstall row Tier 1 description updated (factual): adds user units + ScaleTail + flags store.

### Probes (all pass)
1. **H-002/H-003 fixture `.bashrc` (15 lines incl. unrelated `pos` lines + comments) → 3 lines removed** (PATH_LINE, COMPLETION_LINE, hook source); custom `MY_POS_REPO`, user PATH, `# source pos.bash` comments survive.
2. **Fixture `.bash_completion` (7 lines incl. `repos`/`dispose`/`compose`) → 1 line removed** (source pos.bash); `repos`/`dispose`/`compose` and comment survive.
3. **scan_tier1 (HOME fixture):** finds exact bashrc/bash_completion lines + `pos-aria2.service`, `pos-entertainment-weather.timer` user units; does NOT find `unrelated.service` or unrelated completion lines.
4. **remove block replication:** REMOVED_COUNT=6 (3 bashrc + 1 completion + 2 user units); unrelated content + `unrelated.service` survive; `systemctl --user` fails gracefully (`|| true`, no session).
5. **Inventory: POS_LIBS == install.sh lib list** (12 names identical); 13th `lib/pos-ai-hook.sh` is not installed by install.sh phase 2 (correctly not in POS_LIBS).

[DONE]

---

## Step 3: Gates + hygiene

### Gate results (final state)
- `bash -n scripts/lint-conventions.sh bin/pos-system-uninstall` → OK.
- `make gen` ×2 → idempotent (`gen-docs: write OK` both runs; second run produces the same diff, no drift).
- `make check` → `check-sync: OK` (exit 0).
- `time make lint` → `0 FAIL, 0 WARN (convention lint)`, **4.38 s** (second run 6.26 s; final measured 4.38 s). Baseline was **145.9 s** for the bare script and >120 s (timeout) for `make lint` → ~30x speedup. Rapid repeat runs no longer leave the shell spinning (no more per-line fork storms).
- **Gen output note:** `make gen` regenerated `DOC/AGENT_Context_Project.md` + `completions/pos.bash` from the **shared** working tree. The diff includes my expected `bin/pos-system-uninstall` row-count update (435→517 lines) **plus** the other parallel tracks' already-uncommitted changes (`bin/pos-ai-server`, `bin/pos-ai`, `bin/pos-system-backup`, communication listeners, etc.). No POS headers/dirs were touched by me; gen is byte-order deterministic (`LC_ALL=C`), CI's `git diff --exit-code` will see the whole tree's refresh.

### Hybrid conflict check (shared working tree)
Final `git status` shows many files modified by **parallel Builder tracks** (stab-ai, stab-security: `bin/pos-ai*`, `bin/pos-communication-*`, `bin/pos-network-checkport`, `bin/pos-share-smb-client`, `bin/pos-system-backup`, `lib/share-lib.sh`, `lib/ai-providers/llamacpp.sh`, `apps/install.sh`, `templates/app.sh`, `DOC/howto/*`, `DOC/APPS.md`, `AGENT_TODO.md`, `config/*.env`). These were NOT edited by me — my changed-file set is exactly:
1. `scripts/lint-conventions.sh` (rewritten; 213 changed lines vs HEAD)
2. `bin/pos-system-uninstall` (D-E + H-002/H-003; 150 changed lines vs HEAD)
3. `DOC/POS.md` — only the `pos system uninstall` row (all other rows in the file diff belong to other tracks)
4. `DOC/AGENT_Context_Project.md` + `completions/pos.bash` — gen output including, among others, my uninstall row count
5. `AgentsReport/builder/2026-09-06_stab-tooling.md` (this report)

No protected/brief-excluded file was touched by me; no out-of-scope change made.

### DOC/SCRIPTS.md + DOC/DEV.md
Not touched: no manifest was created (D-E rejected it), so the brief's "only if the manifest needs documenting" condition does not apply. No new documentation needed.

[DONE]

---

## Final status

- **Scope:** lint perf (Task 1) + D-E uninstall coverage (Task 2) + H-002/H-003 safe removal (Task 3) + surviving-artifacts docs (D-E 7). All implemented; no scope expansion.
- **Timings:** `make lint` 145.9 s → 4.38 s (~30x). Differential: output byte-identical to original.
- **Probes:** all pass (H-002/H-003 fixture removal, scan_tier1 with HOME override, remove-block replication, POS_LIBS==install.sh inventory).
- **Gates:** `bash -n` OK, `make gen` idempotent, `make check` OK, `make lint` `0 FAIL, 0 WARN`.
- **Deferred/risks:**
  1. The real-machine removal path (removing live `/usr/local/bin`, `/etc/systemd`, ScaleTail dirs) was NOT executed here — validated via fixture/sandbox probes only. A dry-run pass on a real install is doable via the tool's own scan display (`pos system uninstall` interactive scan shows Tier 1 entries before any removal).
  2. `lib/pos-ai-hook.sh` (13th lib file) is intentionally not in `POS_LIBS` because install.sh phase 2 doesn't install it; the uninstaller already removes `~/.local/bin/pos-ai-hook.sh` separately — no action.
  3. Other parallel tracks' edits are interleaved in the shared tree; my in-scope files are `scripts/lint-conventions.sh`, `bin/pos-system-uninstall`, DOC/POS.md (one row).
- **Recommended next agent:** Reviewer (independent adversarial review of the uninstall diff + lint rewrite), then Orchestrator to coordinate the shared-tree commit once the parallel tracks land.
