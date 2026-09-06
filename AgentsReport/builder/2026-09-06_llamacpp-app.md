# Builder Report — 2026-09-06 — llamacpp app installer + `ai` category + `pos ai server` hint wiring

## TL;DR
- **Status:** IMPLEMENTED — all steps `[DONE]`, all gates green
- **Scope:** new `apps/ai/llamacpp.sh` installer, `ai` category plumbing (CAT_NAMES, template comment, DOC/APPS.md), 3 error-hint lines in `bin/pos-ai-server`, 1 line in `DOC/POS.md`, 1 AGENT_TODO.md Done entry
- **Real asset naming VERIFIED via live API probe** (network available): `releases/latest` is the `v0.4.0` milestone with **no binary assets** (only `nightly-tag.txt`); the binaries live on nightly `bNNNNN` prereleases as `llama-<tag>-bin-ubuntu-x64.tar.gz` / `llama-<tag>-bin-ubuntu-arm64.tar.gz` (`.tar.gz`, **not** `.zip`), with a top-level dir `llama-<tag>/`
- **Key adaptations vs brief:** (1) fetch `/releases?per_page=10` + scan for the first release with a matching asset instead of `/releases/latest`; (2) extract with `tar xzf --strip-components=1` instead of `unzip` — the `.zip`/`unzip` assumption is obsolete (evidence: live API + archive listing); no `unzip` apt install (wrong mutation for tar.gz assets)
- **Files changed:** `apps/ai/llamacpp.sh` (new), `apps/install.sh` (CAT_NAMES), `templates/app.sh` (comment), `DOC/APPS.md`, `bin/pos-ai-server` (3 text lines), `DOC/POS.md` (1 line), `AGENT_TODO.md` (1 entry), `AgentsReport/builder/2026-09-06_llamacpp-app.md` (new report). `make gen` changed nothing.

## Step 1: Probe real llama.cpp release assets
- [x] Probe `api.github.com/repos/ggml-org/llama.cpp/releases/latest` + `/releases?per_page=10`, inspect archive layout
- [DONE]

## Step 2: Write `apps/ai/llamacpp.sh`
- [x] Installer with idempotent `install_llamacpp()` / `uninstall_llamacpp()` + uninstall case
- [x] Verify `bash -n`, idempotent no-op paths
- [DONE]

## Step 3: `ai` category plumbing
- [x] `apps/install.sh` CAT_NAMES `[ai]="AI / ML"`
- [x] `templates/app.sh` categories comment adds `ai`
- [x] `DOC/APPS.md`: categories line, count 15→16, catalog row
- [DONE]

## Step 4: Point `pos ai server` at the installer
- [x] `bin/pos-ai-server` lines ~397, ~563, ~256 → scrcpy-style hint keeping the GitHub URL
- [x] `DOC/POS.md` ~line 125 adds "(install via `bash apps/install.sh llamacpp`)"
- [DONE]

## Step 5: AGENT_TODO.md Done entry
- [x] Insert 2026-09-06 entry before the current first Done entry
- [DONE]

## Step 6: Verification
- [x] `bash -n apps/ai/llamacpp.sh apps/install.sh bin/pos-ai-server` → all OK
- [x] `make gen && make gen` → idempotent, **no gen output changed** (apps installers aren't scanned by gen)
- [x] `make check` → `check-sync: OK`, rc 0
- [x] `make lint` → `0 FAIL, 0 WARN`, rc 0
- [x] `bash apps/install.sh --uninstall llamacpp` → resolves app, "llama.cpp not installed", rc 0, no network
- [x] `bash apps/ai/llamacpp.sh uninstall` → rc 0 (no llama-server on PATH)
- [x] Stub-guard: `bash apps/ai/llamacpp.sh` with a fake `llama-server` on PATH → "llama.cpp already installed", rc 0 (no network/sudo)
- [x] Dry-run install + uninstall with a real (stubbed) binary → parse + spawn expansion + symlink-loop body all verified
- [DONE]