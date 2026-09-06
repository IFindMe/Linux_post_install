# Detective Report: `pos ai server start` — llama.cpp Post-Install Breakage

**Date:** 2026-09-06
**Investigator:** Detective (read-only)
**Symptom (user paste):** After `bash apps/install.sh llamacpp` installed llama.cpp b10822, `pos ai server start Qwen-Qwen3-1.7B-GGUF` fails: version "unknown", default flags rejected, model-not-found, and dbus error at the end.
**Severity:** High — complete server-start failure after a clean install; the generated unit is silently corrupted.

## TL;DR

| Hyp | Verdict | One-line evidence |
|-----|---------|-------------------|
| H1 | **CONFIRMED** (wrong mechanism) | `llama-server --version` prints to **stderr** (`common/build-info.h:13` default `FILE* = stderr`); `detect_llama_version` discards it with `2>/dev/null` → always "unknown" |
| H2 | **REFUTED as user's cause; latent defect stands** | Archive ships `llama-server`; installer symlinks it (verified); but bare `server` fallback picks unrelated binaries when llama-server is missing (fixture-proven) |
| H3 | **REFUTED as stated; REAL bug found** | Word-boundary regex MATCHES all 5 flags in real help; the actual failure is `printf|grep -q` + `set -o pipefail` **SIGPIPE race** (pipeline rc=141) — flaky per-run |
| H4 | **CONFIRMED** | `resolve_model` accepts only files; a dir containing one `.gguf` under `HF_DOWNLOAD_DIR` fails with exact user error (reproduced) |
| H5 | **CONFIRMED** | Unit written (`:584-602`) BEFORE `systemctl --user daemon-reload` (`:605`); no bus pre-check; SSH without `XDG_RUNTIME_DIR` → exact error, `set -e` aborts, linger hint never runs; orphaned unit remains |
| H6 | **CONFIRMED** | llama.cpp default port **8080** (`common/common.h:620`; `--help` default), tool/adapter default **8088**; real orphaned unit on this machine omits `--port` |

**Root cause chain (one paragraph):** `detect_llama_version` (bin/pos-ai-server:71) always returns "unknown" because llama.cpp's `--version` writes to stderr and the tool discards stderr (`2>/dev/null`). Independently, `validate_default_flags`/`validate_requested_flags` (lines 101, 145) run `printf '%s' "$help_text" | grep -qE ...` under `set -o pipefail`; `grep -q` exits at the first match (flags are at byte offsets 320–39,741 of a 59,000-byte help), the bash-builtin `printf` then hits EPIPE, and pipefail promotes the SIGPIPE (rc=141) — so the `if` is false even though the flag IS in the help. Which flags "fail" each run is a scheduling race (empirically 0–4 flags rejected per run). Separately, `resolve_model` (lines 229-259) rejects the user's directory argument `Qwen-Qwen3-1.7B-GGUF` (HF downloader produces `$HF_DOWNLOAD_DIR/<repo-slug>/<file>.gguf`, not a flat file), and the unit write precedes an unguarded `systemctl --user daemon-reload` that fails under SSH with no `XDG_RUNTIME_DIR`, aborting via `set -e` before the linger hint and leaving an orphaned unit whose ExecStart may already have lost `--port` (real example on this machine: `ExecStart=... --host 127.0.0.1` only), guaranteeing a port mismatch against the adapter's 8088 health/API probes.

---

## Step 1: H1 — Version detection "unknown"

### Hypothesis (as briefed)
`detect_llama_version` (`bin/pos-ai-server:65-74`) greps `[0-9]+\.[0-9]+\.[0-9]+` (semver) from `--version`; llama.cpp uses build numbers `bNNNNN`, never X.Y.Z.

### Actual llama.cpp `--version` output (b10822)
Downloaded and executed the real release binary (`llama-b10822-bin-ubuntu-x64.tar.gz`, `https://github.com/ggml-org/llama.cpp/releases/tag/b10822`):

```
$ ./llama-server --version
version: 0.4.0-dev (build 10822, commit c457e3bf7)
built with GNU 11.4.0 for Linux x86_64
```

**The format DOES contain X.Y.Z (`0.4.0`).** The briefed premise is factually wrong for current builds. The regex would match `0.4.0`.

### The REAL mechanism — output goes to stderr
```
$ ./llama-server --version 1>/dev/null        # output STILL appears
$ ./llama-server --version 2>/dev/null        # NOTHING appears
```
`od -c` confirms the bytes are written to **stderr**. Source citation: `common/build-info.h:13`
```cpp
void llama_print_build_info(const char *, FILE * = stderr);
```
called from `common/arg.cpp:1456` (`llama_print_build_info(llama_version()); exit(0);`) — default stream stderr.

`detect_llama_version` (`bin/pos-ai-server:71`):
```bash
version="$("$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
```
`2>/dev/null` discards the ONLY output → grep gets empty input → `version=` empty → `"unknown"`. Proven against real binary: with `2>/dev/null` captured nothing; with `2>&1` captured `0.4.0`.

Note: even with `2>&1`, the regex is brittle against older builds that print only `build 10822` (no semver) — a secondary hazard, not the current blocker.

```
Hypothesis: version always "unknown" because regex can't match
Why plausible: builds are tag "b10822"
Evidence supporting: user sees "unknown" in all messages
Evidence against: actual output has X.Y.Z ("0.4.0"); the regex DOES match
Test needed: run detect_llama_version verbatim against real binary
Result: empty capture (stderr discarded) → "unknown"
Conclusion: CONFIRMED outcome, wrong mechanism — stderr discard, not regex format
```

**[DONE]**

## Step 2: H2 — Wrong binary found

### (a) What the release archive ships
`llama-b10822-bin-ubuntu-x64.tar.gz` (downloaded and listed) contains `llama-server` (among ~30 `llama*` tools + `.so` libs). **No bare `server` binary.**

### (b) Installer symlink behavior
`apps/ai/llamacpp.sh:52-55`:
```bash
for bin in \$install_dir/llama*; do
    [ -f "\$bin" ] && [ -x "\$bin" ] || continue
    sudo ln -sf "\$bin" /usr/local/bin/\$(basename "\$bin")
done
```
Since the archive ships `llama-server`, the glob `llama*` matches it → `/usr/local/bin/llama-server` IS created. Verified on the target machine (real install): `/usr/local/bin/llama-server -> /usr/local/lib/llama.cpp-b10822/llama-server`, and `llama-server --help` (PATH lookup) returns the full 732-line/59,000-byte help. RUNPATH `$ORIGIN` (`readelf -d`: `Library runpath: [$ORIGIN]`) makes the shared libs resolve through the symlink. **The install is not broken this way — H2 is not the user's cause.**

### (c) The bare `server` fallback is a genuine latent defect (fixture)
`find_llamacpp` (`bin/pos-ai-server:56`) candidates: `llama-server`, `llama.cpp/server`, `server`, `llama-server-cuda`. Fixture: PATH containing ONLY an unrelated `/tmp/h2fixture/bin2/server` (no llama-server):

```
find_llamacpp -> 'server'  (command -v -> '/tmp/h2fixture/bin2/server')
detect_llama_version -> (depends on the unrelated binary)
validate_default_flags:
  --port: UNSUPPORTED (warn + omit)
  --host: UNSUPPORTED (warn + omit)
  --n-gpu-layers: UNSUPPORTED (warn + omit)
  --ctx-size: UNSUPPORTED (warn + omit)
  --threads: UNSUPPORTED (warn + omit)
```
i.e., a wrong-binary scenario produces the same family of user-visible messages — but **not** what this user hit (their install is correct and `llama-server` resolves first because candidate order checks `llama-server` before `server`).

```
Conclusion: REFUTED as user's root cause; PARTIALLY-CONFIRMED as latent defect (bare `server` fallback)
```

**[DONE]**

## Step 3: H3 — Help-format regex vs real llama-server --help — **actual root cause of the flag rejections**

### The regex matches real help
Real `llama-server --help` (732 lines) contains (`grep -n` on real output):
```
7:   -t,    --threads N
25:  -c,    --ctx-size N
140: -ngl,  --gpu-layers, --n-gpu-layers N
503: --host HOST
506: --port PORT
```
Word-boundary regex `(^|[[:space:]])${flag}([[:space:]]|=|$)` matches all five when tested WITHOUT pipefail (verified repeatedly). H3 as stated ("format mismatch misses real flags") is **REFUTED**.

### The real failure: `printf | grep -q` + `set -o pipefail` → SIGPIPE race
`bin/pos-ai-server` line 2: `set -euo pipefail`. Lines 101/145:
```bash
if printf '%s' "$help_text" | grep -qE -- "(^|[[:space:]])${flag}([[:space:]]|=|$)"; then
```
`grep -q` exits as soon as it finds a match (closing the pipe's read end). The produced help_text is 59,000 bytes; the pipe buffer is 64 KB. Flags appear at byte offsets:
- `--threads` 320, `--ctx-size` 1892, `--n-gpu-layers` 10992 (early)
- `--host` 39499, `--port` 39741 (late)

For early flags, grep matches and exits after reading ≤ a few KB; the bash-builtin `printf` still has ~57 KB to write → EPIPE → under `pipefail` the pipeline returns **141 (128+13=SIGPIPE)** → the `if` is false even though grep found the flag. For late flags, printf usually completes writing into the 64 KB buffer before grep exits → rc=0. It's a **race**, so outcomes vary run to run.

**Isolated proof** (same capture, same regex, pipefail on):
```
++ printf '%s' "$help_text" | grep -qE -- '(^|[[:space:]])--ctx-size([[:space:]]|=|$)'
pipeline rc=141   (grep -q DID match; printf died of SIGPIPE)
```
30-run trial: MATCH/NOMATCH alternated ~50/50 for `--ctx-size`.

**Live `pos-ai-server` flakiness (10 runs, real binary, identical inputs):**
```
run 1:  --ctx-size --threads
run 2:  --ctx-size --threads
run 3:  --threads
run 4:  --threads
run 5:  --n-gpu-layers --ctx-size --threads
run 6:  --ctx-size
run 7:  --port --n-gpu-layers --threads
run 8:  --host --n-gpu-layers --ctx-size --threads
run 9:  --n-gpu-layers --ctx-size --threads
run 10: (none!)
```
This explains the user's per-run differences (runs 1-2 vs run 3): **there is no CLI/config/env difference** — `REQUESTED_FLAGS` and `CONFIG_REQUESTED_FLAGS` are empty (no ai.env `LLAMACPP_*` keys, no CLI flags; verified the `requested_from_env_config` calls return early). Flag validation runs identically each time; the outcome is a scheduling race. Both `validate_default_flags` (warn+omit) and `validate_requested_flags` (hard `err`) carry the same bug — a requested `--ctx-size` would randomly hard-fail with "does not expose".

Verdict: **H3 REFUTED as stated; SIGPIPE+pipefail race is THE root cause of the flag rejections.**

**[DONE]**

## Step 4: H4 — Model resolution

`resolve_model` (`bin/pos-ai-server:229-259`) accepts: absolute FILE path (`[ -f ]`), `$HF_DOWNLOAD_DIR/<name>` **FILE** (`[ -f "$candidate" ]`), or relative FILE. It never treats a DIRECTORY under `$HF_DOWNLOAD_DIR` as a model.

Downloader layout (`bin/pos-ai-hf`): `hf_repo_dir()` (lines 308-311) → `$HF_DOWNLOAD_DIR/${repo_id//\//-}` — e.g. repo `Qwen/Qwen-Qwen3-1.7B-GGUF` → dir `$HF_DOWNLOAD_DIR/Qwen-Qwen3-1.7B-GGUF/` containing `Qwen3-1.7B-Q8_0.gguf` + `.hf-meta`.

Reproduction (fixture dir created exactly like the user's; `.gguf` stub inside):
```
$ pos-ai-server start Qwen-Qwen3-1.7B-GGUF
[!] installed llama.cpp unknown does not support default flag --threads — omitting it from the unit
ERROR: Model not found: Qwen-Qwen3-1.7B-GGUF (also searched /home/unknown/.local/share/linux_post_install/ai/models)
EXIT: 1
```
Exact user message. The user's `mv Qwen3-1.7B-Q8_0.gguf ../` moved the file into `$HF_DOWNLOAD_DIR/`, but the arg `Qwen-Qwen3-1.7B-GGUF` is still a dir name → still fails (run 2 reproduced identically). The absolute file path (run 3) succeeds at model resolution (reproduced).

`pick_model` (lines 205-227) uses `find "$HF_DOWNLOAD_DIR" -name '*.gguf' -type f` — RECURSIVE, does NOT miss subdirs (verified). But it is only reached when no explicit arg/config is given; the user passed an explicit arg, so it wasn't involved.

**H4 CONFIRMED.**

**[DONE]**

## Step 5: H5 — dbus/systemctl under SSH

Code ordering (`bin/pos-ai-server`):
- `set -euo pipefail` (line 2)
- unit write + `chmod 644` (lines 584-602)
- `systemctl --user daemon-reload` (line 605)
- `systemctl --user enable --now "$SERVICE"` (line 606)
- linger hint (lines 610-615)

No pre-check of the user bus anywhere in the file. Same pattern in `pos-communication-matrix-listener:341-342` and `pos-network-download:191-192`; NO tool pre-checks the bus (`pos-entertainment-status:55` uses `systemctl --user show-environment` only as a query guard, not an enable guard).

Reproduced exactly on target machine (SSH-like shell: `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS` unset):
```
$ systemctl --user show-environment
Failed to connect to user scope bus via local transport: $DBUS_SESSION_BUS_ADDRESS and $XDG_RUNTIME_DIR not defined (consider using --machine=<user>@.host --user to connect to bus of other user)
rc=0 (exit status shown as 0 because of head pipe; the systemctl command itself fails)
```
With `set -e`, line 605's failure aborts the script; the linger hint (611-615) never runs.

Remediation verified: with ONLY `export XDG_RUNTIME_DIR=/run/user/$(id -u)` (dir exists), `systemctl --user show-environment` succeeds. `loginctl enable-linger` is the standard persistence fix.

Orphaned-unit side effect confirmed: the unit file remains written even though daemon-reload failed (a real orphaned unit exists at `~/.config/systemd/user/pos-ai-server.service` from the failed attempt on this machine — see Step 6 for its corrupted ExecStart).

**H5 CONFIRMED.**

**[DONE]**

## Step 6: H6 — Port mismatch (downstream impact)

llama.cpp default port: **8080**.
- Binary evidence: real `--help` → `--port PORT port to listen (default: 8080)`
- Source citation: `common/common.h:620` → `int32_t port = 8080; // server listens on this network port` (also `common/common.h:261` in struct block; `from https://raw.githubusercontent.com/ggml-org/llama.cpp/master/common/common.h`)

Tool/adapter default: **8088** — `bin/pos-ai-server:329` (`PORT="${LLAMACPP_PORT:-8088}"`), `:281`, `:316`; `lib/ai-providers/llamacpp.sh:15,23,49` (adapter probes `http://$host:$port/v1/models` and `/v1/chat/completions`); health check `bin/pos-ai-server:198` probes `$HOST:$PORT`.

Real corrupted unit found on this machine (from the failed start attempt — the SIGPIPE race omitted flags):
```
ExecStart="/usr/local/bin/llama-server" -m "…/Qwen3-1.7B-Q8_0.gguf" --host 127.0.0.1
```
Only `--host` survived — `--port 8088`, `--n-gpu-layers 0`, `--ctx-size 4096`, `--threads N` were all dropped. If `systemctl` had succeeded, llama-server would bind **8080** while `check_health` and the OpenAI adapter probe **8088** → "not running" / connection refused. Even when the race lets the unit through, H6 guarantees a downstream mismatch whenever `--port` is omitted.

**H6 CONFIRMED.**

**[DONE]**

## Root Cause Statement (final)

The user's exact messages trace to four independent defects in `bin/pos-ai-server` (plus one in the adapter default):

1. **"installed llama.cpp unknown"** — `detect_llama_version` (`:71`) discards stderr; real llama.cpp b10822 prints `version: 0.4.0-dev (build 10822, …)` to **stderr** (`common/build-info.h:13`), so the capture is always empty → "unknown".
2. **"does not support default flag …"** — `printf '%s' "$help_text" | grep -qE` under `set -o pipefail` races: grep -q exits at first match, printf gets SIGPIPE, pipefail promotes rc=141, so valid flags are randomly judged "unsupported" and omitted from the unit (or hard-errored when user-requested). This is the reason runs 1-2 and run 3 flagged different sets of flags — pure scheduling, not input differences.
3. **"Model not found: Qwen-Qwen3-1.7B-GGUF"** — the HF downloader puts weights at `$HF_DOWNLOAD_DIR/<repo-slug>/<file>.gguf`, but `resolve_model` accepts only files; a directory argument fails (`:241-248`), even after the user's `mv` (the arg was still a directory name).
4. **"Failed to connect to user scope bus …"** — the unit write (`:584-602`) precedes an unguarded `systemctl --user daemon-reload` (`:605`); under SSH neither `XDG_RUNTIME_DIR` nor `DBUS_SESSION_BUS_ADDRESS` is set, so systemctl fails, `set -e` aborts, and the linger fix hint (`:611-615`) never shows. The orphaned unit left behind can carry a corrupted ExecStart (see H6), e.g. missing `--port 8088` so the server would bind llama.cpp's default 8080 while the adapter/health check probe 8088.

Classification: **FACT** (mechanisms directly reproduced with the real b10822 binary; source citations for stderr stream and port default; unit artifact inspected).

## Fix-Point Spec

| # | File:line | Defect | Minimal change | Design question for Architect |
|---|-----------|--------|----------------|-------------------------------|
| F1 | `bin/pos-ai-server:71` | version always "unknown" (stderr discarded; regex also brittle for pure-build strings) | Capture `2>&1`; broaden regex to also accept `build [0-9]+`/`b[0-9]+`: `version="$("$bin" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+|build [0-9]+|b[0-9]+' | head -1 …)"` | Canonical display: semver vs build number vs both? |
| F2 | `bin/pos-ai-server:101,145` | `printf|grep -q` + pipefail SIGPIPE race → random flag rejection | Replace the pipeline: `grep` without `-q` writing to `/dev/null`, e.g. `if grep -E -- "…" <<<"$help_text" >/dev/null; then` (non-q grep consumes all input; herestring avoids the pipe and printf EPIPE), **or** bash regex `[[ "$help_text" =~ (^|[[:space:]])${flag}([[:space:]]|=|$) ]]` | Style preference: grep-herestring vs bash `=~`; whether to harden `validate_requested_flags` identically (yes) |
| F3 | `bin/pos-ai-server:229-259` (`resolve_model`) | directory under `HF_DOWNLOAD_DIR` (one `.gguf`) rejected | When `$candidate` is a directory: if exactly one `*.gguf` inside → use it; if multiple → list and err/ask | Should auto-expand single-gguf dirs, or require explicit file path? (Recommended: auto-expand, since downloader always produces `<repo>/<file>` layout) |
| F4 | `bin/pos-ai-server:605-606` (+ same in matrix-listener:341, network-download:191) | no user-bus pre-check; SSH w/o XDG_RUNTIME_DIR → set -e abort; orphan unit; linger hint skipped | Pre-flight before daemon-reload: `systemctl --user show-environment` (or `printenv XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS`); on failure `err` with remediation: `export XDG_RUNTIME_DIR=/run/user/$(id -u)` (if dir exists) and `sudo loginctl enable-linger $(id -un)`; optionally run the server directly (no unit) as fallback | Fallback strategy: error+hint only, or run-direct fallback? Also: consider removing the orphaned unit on failure (Builder decision) |
| F5 | `bin/pos-ai-server:56` (`find_llamacpp`) | bare `server` / `llama.cpp/server` fallbacks can pick unrelated binaries | Drop `"server"` (keep `llama-server`, `llama-server-cuda`; keep or drop `llama.cpp/server`) | Should the fallback list be `llama-server`/`llama-server-cuda` only? |
| F6 | `bin/pos-ai-server:528-532` + `lib/ai-providers/llamacpp.sh:15,23,49` | `--port` omission → server on 8080 vs adapter/health on 8088 | Guarantee `--port $PORT` always emitted (F2 fixes the omission); as defense-in-depth, adapter health fallback probe both 8088 and 8080, or derive from the unit | Should the tool ever allow running on llama.cpp's default 8080, or always pin 8088? |
| F7 | `apps/ai/llamacpp.sh:46-57` | installer never verifies the installed binary runs (version/help readable) | Post-install sanity: `llama-server --version >/dev/null 2>&1 && llama-server --help >/dev/null`; warn on failure | None (simple hardening) |

## Design Questions (explicit)

1. **F2/F3 boundary:** Should unknown-version disable flag *validation* entirely (trust defaults), or retain help-based validation but fix the SIGPIPE race? (Recommended: keep validation, fix race — help-based validation is the correct design once deterministic.)
2. **F3:** Should `resolve_model` auto-expand a single-`.gguf` directory; with multiple gguFs, err with the list?
3. **F4:** On unresolvable user bus: error+hint only, or a run-direct fallback (no systemd unit) for headless/SSH use?
4. **F5:** Drop the bare `server` (and possibly `llama.cpp/server`) fallback candidates?
5. **F6:** Pin the port in the unit always (recommended) vs teach the adapter to probe the llama.cpp default 8080 as a fallback?

## Test-Fixture Spec (for Tester)

Each fix gets a stub/PATH/case that reproduces it deterministically:

- **F1 (version):** fake `llama-server` printing `version: 0.4.0-dev (build 10822, commit c457e3bf7)` **to stderr**, help to stdout. Assert `detect_llama_version` returns `0.4.0` (not "unknown") with the fixed `2>&1`; also fixture printing only `version: b10822`/`build 10822` to stderr to assert the broadened regex.
- **F2 (race):** fake `llama-server` whose `--help` emits a 59 KB body with tokens `--threads` at line 7, `--ctx-size` at line 25, `--n-gpu-layers` at line 140, `--host`/`--port` near the end (exact real llama.cpp layout). Run `validate_default_flags` 20× under `set -euo pipefail`; fixed code must report all 5 supported on EVERY run (deterministic). Regression tail: pre-fix, the run must fail at least once (demonstrates the race existed).
- **F3 (model dir):** fixture `$HF_DOWNLOAD_DIR/Qwen-Qwen3-1.7B-GGUF/Qwen3-1.7B-Q8_0.gguf` (+ `.hf-meta`). Assert `pos ai server start Qwen-Qwen3-1.7B-GGUF` (DRY_RUN=1) resolves to the file; multi-gguf dir case errors with the file list.
- **F4 (bus):** environment with `XDG_RUNTIME_DIR`/`DBUS_SESSION_BUS_ADDRESS` unset (or a stub `systemctl` that fails with the dbus message); assert the pre-flight fails with the remediation hint AND the linger hint text when applicable; assert no orphaned unit is left (or is removed on failure).
- **F5 (server fallback):** PATH containing ONLY a fake unrelated `server` (prints its own --help/--version) and no llama-server; assert `find_llamacpp` does NOT return `server`.
- **F6 (port):** with F2 fixed, generate a unit with `DRY_RUN=1` and assert ExecStart always contains `--port 8088` (and `--host`, `--n-gpu-layers`, `--ctx-size`, `--threads`).
- **F7 (installer):** run `apps/ai/llamacpp.sh` against a fixture tar containing a broken binary (e.g., missing shared lib) → assert post-install sanity warns.

## Evidence Index (concrete artifacts)

- Real binary downloaded/run: `llama-b10822-bin-ubuntu-x64.tar.gz` from `https://github.com/ggml-org/llama.cpp/releases/tag/b10822` (asset `llama-b10822-bin-ubuntu-x64.tar.gz`).
- `llama-server --version` → stderr: `common/build-info.h:13` (`FILE * = stderr`), `common/arg.cpp:1454-1458`, plus byte-level `od -c`/redirect proof.
- `--help` flag lines: real output lines 7/25/140/503/506; byte offsets 320/1892/10992/39499/39741; total 59001 bytes (< 64 KB pipe buffer).
- Pipeline rc=141 proof: `/tmp/test_sigpipe3.sh` output (rc 0/141 alternating).
- 10-run `pos-ai-server` flakiness table (see Step 3).
- Real corrupted orphaned unit: `~/.config/systemd/user/pos-ai-server.service` — `ExecStart=… --host 127.0.0.1` (port/ctx/threads/gpu-layers omitted).
- Model-not-found exact reproduction and post-`mv` reproduction.
- User-bus error reproduced verbatim on target machine; `export XDG_RUNTIME_DIR=/run/user/$(id -u)` remediation verified working.
- Default port: `common/common.h:620` (`int32_t port = 8080`); real `--help` `(default: 8080)`.
- H2 fixture: fake unrelated `server` → `find_llamacpp` returns `server`, all defaults "unsupported".

## Next Agent

**Builder** — five (F1-F5) of the six fix-points are code changes in `bin/pos-ai-server` (plus `apps/ai/llamacpp.sh` for F7); Architect input needed on the design questions before/while implementing F2/F3/F4/F6.

**Changes made by Detective:** none (read-only; only downloaded/extracted to /tmp and created user-level fixtures under `/home/unknown/.local/share/linux_post_install/ai/models` matching the user's layout for reproduction).