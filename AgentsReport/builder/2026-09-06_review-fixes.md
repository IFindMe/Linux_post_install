# Builder Report — POS AI review fixes (F1–F6)

Date: 2026-09-06
Builder: big-pickle

## TL;DR

- Status: IMPLEMENTED
- Fixes F1–F6 from `AgentsReport/reviewer/2026-09-06_pos_ai_full_review.md` implemented in `bin/pos-ai-hf`, `bin/pos-ai-server`, `DOC/POS.md` (hf + server detail), generated docs via `make gen`.
- Scope: exactly the approved fixes; no changes to `bin/pos-ai`, `bin/pos-ai-llamacpp`, `bin/pos`, README.md, AGENT_TODO.md, lib/ (AGENT_TODO.md not updated on purpose — out of scope, has pre-existing worktree edits).
- Verification: `bash -n` clean; `make gen` idempotent (3rd run md5-identical); `make check` → check-sync: OK; `make lint` → `0 FAIL, 0 WARN`; targeted probe matrix below (all passed).
- Deviation from reviewer wording: destroy-confirmation for `cache clear` reads `/dev/tty` (same pattern as `pos-ai-server pick_model`) instead of sourcing `lib/common.sh confirm()` — `pos-ai-hf` is NOT in `bin/pos` `INTERACTIVE_CMDS` and `bin/pos` is off-limits, so a plain stdin `read`/`confirm` would hang-or-trip the `uses_stdin` lint rule. Fail-closed default `n`, EOF/invalid denies (verified via `setsid`/pty probes).

## Step 1: F1 — include/exclude glob filtering (pos-ai-hf)
[DONE]

- Removed the `--include/--exclude` + `--gguf` erroring pre-check (`bin/pos-ai-hf` cmd_download) — patterns now compose, not conflict.
- Removed the old jq `match()` regex branch (regex semantics despite "supports glob" docs) from the `elif` chain; single composition point after gguf/filename filter, order: gguf/filename → include → exclude.
- New `hf_apply_patterns()` (`bin/pos-ai-hf:422-447`): bash `case` glob semantics, always yields a JSON array (`[]` when no match) preserving `{"rfilename","size"}` shape.
- Added error path `No files match include/exclude patterns in <repo> (branch: <branch>)` (rc 1) when patterns filter everything out.

Probes (fake curl serving canned repo):
- `--include "model.gguf"` (single file, sequential): rc 0, only model.gguf fetched, `.hf-meta` files array is a JSON array of 1.
- `--include "*.gguf"` (parallel): rc 0, model.gguf + Q8_0/model-q8.gguf fetched, meta files array length 2.
- `--include "*.bin"` → `ERROR: No files match include/exclude patterns in org/model (branch: main)`, rc 1.
- `--gguf --include "*.gguf"` composes: rc 0, same 2 gguf files.
- exclude-only `--exclude "*.safetensors"` → rc 0, 3 files remain.

## Step 2: F2 — systemd unit single-line ExecStart (pos-ai-server)
[DONE]

- `cmd_start` now builds ONE `exec_cmd` string with binary + model + all resolved flags (`bin/pos-ai-server:431-477`); unit written via heredoc with `ExecStart=$exec_cmd` on a single line (`bin/pos-ai-server:488-504`) — no more multi-line `echo >>` appends that systemd rejects.
- Dry-run prints the same `$exec_cmd` it would write into the unit (previously the dry-run line missed all optional flags).
- Real (non-dry) start: unit written, then `systemctl --user daemon-reload` (container has no systemd user session → fails after write, expected; unit itself verified).

Probes:
- dry-run with all flags: single ExecStart line containing every flag, rc 0.
- real run wrote the unit; `systemd-analyze verify <unit>` → **RC=0, no warnings** (executable path resolves, `EnvironmentFile=-%h/...` accepted).

## Step 3: F3 — --branch/--revision alias (pos-ai-hf)
[DONE]

- Removed the separate `BRANCH` variable; `--branch` and `--revision` both set `REVISION` (`bin/pos-ai-hf:127-148`), last flag wins (usage documents the alias).
- `hf_resolve_branch` unchanged: explicit revision or API default branch, falls back `main`.

Probes:
- `--branch main`, `--revision v1.0`, and `--revision v2.0 --branch main` (later wins → main) all rc 0.

## Step 4: F4 — parallel download failure handling (pos-ai-hf)
[DONE]

- Rewrote the parallel path (`bin/pos-ai-hf:638-692`): per-pid `wait` with `! wait` failure capture, parallel `job_pids`/`job_names` arrays, `failed_files` collection, per-job log files under `mktemp -d` temp dir (no interleaved output), individual job reaped as batch limit reached AND full drain at the end, per-file `Failed to download <file>` warns after the batch (same style as sequential path), `trap 'rm -rf "$temp_dir"' EXIT` + explicit `rm -rf` + `trap - EXIT` so temp dirs never survive.
- Removed dead helpers `err_with_context`, `hf_download_file`, `run_parallel_download`.

Probes (poisoned fake curl failing only `Q8_0/model-q8.gguf`):
- 2-file parallel download: 1 success + 1 failure — batch rc 0, `[!] Failed to download Q8_0/model-q8.gguf` reported at end, successful file on disk, **zero stray `/tmp/tmp.*` dirs** after exit.
- Known limit (pre-existing, noted not in review scope): summary line counts *attempted* files (`2 files, 40 B`) even when one fails — same optimistic counting as the sequential path.

## Step 5: F5 — version/feature validation guard (pos-ai-server)
[DONE]

- `detect_llama_version <binary>` guarded: missing binary or unreadable `--version` → `unknown`, never errexit (previously called `llama-server --version` directly → crash when binary absent).
- Replaced no-op `validate_server_features` with `validate_requested_flags <binary> <version> <flag...>`: greps the binary's actual `--help` output for each **explicitly requested** flag token; first unsupported one errors `installed llama.cpp <version> does not expose <flag> — remove it or upgrade llama.cpp`; unreadable `--help` → warn once and proceed (no hard-fail). Alias-mapped requests dedupe (`--gpu`/`--gpu-layers`/`--n-gpu-layers` all validate `--n-gpu-layers`).
- Parse loop records canonical request tokens in `REQUESTED_FLAGS` (defaults/config-derived values NOT validated — only what the user typed).
- `cmd_status`: binary guard with actionable error before version probe; version printed via the *resolved* binary path.

Probes (fake llama-server v0.1.0 whose `--help` omits `--kv-cache` and `--slots`):
- `start --model fake.gguf --slots 4` → `ERROR: installed llama.cpp 0.1.0 does not expose --slots — remove it or upgrade llama.cpp`, rc 1 (also proves validation runs before dry-run return).
- `status` without llama-server on PATH → `ERROR: llama-server not found — install llama.cpp (...)`, rc 1, no crash.
- `status` with shim → `service: stopped`, `version: 0.1.0`, rc 0.

## Step 6: F6 — hf cache real implementation (pos-ai-hf)
[DONE]

- `cmd_cache {status|clear}` with default `status` (`bin/pos-ai-hf:887-894`); bad action → usage error. Top-level indent of `cmd_cache()` fixed (reviewer style nit).
- `cmd_cache_status`: cache dir + model count + total on-disk size (excludes `.hf-meta` — same discovery as `list`/`remove`); empty dir → `Models: 0 (nothing downloaded yet)`, rc 0.
- `cmd_cache_clear`: lists models to be removed, then confirm `Remove all downloaded models? [y/N]: ` read from `/dev/tty` (see TL;DR deviation), fail-closed — anything but `y`/`Y` (including EOF) → `Aborted — nothing removed`, rc 0; on `y` removes all model dirs and prints freed size.

Probes:
- `cache status` empty cache: rc 0, `Models: 0 (nothing downloaded yet)`.
- `cache status` 2 fake models: `Models: 2 / Size: 5 B`, rc 0.
- `cache clear` under `setsid` (EOF, no tty): prompt shown, `Aborted — nothing removed`, rc 0, **models intact**; clean stderr (the `/dev/tty` open error is suppressed: `read -r yn 2>/dev/null </dev/tty` — redirection order matters).
- `cache clear` via pty (`script -qec` feeding `y`): list shown, prompt, `Cache cleared (freed 9 B)`, rc 0, model dirs **gone**.

## Step 7: Docs (DOC/POS.md) + make gen/check/lint
[DONE]

- `DOC/POS.md`: hf download row updated (`--revision` alias, include/exclude glob composition order, example), new `pos ai hf cache [status|clear]` row, server flags+validation detail extended.
- `make gen` after touching bin files: tree/dispatch/filetable/completions regenerated (also repairs the pre-existing stale `_pos_flags` for ai-hf/ai-server and picks up the maintainer's untracked `pos-ai-llamacpp` forwarder).
- Gates (final state): `bash -n bin/pos-ai-hf bin/pos-ai-server` → OK; `make gen` twice after edits → second run byte-identical (idempotent); `make check` → check-sync: OK; `make lint` → `0 FAIL, 0 WARN`.

## Files changed (this task)

- `bin/pos-ai-hf` — F1/F3/F4/F6 (+ dead code removal, style fix)
- `bin/pos-ai-server` — F2/F5
- `DOC/POS.md` — hf download row, cache row, server flags/validation
- `DOC/AGENT_Context_Project.md`, `completions/pos.bash` — generated by `make gen` (auto-rows, flags, subcmd completion)

Pre-existing worktree drift NOT touched (confirmed untouched in final diff): `AGENT_TODO.md`, `DOC/howto/ai.md`, `bin/pos`, `bin/pos-ai`, untracked `bin/pos-ai-llamacpp`, `AUDIT.md` etc.

## Remaining risks / deferrals

- `systemctl --user daemon-reload`/`enable --now` cannot complete inside this container (no systemd user session) — real start verified only up to unit write + `systemd-analyze verify` RC 0; the systemctl calls themselves are otherwise standard.
- Summary line after a partially failed parallel download counts attempted files, not successes (pre-existing, matches sequential path; not flagged in review).
- `validate_requested_flags` warns-and-proceeds if `--help` cannot be read (deliberate: silent-basic-defaults behavior lost, actionable warning kept).