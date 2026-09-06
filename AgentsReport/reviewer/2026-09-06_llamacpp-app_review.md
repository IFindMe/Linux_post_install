# Reviewer Report — 2026-09-06 — llamacpp optional-app installer + `ai` category

## TL;DR

- **Status:** REQUEST_CHANGES — 2 REQUIRED, 3 SUGGESTED, 3 NOTE. All functional/structure claims verified; two fixable defects block acceptance.
- **REQUIRED-1:** `apps/ai/llamacpp.sh` is **not executable** (mode 100644, untracked); every tracked `apps/*` file is 100755. Fix: `chmod +x` before `git add`.
- **REQUIRED-2:** `DOC/APPS.md:3` says "16 optional desktop application installers"; the catalog table (rows 73–90) and the filesystem both hold **18** app installers (17 pre-existing tracked + the new one). The 15→16 change propagated a stale count (correct: 18).
- **SUGGESTED:** (S1) failures inside the embedded `bash -c` install block are masked as success (no `set -e` in child — same class pattern as `scrcpy.sh`, so fix across the class); (S2) `DOC/DEV.md:292` categories list misses `ai`; (S3) unguarded `python3` dependency yields a misleading error when absent.
- Every other item in the brief verified [PASS]: shebang/strict-mode/source path, idempotence guard before network/sudo, `/releases?per_page=10` scanning, `.tar.gz` suffix matcher, `--strip-components=1`, symlink-loop + readlink-target uninstall (no blanket `rm llama*`), temp cleanup on success + matcher-failure path, `case` dispatch with `uninstall`, CAT_NAMES `[ai]`, template comment, exactly 3 text lines in `bin/pos-ai-server` (no logic change), 1-line `DOC/POS.md` hint (accurate — `install.sh --apps/--full` verified), AGENT_TODO Done entry, scope/hygiene clean.
- **Unverified (read-only boundary):** live GitHub API probe results, and `make gen/check/lint` runs (I did not re-run them); static evidence is consistent with the Builder's claims.

## Step 1: `apps/ai/llamacpp.sh` — structure, idempotence, release discovery, cleanup, dispatch

- [x] Shebang `#!/usr/bin/env bash` (line 1), `set -euo pipefail` (line 2), sources `lib/common.sh` via `$(dirname "$0")/../../lib/common.sh` (line 3) — correct depth for `apps/ai/`.
- [x] `install_llamacpp()` idempotence guard **first**: `command -v llama-server &>/dev/null && { log "llama.cpp already installed"; return 0; }` (line 16) — before any network (lines 25–27) and before any sudo (lines 49–55).
- [x] Arch mapping `x86_64→x64`, `aarch64→arm64`, unsupported arch errors (lines 19–23).
- [x] Discovery: fetches `/releases?per_page=10` (line 13); python3 matcher scans `r['assets']` for `a['name'].endswith('-bin-ubuntu-$arch.tar.gz')` (lines 30–40). `endswith` on the exact suffix ⇒ no false positives on `.sha256`/`.txt` assets. No-match path removes the temp JSON and `err`s with a clear message + GitHub URL (lines 41–44).
- [x] `--strip-components=1` extraction (line 51) — consistent with the claimed top-level-dir archive layout (Builder live probe; cannot re-probe read-only → see unverified).
- [x] Symlink loop links every `llama*` binary from the install dir to `/usr/local/bin`, guarded by `[ -f ] && [ -x ]` (lines 52–55).
- [x] Temp cleanup on success (line 56, both files) and on the matcher no-match path (line 42). No `trap`; remaining early-failure edge → NOTE-3.
- [x] `uninstall_llamacpp()`: idempotent guard (line 63), removes `/usr/local/lib/llama.cpp-*` (line 65), and removes **only** symlinks whose `readlink` target matches `/usr/local/lib/llama.cpp-*` (lines 69–77) — **no** blanket `rm -f /usr/local/bin/llama*`; unrelated `/usr/local/bin/llama*` files are left alone. Extra edge → NOTE-2.
- [x] `case "${1:-}"` dispatch with `uninstall` arm (lines 82–85). Matches lint rule `lint-conventions.sh:192-204` (function name + `uninstall)` dispatch present).
- [x] Dry-run: every mutation is inside `spawn` (common.sh `spawn` logs and returns 0 under `DRY_RUN=1`, lines 79–82) — no mutation under `DRY_RUN=1`. Nuance → NOTE-1.

[PASS]

## Step 2: `apps/install.sh` — CAT_NAMES + discovery

- [x] `CAT_NAMES` gains `[ai]="AI / ML"` (line 45); alphabetical position consistent.
- [x] Discovery loop (lines 59–78) is directory-driven; no per-category registration — `apps/ai/` is picked up automatically; `bash apps/install.sh llamacpp` resolves via `find_app_category`; `--uninstall llamacpp` path works the same.

[PASS]

## Step 3: `templates/app.sh` — category comment

- [x] Comment now reads "Categories: ai, browsers, development, media, networking, remote-access, system, utilities." (line 8) — `ai` added, nothing else drifted (single-hunk diff).

[PASS]

## Step 4: `bin/pos-ai-server` — exactly 3 text lines

- [x] `git diff bin/pos-ai-server`: 3 hunks, +3/-3, string-only:
  - help "Requires:" line (now line 256),
  - `cmd_start` `err` (line 397),
  - `cmd_status` `err` (line 563).
- [x] All three name the installer (`apps/ai/llamacpp.sh`), give the invocation (`bash apps/install.sh llamacpp`, `--apps`/`--full`), and keep the GitHub URL `https://github.com/ggerganov/llama.cpp`.
- [x] `--apps`/`--full` claim verified against root `install.sh:57-58,78-79` and `DOC/APPS.md:26` — accurate.
- [x] Phrasing mirrors the scrcpy model (`bin/pos-communication-scrcpy:11`: "… not found — install … with the app installer: 'apps/media/scrcpy.sh' … see 'pos help …'"). No logic changed — diff is text-only in message strings.

[PASS]

## Step 5: `DOC/APPS.md` — count, categories, row

- [x] Categories line now includes `ai` (line 37); llama.cpp catalog row added (line 73) with method "GitHub release → `/usr/local/lib/llama.cpp-<tag>` + `/usr/local/bin` symlinks" and category `ai` — matches the installer (GitHub release `.tar.gz` → `/usr/local/lib`, cat `ai`).
- [FAIL] Count line (line 3): says "16 optional desktop application installers". Actual = **18**. Evidence: catalog rows 73–90 = 18 rows; `apps/**/*.sh` glob = 19 files incl. `apps/install.sh` (18 app installers); `git ls-files 'apps/*/*.sh'` = 17 tracked + 1 new. The pre-existing "15" was already stale (17 real installers at HEAD); the change kept the arithmetic wrong (correct value 18). REQUIRED-2.

[FAIL]

## Step 6: `DOC/POS.md` — single-line hint

- [x] Diff shows exactly one line changed (line 125, `pos ai server` Flags line): appends "(install via `bash apps/install.sh llamacpp`)" to the existing sentence. Accurate.

[PASS]

## Step 7: `AGENT_TODO.md` — Done entry

- [x] New entry dated **2026-09-06** inserted at the top of `## Done` (line 45), before the prior 2026-09-06 entries — accurate, no duplication, matches the implementation (including the "15→16" claim which carries the same count defect as the DOC — noted in R2).

[PASS]

## Step 8: Hygiene + executable mode

- [x] No debugging artifacts, no hardcoded machine paths, no secrets, no committed temp files. `apps/ai/` contains only `llamacpp.sh`.
- [FAIL] Executable mode: **existing apps are tracked 100755** (`git ls-files -s apps` → every `apps/*` including `apps/install.sh` is `100755`; `templates/app.sh` also 100755). The new `apps/ai/llamacpp.sh` is **100644** (`git diff --no-index --summary /dev/null apps/ai/llamacpp.sh` → "create mode 100644"). The repo convention stores app exec bits; the new file breaks that uniformity and `git add` would persist 100644. Note: gates won't catch it (`check-sync.sh` exec loop covers only `bin/pos*`; `lint-conventions.sh` `executable_files()` covers `bin/pos-*` + `entertainment/*.sh` only). REQUIRED-1.

[FAIL]

## Step 9: Scope

- [x] `git status --porcelain`: modified = AGENT_TODO.md, DOC/APPS.md, DOC/POS.md, apps/install.sh, bin/pos-ai-server, templates/app.sh; untracked = AgentsReport/builder/2026-09-06_llamacpp-app.md, apps/ai/. `git diff --stat` = 6 files, +11/-7 — consistent with the claimed change set.
- [x] No `lib/`, `config/`, `install.sh`/`preinstall.sh`/`postinstall.sh`, `completions/`, or GEN: block changes. Builder's "make gen changed nothing" is consistent with the absense of generated-block diffs.

[PASS]

## Findings

| # | Severity | File:line | Finding | Evidence |
|---|----------|-----------|---------|----------|
| R1 | REQUIRED | `apps/ai/llamacpp.sh` (untracked, whole file) | New app installer is not executable (100644); all tracked app installers/template are 100755. `git add` will persist 100644 | `git diff --no-index --summary /dev/null apps/ai/llamacpp.sh` → "create mode 100644"; `git ls-files -s apps` → all 100755; `check-sync.sh:22-24` + `lint-conventions.sh:100-105` only enforce exec bits for `bin/pos*`/`entertainment/*.sh`, so gates are blind to this |
| R2 | REQUIRED | `DOC/APPS.md:3` | Count says 16; actual installer count is 18 (17 pre-existing tracked + llamacpp). Pre-existing "15" was already stale; change should have gone to 18 | Catalog table rows 73–90 (18 rows, read of DOC/APPS.md); glob `apps/**/*.sh` → 19 files incl. `apps/install.sh` (18 installers); `git ls-files 'apps/*/*.sh'` = 17 |
| S1 | SUGGESTED | `apps/ai/llamacpp.sh:46-57` | Embedded `bash -c` install block has no `set -e`; a failed `curl -fsSL`/`tar` continues to `rm` (rc 0) → `spawn` prints OK and line 59 logs "installed" on a failed install. Same class pattern as `apps/media/scrcpy.sh:26-34` — recommend adding `set -e` inside the child (or `&&`-chaining), ideally fixed across both installers | read of llamacpp.sh:46-57 vs scrcpy.sh:26-34; common.sh:90-115 (`spawn` runs `bash -c` child, no errexit inheritance) |
| S2 | SUGGESTED | `DOC/DEV.md:292` | "Adding an Optional App" categories list omits the new `ai` category (updated in `templates/app.sh:8` and `DOC/APPS.md:37` but not DEV.md) | read of DEV.md:292; diff of templates/app.sh + DOC/APPS.md |
| S3 | SUGGESTED | `apps/ai/llamacpp.sh:30-43` | `python3` is an undeclared dependency; if absent, `python3 -c` fails and the script prints the misleading "No llama.cpp Ubuntu x64 binary release found" error. A `command -v python3` guard (or using the `curl`+`jq` already required by `pos ai server`) would give a clearer error. Same pattern as scrcpy.sh:15 | llamacpp.sh:30-44; no deps guard for python3 anywhere in file |
| N1 | NOTE | `apps/ai/llamacpp.sh:30-44` + `lib/common.sh:79-82` | Under `DRY_RUN=1` no mutation occurs (spawn no-ops), but the python3 matcher runs outside spawn and hard-errors ("No … release found") because the probe file was never fetched — dry-run does not print a would-be trace. Mirrors scrcpy's dry-run behavior; no defect in mutation-safety | common.sh:79-82 (spawn DRY_RUN branch), llamacpp.sh:30-44 |
| N2 | NOTE | `apps/ai/llamacpp.sh:63` | Uninstall guard keys on `llama-server` on PATH; a partial install with no symlink leaves `/usr/local/lib/llama.cpp-*` behind on uninstall. Reinstall is safe (line 49 removes the dir first) — edge case only | llamacpp.sh:63, 49 |
| N3 | NOTE | `apps/ai/llamacpp.sh:25-27` + `lib/common.sh:114` | First-spawn (release JSON fetch) failure exits via `spawn`'s `exit "$rc"` before the JSON cleanup runs (line 42/56); a mid-transfer abort can leave a partial `/tmp/llamacpp-releases.json`. No `trap` for the process. Minor | common.sh:114, llamacpp.sh:25-27 |

## Verification verified

- All structure/idempotence/dispatch claims for `apps/ai/llamacpp.sh` (Step 1 list) — read-only inspection.
- `apps/install.sh` CAT_NAMES + auto-discovery; `templates/app.sh` one-comment-line diff; `bin/pos-ai-server` exactly 3 text lines (256/397/563), no logic change, GitHub URL kept, `--apps`/`--full` accurate (root `install.sh:57-58,78-79`); `DOC/POS.md` one-line hint; AGENT_TODO entry correct and non-duplicated; scope = exactly the claimed file set; hygiene clean; uninstall symlink-scoped removal (no blanket `rm llama*`); temp cleanup on success + matcher-failure paths; lint apps-class rules satisfied (`lint-conventions.sh:192-204`).

## Verification unverified

- Live GitHub API probe (nightly `bNNNNN` asset naming, `.tar.gz` not `.zip`, top-level dir layout, `/releases/latest` having no binaries) — external network probe; not re-run within read-only boundary. Static construction (per_page=10 scan, endswith matcher, strip-components=1) is consistent with the Builder's claimed evidence.
- `make gen` idempotence, `make check`, `make lint` runs — not re-run (do-not-run-make instruction); Builder-reported outputs are consistent with the script rules I inspected (gen scans only `bin/pos-*` `# POS:` headers; none changed).
- Runtime behavior of DRY_RUN and failure paths — analyzed statically only.

## Scope compliance

- In-scope confirmed: new `apps/ai/llamacpp.sh`; `apps/install.sh` line; `templates/app.sh` line; `DOC/APPS.md` 3-line edit; `bin/pos-ai-server` 3-line text edit; `DOC/POS.md` 1-line edit; `AGENT_TODO.md` 1 entry; builder report.
- Out-of-scope found: none. No lib/config/core-installer/generated-block changes.

## Remaining uncertainty

- Whether `chmod +x` is applied before commit (R1) and whether the count is corrected to 18 (R2).
- Whether the failure-masking (S1) should be addressed in this change or deferred as a class-level fix (scrcpy shares it). Not a blocker; owner decision.

## Recommended next agent

**Builder**

## Reason

Two REQUIRED findings within the approved scope of this change: (1) `chmod +x apps/ai/llamacpp.sh` before `git add` (100755 uniformity with all tracked apps); (2) correct `DOC/APPS.md:3` count from 16 → 18 (and, if touched, the AGENT_TODO wording). Both are small, understood fixes — no design/architecture input needed. After fixing, re-run `bash -n`, `make check`, `make lint`.

## Changes made by Reviewer

none