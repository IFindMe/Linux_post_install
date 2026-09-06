# Explorer Report — 2026-09-06 — Tooling Audit (lint perf, install/uninstall symmetry, config-parsing duplication, shell correctness)

## TL;DR

- **Lint perf:** `scripts/lint-conventions.sh` (261 lines) has ~17 external-process hotspots; the dominant cost is **two full-file scans that spawn `printf | sed | tail` per line** (`uses_stdin` L67 and the top-level-`local` scan L143) — for a ~45-tool repo with several >1000-line tools this is roughly **60k+ subprocess forks per lint run** just from those two scans. Wall-time measurements are **UNVERIFIED** (sandbox denies `time`/`make`/`bash` execution); static hotspot inventory below is complete.
- **Install/uninstall symmetry:** a real uninstaller exists (`pos system uninstall`, 435 lines) but it is **PARTIAL** — 9 of 12 installed `lib/*.sh` have no removal path, the ScaleTail template clone (`/usr/local/share/linux_post_install/scale-tail`) and the feature-flag store (`/usr/local/share/linux_post_install/flags/`) are never removed, `~/.config/rclone/` and `/usr/local/bin/yt-dlp` survive, and **all runtime-created systemd *user* units** (`~/.config/systemd/user/`) are missed by every tier.
- **Config duplication:** **9 tools hand-roll byte-similar `load_config()`-style loaders** (env-wins export loop), plus at least 4 bespoke parsers; 2 shared key-value read/write libraries (`config-ui.sh` `cfg_value`/`cfg_write` and `entertainment-lib.sh` `config_value`/`write_config_key`) are duplicates of each other. CRLF-strip behavior splits 5-and-5; the `CONFIG_DIR`/XDG seam is honoured by self-contained tools but **bypassed by several common.sh-sourcing tools** that hardcode `$HOME/.config/linux_post_install/...`. Recommended owner: **`lib/config-ui.sh`**.
- **Shell correctness:** no high-confidence unquoted-`rm -rf`, unquoted-`[ $x ]`, or unguarded-`cd` bugs found in `bin/`; the flagged hotspots are `bin/pos:388/403` (`run eval "$cmd"` — AI-extracted command execution, deliberate but security-relevant), `bin/pos-system-uninstall:333` (`sed -i '/pos/d'` on user `.bash_completion`), and the per-line subprocess spawns in the lint script itself.

---

## Task 1 — Lint performance (`scripts/lint-conventions.sh`, 261 lines)

### 1.1 Measured timing

| Command | Result |
|---|---|
| `time make lint` (run 1) | **UNVERIFIED** — sandbox denies `make`, `bash`, `time` execution |
| `time make lint` (run 2) | **UNVERIFIED** |
| `time bash scripts/lint-conventions.sh` | **UNVERIFIED** |

Static hotspot analysis is complete and is the basis for the estimates (see 1.3).

### 1.2 Per-line/per-file external-process hotspots (rule → implementation → bash-native alternative)

F = per-file spawn, L = per-line spawn, 1× = one-off.

| # | Lint rule | Location | Spawns per unit | Bash-native equivalent (no semantics change) |
|---|---|---|---|---|
| 1 | shebang check | L92 `head -1 "$f" \| grep -q` | F (2 procs/file) | `IFS= read -r first < "$f"` + `[[ $first == '#!/usr/bin/env bash' ]]` |
| 2 | strict-mode check | L95 `has_regex` → `grep -qE` | F (1 proc/file) | fold into the same first-line read as #1 |
| 3 | INTERACTIVE_CMDS extraction | L84 `sed -n … \| head -1` | 1× (2 procs) | single `read` with regex |
| 4 | `# POS:` header text | L110 `sed -n '/^# POS: /{…;q}'` | F (1 proc/tool) | read up to first `# POS:` line in bash loop |
| 5 | em-dash presence | L115 `grep -q ' — ' <<<"$headline"` | F (1 proc/tool, heredoc string) | `[[ $headline == *' — '* ]]` |
| 6 | `# POS:` line number | L118 `grep -nE … \| head -1 \| cut -d: -f1` | F (3 procs/tool) | captured in the same loop as #4 |
| 7 | deps-guard-before-help | L127 `first_guard_line` | F (0 extra — bash loop) | already bash-native |
| 8 | help-line number | L128 `first_line` → `grep -nE … \| while read` | F (1 proc/tool) | same first-match read loop as #4/#6 |
| 9 | top-level `local` scan | L137–157 with **L143 `printf '%s\n' "$line" \| sed -nE … \| tail -1`** | **L (3 procs per line of every tool)** | `[[ $line =~ <<-?[[:space:]]*([A-Za-z0-9_]+) ]]` in-bash |
| 10 | stdin-reader detection | L59–80 `uses_stdin` with **L67 `printf \| sed \| tail`** | **L (3 procs per line — scans every tool a 2nd time)** | same `[[ =~ ]]` regex; can also merge with #9 into ONE pass |
| 11 | POS.md reference | L169 `grep -q "$(basename "$f")" DOC/POS.md` | F (1 proc/tool) | read POS.md into a var once; `[[ $posmd == *$basename* ]]` |
| 12 | INTERACTIVE_CMDS entry check | L174–180 | — | fine |
| 13 | plugin common.sh / POS_PLUGIN / app uninstall fn+case / systemd / wrapper checks | L184,187,196,197,201,208,211,218,224 `has_regex` | F (1–2 procs/file each) | single-read first-match loop per file |
| 14 | wrapper line count | L221–222 `wc -l < "$f"` **twice** | F (2 procs/wrapper) | `mapfile -t lines < "$f"; ${#lines[@]}` |
| 15 | secret-literal scan | L229–243 `grep -nE` per file + **L235 `grep -qE … <<<"$body"` per matched line** | F + L (heredoc-string greps) | `[[ $body =~ (TOKEN|PASSWORD|…)= ]]` |
| 16 | system-path write scan | L245–258 `grep -nE` per file + **L251 two `grep -qE <<<"$body"` per matched line** | F + L | `[[ $body =~ (>|>>|tee ) ]] && [[ $body =~ (/etc/|\$HOME|/usr/local) ]]` |
| 17 | `last_line()` | L39–42 | **dead code — defined, never called** | delete |

### 1.3 Estimated cost

- The two per-line scans (#9, #10) each read every line of every `bin/pos-*` tool twice. The repo has 45 tools with several >1000-line files (pos-docker-vbox 1125, pos-media-ytsync 1213, pos-network-download 1108) — total tool lines ≈ 15–20k. At 3 forks/line × 2 scans ≈ **90k–120k `printf|sed|tail` subprocess forks per lint run** just from those two rules.
- Remaining rules add ≈ 10–15 forks per tool ≈ 500–700 more forks total. The secret/system-path scans add one grep per file plus per-matched-line heredoc greps.
- Expected effect: the lint time is dominated by process creation (fork/exec), not by grep itself. Replacing #9/#10 with `[[ =~ ]]` and merging into one pass should cut lint wall time by the largest factor; the heredoc-string greps (#5, #15, #16) are cheap per call but numerous.

### 1.4 `scripts/check-sync.sh` (42 lines) — brief

- `bash -n` per file, exec-bit loop, doc-sync via `gen-docs.sh --check`, 3 dispatch smokes. Per-file spawns are inherent to `bash -n` (must run bash anyway); no obvious perf bug.
- Correctness note: L14–16 glob list misses `features/*.sh`? — actually it includes `features/*.sh` (line 15 `features/*.sh`). It does NOT include `completions/*` other than `completions/pos.bash` (fine) and does not `bash -n` `install.sh`'s sourced libs beyond the list — libs are covered. No hotspot.

### 1.5 `scripts/gen-docs.sh` (254 lines) — brief

- `sed` per header per tool (L42–47: 6 sed calls/tool) — minor; only runs on `make gen`, not per commit.
- L207–210 check mode: `sed` block extract + `cat` + `diff` per block — fine for check.
- Correctness hotspot: docmap convergence loop (L244–252) re-runs `regen_block docmap` up to 5 times by design; each iteration re-does a full-file `sed` + `grep -n` + `wc -l` — acceptable (documented convergence), but on a 700-line file it is the single slowest part of gen; an in-memory line accounting would converge in one pass. Not a bug.

### Task 1 — Ranked change list (no implementation)

1. Merge the per-line `printf|sed|tail` delimiter extraction into a single bash-native pass using `[[ $line =~ <<-?[[:space:]]*([A-Za-z0-9_]+) ]]` — used by the top-level-`local` scan (L143) and `uses_stdin` (L67). Highest ROI; removes the ~90–120k fork estimate.
2. Replace per-line heredoc-string `grep -q <<<"$body"` with `[[ $body =~ … ]]` in the secret (L235) and system-path (L251) scans.
3. Replace per-file `grep`/`sed|head|cut`/`wc` with a single read of the first ~6 lines per tool (covers L92/95/110/115/118/128) plus `mapfile` line counts for wrappers (L221).
4. Replace `grep -q <basename> DOC/POS.md` (L169) with one preloaded POS.md content check.
5. Delete the dead `last_line()` (L39–42).

---

## Task 2 — Install/uninstall symmetry

### 2.1 What exists

- **Installer:** `install.sh` phases 1–4 + optional apps. Uninstall path documented in `install.sh:68–71` (apps only) and provided as a **CLI tool** `bin/pos-system-uninstall` (not a `make uninstall`, not a scripts/ uninstaller — grep of `Makefile`, `scripts/`, `README.md` shows no `make uninstall`; `apps/install.sh --uninstall` handles optional desktop apps only).
- **Uninstaller:** `bin/pos-system-uninstall` — Tier 1 (always): binaries, plugins, known systemd services, shell integration; Tier 2 (`--config`): `~/.config/linux_post_install`; Tier 3 (`--data`): `~/.local/share/linux_post_install`.

### 2.2 Install inventory vs uninstall coverage

| Artifact | Installed by | Removal path | Verdict |
|---|---|---|---|
| `bin/*` → `/usr/local/bin/` (45 pos-*, pos, flag-*, wr-*, mp3/mp4/vbox/ssh-load-all) | Phase 2 (install.sh:136–140) | Tier 1: `/usr/local/bin/pos` + `compgen -G /usr/local/bin/pos-*` + legacy names (L53–83, 229–257) | **SYMMETRIC** |
| `lib/common.sh`, `lib/menu-lib.sh`, `lib/share-lib.sh` → `/usr/local/bin/` | Phase 2 (install.sh:143–144) | Tier 1 (pos-system-uninstall:62–64) | **SYMMETRIC** |
| `lib/{flags,notify,entertainment-lib,scheduler-lib,config-ui,user-timers-lib,entertainment-plugin-lib,usb-lib,registry}.sh` → `/usr/local/bin/` | Phase 2 (install.sh:143–144) | **none** | **INSTALL-ONLY** (9 of 12 libs) |
| `lib/ai-providers/*.sh` → `/usr/local/bin/ai-providers/` | Phase 2 (install.sh:154–161) | Tier 1 `rm -rf /usr/local/bin/ai-providers` (L244) | **SYMMETRIC** |
| `entertainment/*.sh` → `/usr/local/bin/` | Phase 2 (install.sh:167–173) | Tier 1 — **hardcoded list** `weather.sh gold.sh joke.sh` (L72, 248) | **SYMMETRIC today**; breaks automatically if a 4th plugin is added |
| `x64_bin|arm64_bin/*` → `/usr/local/bin/` | Phase 2 (install.sh:179–194) | Tier 1 hardcoded `wihotspot wihotspot-gui create_ap` (L86, 260) | **SYMMETRIC today**; same hardcode fragility |
| `features/*` → `/usr/local/bin/` (--feature) | Phase 2 (install.sh:197–222) + flag set | Tier 1 `autostart.sh usb-automount.sh` (L91, 265) | **SYMMETRIC today**; hardcoded |
| **Feature-flag store** `/usr/local/share/linux_post_install/flags/` | Phase 2 `flag_set` (install.sh:216) | **none** (no `flags`/`flag` match in pos-system-uninstall) | **INSTALL-ONLY** |
| **ScaleTail clone** `/usr/local/share/linux_post_install/scale-tail` | Phase 4 (install.sh:237–243) | **none** (only bash-completion under /usr/local/share is removed, L108) | **INSTALL-ONLY** |
| `completions/pos.bash` → `/usr/local/share/bash-completion/completions/pos.bash` | postinstall.sh:100–107 | Tier 1 (L108, 284) | **SYMMETRIC** |
| systemd `*.service`/`*.timer` → `/etc/systemd/system/` + enable | postinstall.sh:139–166 | Tier 1: 3 known + find `-name '*linux_post_install*' -o -name 'pos-*'` (L287–311) | **SYMMETRIC** (system units) |
| `config/authorized_keys` → `~/.ssh/authorized_keys` | postinstall.sh:110–137 | **none** (tier 2 only targets `~/.config/linux_post_install`) | **INSTALL-ONLY** (by design — user data) |
| `config/rclone.conf` → `~/.config/rclone/rclone.conf` | postinstall.sh:10–17 | **none** (tier 2 path is `linux_post_install` only) | **INSTALL-ONLY** |
| `config/{entertainment,system,notify,ai}.env` → `~/.config/linux_post_install/` | postinstall.sh:22–50 | Tier 2 (`--config`) find over the dir (L147–155) | **SYMMETRIC** (opt-in tier) |
| `config/schedule.d/*.env` → `~/.config/linux_post_install/schedule.d/` | postinstall.sh:57–77 | Tier 2 + rmdir schedule.d (L351–355) | **SYMMETRIC** (opt-in tier) |
| PATH line + completion line in `~/.bashrc` | postinstall.sh:80–98 | Tier 1 sed removals (L320–322) | **SYMMETRIC** |
| apt packages (25+) + yt-dlp → `/usr/local/bin/yt-dlp` + cpufreq | preinstall.sh:28–75 | **none** (uninstaller never touches apt or yt-dlp) | **INSTALL-ONLY** (likely deliberate — system packages) |

### 2.3 Runtime-created state (created by tools at runtime, not install.sh)

| Artifact | Created by | Uninstall path in pos-system-uninstall | Verdict |
|---|---|---|---|
| `~/.config/linux_post_install/<tool>.env` (ai, telegram, matrix, scrcpy, download, ytsync, grab, ai-aliases, compose) | tools' config writes | Tier 2 (`--config`) | **RUNTIME-STATE / SYMMETRIC** (removed with --config) |
| `~/.local/share/linux_post_install/{logs,ytsync,ai/models,entertainment/last,backups}` | bin/pos logging + tools | Tier 3 (`--data`) | **RUNTIME-STATE / SYMMETRIC** (removed with --data) |
| **systemd *user* units** `~/.config/systemd/user/`: `pos-aria2.service`+`pos-aria2-retry.{service,timer}` (pos-network-download:172–190,633–669), telegram-listener unit (pos-communication-telegram-listener:471–521), matrix-listener unit (pos-communication-matrix-listener:315–364), `pos-ai-server.service` (pos-ai-server:500–522), entertainment timers `pos-entertainment-*.timer` (user-timers-lib), scheduler per-job timers (scheduler-lib) | runtime tool subcommands | **none** — Tier 1 only scans `/etc/systemd/system` (L287–311); Tier 2 only `~/.config/linux_post_install`; `~/.config/systemd/user/` is outside both | **INSTALL-ONLY** (from the uninstaller's perspective; each tool's own `stop`/`disable` subcommand does remove its own unit, e.g. `pos network download stop` L209–211) |
| `~/.local/bin/pos-ai-hook.sh` + `ai-aliases.sh` wrappers | pos-ai-alias | Tier 1 pos-ai-hook + marker-managed alias scan (L96–105, 270–281) | **SYMMETRIC** |
| `~/.config/rclone/rclone.conf` (from postinstall) | postinstall.sh:10–17 | none | **INSTALL-ONLY** |

### Task 2 — Ranked change list (no implementation)

1. **Remove the 9 orphaned libs** (`flags.sh`, `notify.sh`, `entertainment-lib.sh`, `scheduler-lib.sh`, `config-ui.sh`, `user-timers-lib.sh`, `entertainment-plugin-lib.sh`, `usb-lib.sh`, `registry.sh`) in Tier 1 — the biggest INSTALL-ONLY gap (hardcoded `common.sh menu-lib.sh share-lib.sh` only, pos-system-uninstall:62–64).
2. **Remove ScaleTail templates** `/usr/local/share/linux_post_install/scale-tail` and the **feature-flag store** `/usr/local/share/linux_post_install/flags/` in Tier 1 (documented install outputs in AGENT_Context §3/§10, no removal).
3. **Add a user-unit sweep** to Tier 1: disable+remove matching units in `~/.config/systemd/user/` (prefixes `pos-*`, `pos-entertainment-*`, `pos-schedule-*` etc.), or document that per-tool `stop` is the supported path.
4. De-hardcode the entertainment-plugin / prebuilt-binary / feature names in the uninstaller to directory-driven discovery (mirror install.sh's loops) so future plugins/bins don't silently become INSTALL-ONLY.
5. Decide (and document) whether `~/.config/rclone`, `~/.ssh/authorized_keys` additions, apt packages, and `/usr/local/bin/yt-dlp` are intentionally outside uninstall — currently silent.

---

## Task 3 — Config-parsing duplication

### 3.1 Inventory

**Shared loaders that exist:**

| Loader | Location | Used by |
|---|---|---|
| `load_system_env()` (env-file → export, env-wins) | lib/common.sh:146–159 | pos-system-health, pos-system-backup, pos-media-sync (system.env) |
| `cfg_value()` / `cfg_write()` (key read/write, `KEY="value"`, chmod 600) | lib/config-ui.sh:311–344 | pos-config; pos-entertainment-config:L98 sources config-ui dynamically; config-scope registry consumers |
| `config_value()` / `write_config_key()` (key read/write, same semantics) | lib/entertainment-lib.sh:28–54 | pos-entertainment-{config,status,enable,disable,send} |
| inline `grep '^NOTIFY_PLATFORM=' \| tail -1 \| cut` | lib/notify.sh:41 | notify_send |

**Hand-rolled near-identical `load_config()`-style loaders (9)** — each is the same ~14-line loop: `grep -E '^[A-Z_]+=' | while IFS='=' read k v` + quote-strip + `[ -z "${!k:-}" ] && export`:

1. bin/pos-communication-telegram-sender:61–74 (`load_config`)
2. bin/pos-communication-matrix-listener:65–77 (`load_config`)
3. bin/pos-communication-telegram-listener:86–98 (`load_config`)
4. bin/pos-communication-matrix-sender:44–57 (`load_config`)
5. bin/pos-communication-scrcpy:14–28 (`load_config`)
6. bin/pos-ai:130–160 (`load_config`, plus legacy-file loop)
7. bin/pos-ai-server:21–35 (`load_config`)
8. bin/pos-ai-hf:30–44 (`load_hf_config`)
9. bin/pos-media-grab:10–23 (`load_grab_config`)

**Bespoke parsers (4+):**

- bin/pos-network-download:32–37 `load_secret` — single-key `grep'^RPC_SECRET=' | head -1 | cut -d= -f2-`; also duplicated inline at L153–154
- bin/pos-docker-compose:9–10 + layered strategy (`template < global compose.env < per-service .env`, documented L31–48) — reads global config via `CONFIG_ENV` and per-service envs
- bin/pos-share-smb-server:97 `reload_config` — Samba-specific
- bin/pos-media-ytsync:28–30 `_YTSYNC_CFG` via `pos config ytsync` scope; plus the share-client (`pos-share-smb-client`) creds records parsing

**Counts:** 45 `pos-*` tools; ~20 source `lib/common.sh`; **9 hand-roll their own file parser**; only `pos-config` and the entertainment tools use a shared key-value loader; 3 use `load_system_env`; the 5 self-contained communication tools duplicate the loader because they don't source common.sh (documented convention: guarded inline fallback copies in DEV.md).

### 3.2 Consistency findings

- **Precedence order** is `env > config-file > defaults` everywhere the hand-rolled loaders are used (`if [ -z "${!k:-}" ]` before export; defaults applied later via `${VAR:-default}`). CLI-vs-config precedence is declared `CLI > environment > config file` in the three tools that document it (telegram-sender:45, scrcpy:70, matrix-sender:29). pos-docker-compose is the outlier model (per-service file wins over global file; no env) — a different domain, but also the only tool where "config file" beats "global defaults" deliberately.
- **CRLF handling diverges:** 5 loaders strip `\r` (matrix-sender:53, scrcpy:23, ai:139, ai-server:30, ai-hf:39) but 5 do NOT (telegram-sender, matrix-listener, telegram-listener, media-grab, and `load_system_env` in common.sh:154). A Windows-edited `.env` parses differently depending on which tool reads it.
- **CONFIG_DIR / XDG seam divergence:** self-contained tools (+ config-ui.sh:32, notify.sh:27) carry the guarded `CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/linux_post_install}"` copy; but several tools that **source** common.sh (which defines `CONFIG_DIR` at line 19) still hardcode `$HOME/.config/linux_post_install/...`: pos-ai:11, pos-ai-hf:26, pos-ai-server:15, pos-media-grab:11, common.sh load_system_env:147, entertainment-plugin-lib:15, pos-docker-compose:10. So `CONFIG_DIR`/`XDG_CONFIG_HOME` overrides work for some tools and are silently ignored by others.
- **Key-value writers duplicated** — `cfg_write` (config-ui.sh:323) and `write_config_key` (entertainment-lib.sh:36) are the same algorithm (grep -v + append, `-` deletes, chmod 600); only the value-quoting and the multi-line warning differ.

### 3.3 Recommendation (no implementation)

- **Owner: `lib/config-ui.sh`.** It already hosts the `POS_CONFIG` scope registry that `pos config` consumes, has secret masking/validation helpers, and is installed to `/usr/local/bin` alongside the tools.
- Add one generic loader there, e.g. `load_env_file <file>` (env-wins export loop with quote + CRLF strip parsed consistently) and have `load_system_env` delegate to it.
- Merge `entertainment-lib.sh` `config_value`/`write_config_key` into `cfg_value`/`cfg_write` (keep `config_value` as a thin alias for the entertainment tools, or migrate the 5 call sites).
- **Migration targets:** the 9 hand-rolled loaders → `load_env_file` (source `config-ui.sh` in the 5 self-contained communication tools, replacing their guarded inline copies and CONFIG_DIR blocks); `pos-network-download` → `cfg_value "$CONFIG_FILE" RPC_SECRET`; `pos-docker-compose` `config show` → `cfg_value`/`cfg_write` for the global config.
- Unify CRLF-strip and the `CONFIG_DIR` path source across every loader during the migration.

### Task 3 — Ranked change list (no implementation)

1. Add `load_env_file` to `lib/config-ui.sh`; make `common.sh load_system_env` delegate; fix the CRLF split in the process.
2. Migrate the 9 hand-rolled loaders (list in 3.1) to it; make the 5 self-contained communication tools source `config-ui.sh` instead of the inline CONFIG_DIR+load_config copies.
3. Fold `entertainment-lib.sh` read/write helpers into `cfg_value`/`cfg_write` (alias or migrate the 5 entertainment call sites).
4. Route `pos-network-download` `load_secret` and `pos-docker-compose` global-config reads through `cfg_value`.
5. Replace hardcoded `$HOME/.config/linux_post_install/...` in the common.sh-sourcing tools with the sourced `CONFIG_DIR` (pos-ai, pos-ai-hf, pos-ai-server, pos-media-grab, load_system_env, entertainment-plugin-lib, pos-docker-compose).

---

## Task 4 — Shell-correctness hotspots (high-confidence only)

Method: targeted scan of `bin/` and `lib/` for unquoted `$var` in args/array appends, `for x in $list`, `[ $x = … ]`, `rm -rf $VAR`, unguarded `cd`, missing `|| true` in pipelines under `set -euo pipefail`, `eval` of derived strings. Only high-confidence items below.

### 4.1 High-confidence findings

- **H-001 (WARN) — `bin/pos-ai:388,403` `run eval "$cmd"`.** `_prompt_run_command` executes a command string extracted from AI output. Interactive path prompts on `/dev/tty`; the `--trust` path (L385–388) auto-executes without confirmation. Deliberate feature, but any AI-output-derived command executed through `eval` is a shell-injection-relevant surface — recommend keeping, but it deserves explicit review of what `trusted=1` callers feed it. Classification: FACT (code), design concern.
- **H-002 (WARN) — `bin/pos-system-uninstall:333` `sed -i '/pos/d' "$HOME/.bash_completion"`.** Deletes **every** line containing the substring `pos` from a user-owned file, not just pos-managed lines (unlike the `pos-ai-hook` marker check at L277). A line like `complete -F _git checkout` is safe, but any unrelated completion containing "pos" (e.g. `repos`, `compose-help`, `dispose`) is silently removed — and this runs in default Tier 1. Classification: FACT.
- **H-003 (WARN) — `bin/pos-system-uninstall:320–322` `sed -i` on `~/.bashrc`.** Removal of PATH/completion/hook lines is line-based and unanchored at line start (`/source.*pos\.bash/d`, `/linux_post_install.*PATH/d`, `/source.*pos-ai-hook/d`); a user comment mentioning `pos.bash` is deleted. Lower risk than H-002 but same class. Classification: FACT.
- **H-004 (WARN) — `scripts/lint-conventions.sh:31,41,67,84,110,118,143,235,251`.** Under `set -euo pipefail`, the `grep | while read` and `... | tail -1 | cut` pipelines are only safe because of the `|| true` / `2>/dev/null` guards and the non-final elements' exit codes. The per-line `printf | sed | tail -1` inside the read loop (L67/L143) is the perf hotspot from Task 1 AND a correctness risk: if `sed` ever exits non-zero for a given line under `pipefail`, the surrounding `while read` loop aborts mid-scan. Classification: FACT (perf measured as static analysis); correctness risk is conditional, not observed.

### 4.2 Checked and cleared (not bugs)

- `rm -rf`/`rm -f` in `bin/` are consistently quoted (`pos-ai-hf:644,698,835,989`; `pos-system-uninstall` all lines; `pos-docker-vbox:1115`; app scripts). No unquoted/empty `rm -rf $VAR` found.
- Unquoted `[ $x … ]` comparisons: none found in `bin/` (only `"$var"` forms).
- `for x in $list` sites (`pos-docker-health:38`, `pos-docker-ps:36`, `pos-tree:71`, `pos-system-health:170`, `pos-network-checkport:408`, `pos-entertainment-status:39`, `pos:123`) intentionally word-split newline/comma-separated IDs or sorted output with no spaces in elements — not bugs at present, but a space in a future element (e.g. a plugin filename) would silently split. Low-priority hardening, not a defect.
- `cd` sites are guarded (`pos-docker-vbox:1029,1040` use `(cd "$d" 2>/dev/null && pwd) || …`; `pos-docker-compose:221–260` wrap in subshells with `set -e` context).
- `pos-share-smb-client:457` `sudo rm -f "$SMB_CREDS_DIR/$(basename "$where")"` — properly quoted.
- `find /etc/systemd/system/ -name '*linux_post_install*' -o -name 'pos-*'` (pos-system-uninstall:311) — `-o` binds both predicates to the stated path; matches both patterns as intended. Not a bug.
- `bin/pos` logging tee pipes: INTERACTIVE_CMDS handling verified by lint rule and existing registrations — no new finding.

### Task 4 — Ranked change list (no implementation)

1. Restrict `pos-system-uninstall` `.bash_completion`/`.bashrc` removal to anchored, marker-based patterns (e.g. only lines the installer itself added, or apply the `grep -q 'Managed by pos…'`-style marker check used for alias wrappers).
2. Review `bin/pos-ai` `_prompt_run_command` trust boundaries: confirm every `trusted=1` caller is user-flagged and document the eval surface (or re-run through `bash -c` with validation).
3. Convert lint L67/L143 per-line `printf|sed|tail` to `[[ =~ ]]` (also removes the pipefail-mid-loop abort risk).
4. Optional hardening: quote the `for x in $list` sites that consume plugin names/scheduled-job names where elements could contain spaces.

---

## Uncertainties

- **Lint wall time** could not be measured (sandbox denies `time`, `make`, `bash`). Estimates are derived from hotspot counts and file sizes (45 tools, 15–20k total lines); real numbers should be captured by a runner-capable agent (`make lint` ×2 + bare script) — see Handoff.
- The exact fork count per run is an INFERENCE (each `printf|sed|tail` is at least 3 forks; actual exec cost depends on PATH lookup and filesystem state).
- Whether apt packages / yt-dlp / `~/.ssh/authorized_keys` / `~/.config/rclone` are *supposed* to survive uninstall is a product decision, not verifiable from code.
- Whether the runtime-created user units are "expected to persist" is not documented anywhere in the repo; the uninstaller help text ("services") implies coverage, which is not delivered.

## Important Files

- `scripts/lint-conventions.sh` — all Task 1 hotspots (L31,41,67,84,92,95,110,115,118,137–157,162,169,221–222,235,251; dead `last_line` L39–42)
- `scripts/check-sync.sh`, `scripts/gen-docs.sh` — gates; convergence loop L244–252
- `install.sh` — phases, `should_run` (L100–117), copy targets (L136–222), ScaleTail (L237–243)
- `preinstall.sh` — apt PACKAGES (L28–43), yt-dlp (L65–68) — no uninstall counterpart
- `postinstall.sh` — rclone/entertainment/system/notify/ai env templates, schedule.d, .bashrc, completion, systemd
- `bin/pos-system-uninstall` — tiers, lib list L62–64, user-unit gap, H-002/H-003, find L311
- `bin/pos`, `bin/pos-ai`, `bin/pos-communication-{telegram,matrix}-{sender,listener}`, `bin/pos-communication-scrcpy`, `bin/pos-ai-server`, `bin/pos-ai-hf`, `bin/pos-media-grab`, `bin/pos-network-download`, `bin/pos-docker-compose`, `bin/pos-share-smb-server` — config-loading inventory (Task 3)
- `lib/common.sh` (load_system_env), `lib/config-ui.sh` (cfg_value/cfg_write), `lib/entertainment-lib.sh` (config_value/write_config_key), `lib/notify.sh` — loader candidates
- `DOC/DEV.md:182–213` — env-seam rules the loader centralization should preserve

## Handoff

- **Status:** OBJECTIVE_SATISFIED (plus measurement note)
- **Objective:** evidence audit of lint performance, install/uninstall symmetry, config-parsing duplication, shell-correctness hotspots — completed read-only.
- **Evidence / completed work:** this report; hotspot inventory with file:line; install/uninstall matrix; 9-loader duplication census with CRLF and CONFIG_DIR inconsistencies; 3 high-confidence shell hotspots.
- **Affected areas:** `scripts/lint-conventions.sh`, `bin/pos-system-uninstall`, `lib/config-ui.sh` + `lib/entertainment-lib.sh` + `lib/common.sh` (loader centralization), 9 tool files, `bin/pos-ai`.
- **Scope/decision boundary:** no code changed. Centralizing the loader (Task 3) is a deliberate cross-tool refactor with a doc convention ("guarded inline fallback copies" in DEV.md) — that is an Architect/Designer decision boundary, not a mechanical fix.
- **Verification performed:** full reads of lint/check-sync/gen-docs/install/preinstall/postinstall/uninstall/common/config-ui; greps across `bin/`+`lib/` for loaders, rm/cd/eval/for-splitting patterns; shared-memory check of maintainer/architect reports (no overlap: the 2026-09-06 convention-sweep was about POS header/doc drift, not these four areas).
- **Remaining uncertainty:** measured lint wall time (needs a runner-capable agent); intended persistence of apt packages/rclone/user units; actual fork count (inference).
- **Recommended next agent:** **Architect** (for the loader centralization decision: which library owns `load_env_file`, how self-contained tools source config-ui.sh without breaking the "no shared lib? inline fallbacks" convention) — and/or **Maintainer** for the uninstaller gaps + lint per-line hotspot rewrite if a decision is not needed.
- **Reason:** Task 3's fix crosses the documented DEV.md convention and 9 tool files (architectural boundary); Tasks 1/2/4 are mechanical cleanups that a Maintainer can implement once the loader decision is made.