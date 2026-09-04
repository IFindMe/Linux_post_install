# Detective Report — ytsync menu errors (`cut` delimiter / `printf --`)

Date: 2026-08-23 · Mode: READ-ONLY investigation (no project files modified)
Scope: `bin/pos-media-ytsync` (+ one look at `install.sh` copy mechanism)

## TL;DR

Status: ROOT_CAUSE_ESTABLISHED (both errors reproduced verbatim; FACT).
- **Error #1 (`cut`)**: `cut -d'·'` at `bin/pos-media-ytsync:292` and `:301`. Delimiter `·` is U+00B7 = **2 bytes** in UTF-8; GNU `cut` is byte-oriented and rejects it ("the delimiter must be a single character"). Fired during first menu render via `menu_render:1045 → last_run_overall:301`.
- **Error #2 (`printf`)**: `bin/pos-media-ytsync:1053` — literal format `'--------------------------------------------\n'` starts with `-`; bash's printf builtin parses that as an invalid option. Same render, executes right after item `0) Exit`.
- Both stderr streams reach the terminal through the dispatcher tee pipe (`bin/pos:286`, `2>&1 | tee`) which preserves ordering ⇒ **both errors actually fired during the FIRST render**, positionally where the transcript shows them; "after exit" is perception (the `Choose:` prompt has no trailing newline).
- Sweep: exactly 3 `cut` uses in the file (1 benign), exactly 1 offending `printf`. No further instances.
- Harmless side effect worth noting: `|| true` masks the cut failure, so the `· last run …` suffix (line 1047) and the LAST SYNC column never populate.

---

## Step 1: Error #1 — `cut` multibyte delimiter

**Where:** `bin/pos-media-ytsync:292` and `:301`

```bash
292:  last="$(grep -F " · $name · " "$HIST_FILE" 2>/dev/null | tail -n 1 | cut -d'·' -f1 || true)"
301:  last="$(tail -n 1 "$HIST_FILE" | cut -d'·' -f1 || true)"
```

**Why multi-char:** `-d'·'` is U+00B7 MIDDLE DOT = `0xC2 0xB7` (2 bytes UTF-8). GNU coreutils `cut` is byte-oriented; any delimiter longer than one byte triggers exactly this error. Locale-independent (no multibyte support in cut).

**When it executes:** `interactive_menu:1126 → menu_render` prints banner (:1041–1043), then `:1045 lr="$(last_run_overall)"` → `last_run_overall:301` runs whenever `$HIST_FILE` (`~/.local/state/…/history.log`, defined :55) exists and is non-empty. Matches transcript position: error sits between banner and item `1)`.

**Trigger path:** menu render ⇒ `last_run_overall` (:298) ⇒ `tail | cut` (:301). Second instance `last_sync_of:292` fires from the list table builder (`:985`, menu option 3 / `pos media ytsync list`) — would produce the same error there.

**Masking:** `|| true` swallows rc=1, so `lr` is empty ⇒ suffix `" · last run …"` (:1047) silently never renders. Cosmetic degradation, no abort.

**Reproduction (harmless, stdin-only):**
```
$ printf '2026-08-22 10:00 · name · 2 new\n' | cut -d'·' -f1
cut: the delimiter must be a single character
Try 'cut --help' for more information.        # rc=1
```
Message matches user output byte-for-byte.

**Conclusion:** FACT.

[DONE]

## Step 2: Error #2 — `printf` format starting with `-`

**Where:** `bin/pos-media-ytsync:1053`, inside `menu_render`'s `{ … } >&2` block (:1039–1055):

```bash
1041:  printf '════════════════════════════════════════════\n'
...
1052:  printf '  0) Exit\n'
1053:  printf '--------------------------------------------\n'    # ← format starts with '-'
```

**Why it fails:** bash's printf builtin scans a leading `-` for options (only `-v var` is valid). A format whose first chars are `--` is reported as `printf: --: invalid option` + usage line, rc=2. Nothing prints; the separator line simply never renders.

**Trigger path/timing:** runs on every `menu_render` iteration immediately after item `0)` and before the `read -rp "Choose: "` prompt (`interactive_menu:1128`). Since `bin/pos:286` pipes the tool's `2>&1 | tee`, ordering is preserved ⇒ the error appeared in its positional slot (right under `0) Exit`) during the first render. It reads as "after exit" because the prompt has no trailing newline and the two error lines trail the visible interaction — STRONG INFERENCE for perception, FACT for execution point (code path + transcript position agree).

**Reproduction (harmless):**
```
$ bash -c "printf '--------------------------------------------\n'"
bash: line 1: printf: --: invalid option
printf: usage: printf [-v var] format [arguments]     # rc=2
```
Matches user output verbatim (path/line prefix differs only because bash reports the executing script).

[DONE]

## Step 3: Full-file sweep (both anti-patterns)

`cut` uses — complete set (grep `\bcut\b`):
| line | code | verdict |
|---|---|---|
| 190 | `… | cut -c1-60` | OK (`-c` char range) |
| 292 | `cut -d'·' -f1` | **BAD** (2-byte delim) |
| 301 | `cut -d'·' -f1` | **BAD** (2-byte delim) |

`printf` with format possibly starting with `-` — all 67 printf sites audited via grep: every format is a quoted literal starting with `%`, a letter, `[` (:1177), `═`, space, or `\r`; variable-format calls (`printf "$var"`) do not occur. Exactly **one** offender:
- `bin/pos-media-ytsync:1053` (**BAD**, dashed literal)

No further instances of either anti-pattern. Note: history writer lines :280/:286 legitimately use `·` as a data separator — not affected; only the `cut -d'·'` readers break.

[DONE]

## Step 4: install.sh — how `/usr/local/bin/pos-*` copies are produced

`install.sh` Phase 2 ("Installing wrapper scripts", :131–140):

```bash
136:  for f in bin/*; do
138:      run sudo install -m 755 "$f" /usr/local/bin/
```

Plain root-owned **copies** (`install -m 755`), not symlinks — consistent with the established fact (root-owned, identical size). Refresh post-fix: re-run `./install.sh` (phase-gated via `should_run 2 scripts`, :132) or manually `sudo install -m 755 bin/pos-media-ytsync /usr/local/bin/`. No other propagation mechanism exists (verified: no symlink/cp logic elsewhere in the Phase-2 block read).

[DONE]

## Step 5: Remedy recommendation (recommendation only, per conventions)

1. **:292 & :301** — drop `cut -d'·'`; take the field with parameter expansion (keeps the ` · `-separated history format from :280/:286 unchanged, no state migration):
   ```bash
   last="$(grep -F " · $name · " "$HIST_FILE" 2>/dev/null | tail -n 1)" ; last="${last%% ·*}"
   last="$(tail -n 1 "$HIST_FILE")"                                     ; last="${last%% ·*}"
   ```
   (Alternative: `awk -F' · '` which is locale-multibyte-safe — either satisfies the convention; expansion avoids one subprocess.)
2. **:1053** — make the format argument unambiguous, matching the file's own style:
   `printf '%s\n' '--------------------------------------------'`
   (equivalently `printf -- '---…\n'`; the `%s` form is what every sibling line already does.)
3. Post-change gates per AGENTS.md/DEV.md: `make gen` (header untouched ⇒ likely no-op), `make check`, `make lint`; then refresh the installed copy (Step 4). Regression probe: `HIST_FILE` present + `pos media ytsync` → menu must show `· last run <date>` suffix and the bottom separator, zero stderr noise.

[DONE]

---

## Handoff

Status: ROOT_CAUSE_ESTABLISHED
Symptom: two stderr errors around the `pos media ytsync` interactive menu (cut delimiter / printf `--`).
Expected: silent menu render incl. `· last run …` suffix + bottom separator.
Actual: both errors emitted; separator and last-run info missing.
Root cause: multibyte `cut -d'·'` (:292,:301) + dashed printf format (:1053). Classification: FACT (both reproduced verbatim).
Evidence: file:line above; repro transcripts; `bin/pos:286` ordering.
Alternatives eliminated: stale/differing installed copy (size-identical, given); locale-dependent collation (cut is byte-based, fails in any locale); delayed-execution theories (tee pipe preserves order).
Affected components: `bin/pos-media-ytsync` only; deployed copy `/usr/local/bin/pos-media-ytsync` inherits until refreshed via `install.sh` Phase 2.
Recommended next agent: Builder (fix list in Step 5; read-only constraints observed — no project files were modified).

REPORT_PATH: ./reportAgents/2026-08-23-detective-ytsync-menu-errors.md
