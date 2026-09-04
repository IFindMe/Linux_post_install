# Builder — T8: categorized `pos docker vbox` create + unpersist micro-fix

## TL;DR
- Status: **IMPLEMENTED_WITH_RISKS** (resumed session; inherited prior pass's code, verified + fixed + documented everything end-to-end)
- Files changed (mine): `bin/pos-docker-vbox` (3 conformance fixes) · `DOC/howto/docker.md` · `DOC/POS.md` · GEN blocks. Inherited uncommitted from prior passes: micro-fix in both share clients + full categorized UI/flag parser in vbox (all re-verified here). T7's `lib/common.sh`/`DOC/DEV.md`/`DOC/howto/share.md` edits pre-date this task — untouched.
- Flag contract: `create <name> [image] [--dir <path>]… [--device </dev/node>]… [--gpu] [--port H:C]… [--cpus N] [--memory SIZE] [--network MODE]`; zero-flag invocations byte-compatible with HEAD (proven vs clone)
- Gates: bash -n ×3 ✅ · make gen idempotent ✅ · make check OK ✅ · make lint **0 FAIL, 0 WARN** ✅
- Probes: **107 assertions, 0 failures** — all 10 Designer §8 scenarios incl. EOF-at-every-depth (discard line exactly once), byte-compat vs HEAD, review-n-preserves-edits, unpersist guidance + session survival on both clients

REPORT_PATH: ./reportAgents/2026-08-23-builder-t8-vbox-categories.md

## Step −1 (this session): resume audit of inherited implementation [DONE]
- Found the working tree carrying the prior T8 pass uncommitted (Steps 0–3 below are its work, re-verified not blindly trusted). Baselines captured fresh to `/tmp/opencode/t8-resume/base/` (`vbox-head.sh` = git HEAD pre-T4-era verb for byte-compat, plus worktree snapshots of all three files).
- Report corrected: prior Step 3 described an older `cc_eof()` stdin-reprobe design; the code evolved to streak-based arbitration (`cc_quit_tick`). Text below reflects the CODE, not the stale prose.
- Three spec-conformance defects identified by inspection (fixed in Step 3b):
  1. Teardown-line hole: menu-lib-signal teardowns (double-quit streak ⇒ rc 77) returned to the orchestrator WITHOUT the mandatory single `[!] setup discarded — nothing was created` line (contract: file header + spec §3 + probe scenario 5).
  2. Name-prompt EOF used a fragile `read -t 0.05` stdin re-probe; a pty-injected Ctrl-D took the silent path, contradicting scenario 5's "discard line printed exactly once at every depth".
  3. `set -e` race: `CC_CAND_LABELS+=("$(cc_node_label …)")` — a vanishing node between listing and labeling aborts the whole tool (bare assignment propagates substitution failure).

## Step 0: Read-in + baseline [DONE]
- Read designer spec (§1–§9), T4-P2 menu pattern report, T7 fix report, `lib/menu-lib.sh`, all three target files, DEV.md lint gate.
- Ratified answers applied: long-only flag spellings; keep verb's `Enter now?` tail; list ALL block devices with `(system disk — careful)` label.

## Step 1: unpersist micro-fix (both share clients) [DONE]
- smb `cmd_unpersist` (:437–450): not-found branch → `return 0` (was `exit 0`, killed interactive sessions); when `persisted_smb_at` finds a Type=cifs unit whose `Where=` matches (escape-drift case) prints warn + guidance naming the unit instead of a bare line. Mirrors T7's unmount approach (same helper, same style).
- nfs `cmd_unpersist` (:201–213): same shape via existing `persisted_nfs_at`; bare `warn "No systemd mount unit…"` preserved for the truly-nothing case.
- `bash -n` ×2 green. Targeted probes in Step 6.

## Step 2: vbox create verb — flag contract [DONE]
- Parser extended additively: `--dir`(repeatable→first=primary lab dir, rest extra mounts), `--gpu`, `--device`(repeatable, `/dev/*` enforced), `--port`(regex `^[0-9]+(:[0-9]+){1,2}$`), `--cpus`(`^[0-9]+(\.[0-9]+)?$`), `--memory`(`^[0-9]+(b|k|m|g|mb|gb)?$`), `--network`(free value). Unknown `-…` token → `[!] Unknown option: …` rc 1. Missing values reuse legacy `Missing value for X` + rc 1.
- argv emission order (fixed): `-it --name --label [gpu] [devices] [ports] [--cpus] [--memory] [--network] -v primary [-v extras] -w IMAGE bash`. Zero-new-flag invocation reproduces legacy argv byte-for-byte (stub-log diff).
- usage() heredoc rewritten; `# POS_FLAGS:` header added for completion regen. Only legacy-surface delta: usage text.

## Step 3: categorized create UI (inherited complete) [DONE]
- Name prompt → hub (`menu_run`, live basket counts) → categories: Image quick-picks (+Other free-ref, whitespace rejected), GPU paths A/B/C (exact §5 wording incl. toolkit probe), Host devices (lsusb→usbfs nodes, ttyUSB/ttyACM/video globs, `/dev/snd` single entry, lsblk disks+partitions w/ system-disk label; perm-restricted labelled not filtered), mounts (validated absolutes, same-path convention), ports (dup-host-port reject), CPU/RAM (blank=Docker defaults).
- Review screen renders literal plan rows (truncate >6 → `… (+N more)`), composed-command footer, CUDA tip hint-only, single `confirm "Create?" n`; 'n' → hub preserving edits.
- Basket mechanics: loop-of-single-picks per §4 verbatim strings; dedupe across sources; manual `/dev/*` + stat check.
- Known deviations (justified): (1) mounts/ports/resources/manual-device prompts use raw `read -rp` instead of `menu_ask_value` — ask_value cannot separate empty-answer ("done") from EOF, and §3's binding EOF rule needs that distinction. (2) Path-A info line wording is mine (spec fixed only B/C wording).

## Step 3b: conformance fixes (this session) [DONE]
- Teardown funnel: all helpers unwind silently via rc 77 (`cc_die` removed from `cc_add_loop`, `cc_add_typed_loop`, `cc_category_resources` raw-read sites); orchestrator now prints the single discard line on EVERY teardown (`crc==77` and review `77`). Hub confirmed-discard stays silent by design.
- Name prompt: stdin-reprobe hack deleted; rc 1 (empty answer or dead stream — indistinguishable at a no-default ask) ⇒ loud teardown, satisfying scenario 5 deterministically under any EOF injection.
- `set -e` race hardened in GPU nodes branch (`lbl=$(cc_node_label …) || lbl=$nl`); empty explicit-nodes basket normalizes back to unconfigured instead of a dangling "0 node(s)" hub label.
- Header comment rewritten to describe the shipped discipline accurately.
- Smoke probe (prior rig reused): happy minimal path green; stub-log argv = legacy form byte-for-byte.
## Step 4: docs (howto/docker.md, DOC/POS.md) [DONE]
- `DOC/howto/docker.md` vbox section: two new flag examples in the code block (`--gpu --cpus --memory`, `--device --port`), an "Interactive create" paragraph (flow + categories + fail-closed note), and a `--gpu`/toolkit troubleshooting line.
- `DOC/POS.md`: create row rewritten to the full additive flag contract (repeatable `--dir/--device/--port`, first `--dir` = working dir); menu paragraph now describes the categorized create flow instead of the old three-prompt one.
## Step 5: gates [DONE]
- `bash -n` ×3 (vbox, smb-client, nfs-client): OK
- `make gen`: write OK ×2, byte-compared reruns (`cmp` on AGENT_Context_Project.md + completions/pos.bash) → **idempotent**. Delta vs HEAD exactly: vbox row 261→1125 lines, nfs/smb rows 343→504/576→764 (T7 counts), `_pos_flags[docker-vbox]="--dir --gpu --device --port --cpus --memory --network"` added.
- `make check`: **OK**
- `make lint`: **0 FAIL, 0 WARN**

## Step 6: probe suite (Designer §8 scenarios 1–10 + brief extras) [DONE]

Environment: throwaway stubs under `/tmp/opencode/t8-probe` (prior rig, reused) + `/tmp/opencode/t8-resume` (this session); stubbed `docker/lsusb/lspci/lsblk/findmnt`, fake `/dev` fixture tree via path-patched tool copy; pty via `script` herestrings and the label-matched `t8drv.py` driver for basket flows; isolated HOME; cleaned at the end.

| Scenario | Result | Evidence |
|---|---|---|
| 1 happy minimal (name→Review→y) | ✅ | review rows literal; stub argv == legacy form byte-for-byte; rc 0 |
| 2 full basket (image+gpu+2 devices+mount+port) | ✅ | exact composed argv incl. `-p 8080:80`, extra `-v`, `--gpus all`; `[+]` feedback verbatim ×4; CUDA tip hint-only |
| 3 GPU paths A/B/C | ✅ | all three info lines verbatim; A recommendation highlight; B explicit-nodes steer; empty explicit basket normalizes; C never blocks create |
| 4 basket edit (add3→remove1→clear→re-add) + dup manual | ✅ | driver-run: `[+] removed` / clear-all verbatim; final hub count correct; dup manual `[!] already selected — skipped` |
| 5 EOF at EVERY depth (name/hub/mid-add-loop/ask_value/summary) | ✅ | `\x04` injection per depth: discard line printed EXACTLY once, nothing created, rc 0 — all five depths |
| 6 hub-0 reflexive-exit protection | ✅ | `Discard this VM setup?` asked once; basket intact after 'n' |
| 7 scripted create byte-compat vs HEAD | ✅ | zero-flag + `--dir .`: stdout/stderr/rc AND docker argv sequences byte-identical to HEAD clone; ls identical; bogus/noargs/-h differ only by the documented usage-text extension |
| 8 empty detection everywhere | ✅ | lsusb/lspci/lsblk absent from PATH + no nodes: three graceful `[i]` lines, picker degrades to manual-only, full create still completes, no stall |
| 9 invalid inputs recoverable | ✅ | relative dir / missing dir / bad port / portless value / dup host port / bad cpu / bad mem all warn+reprompt; valid values land in review |
| 10 perm-restricted nodes | ✅ | chmod-000 ttyUSB0 offered WITH `(perm-restricted for you — dockerd may still access)` label, selectable; ALL system disks labelled `(system disk — careful)` |

Brief extras:
- scripted new-flags composition: `--gpu --device×2 --port×2 --cpus --memory --network` → argv exact in fixed order ✅
- unknown flag → `[!] Unknown option: …` rc 1; missing values + bad `--device/--port/--cpus/--memory` rejections rc 1 ✅
- review-'n'-preserves-edits ✅ (scenario-4 driver run); EOF-at-hub discards cleanly ✅ (S5-hub)
- unpersist micro-fix, BOTH clients: not-found branch survives menu session (menu redraws, rc 0), bare line preserved; escape-drift case prints actionable guidance naming the unit (`custom-named.mount` / `other.mount`) ✅

Totals: vbox suite 72✓ + S4-driver 9✓ + compat/clients suite 26✓ = **107 assertions, 0 failures**.

Probe-harness notes (not tool bugs, recorded for reproducibility): herestring-EOF blocks rather than signals pty-EOF so `\x04` bytes were used for scenario 5; `ptyrun` writes the stub log next to the output file; host `lsusb/lspci/lsblk` leak through PATH fallback unless excluded; manually-added devices ARE excluded from later candidate lists (dedupe working as designed), which shifts picker indices between iterations.

## Step 7: final verification + cleanup [DONE]
- Final gates re-checked after last edit: `bash -n` ×3 OK · `make gen` idempotent · `make check` OK · `make lint` **0 FAIL, 0 WARN**.
- `git status` audit: only allowed files (+ T7's pre-existing uncommitted edits to `lib/common.sh`, `DOC/DEV.md`, `DOC/howto/share.md`, which I did NOT touch).
- Probe environments removed (`/tmp/opencode/t8-resume` scratch, prior-rig regenerated fixtures); baselines discarded with them.
- Note: `AGENT_TODO.md` maintenance deferred — outside this task's allowed file list and no commits permitted.

## Scope compliance & handoff
Status: IMPLEMENTED_WITH_RISKS (risks = inherited-unverified-until-now prior code + one design conflict, below)

Approved scope: categorized create flow for `bin/pos-docker-vbox` per Designer spec §1–§8 + ratified answers; unpersist micro-fix in both share clients; `DOC/howto/docker.md` vbox section; `DOC/POS.md` vbox wording if needed; GEN regen. No commits.

Changes made (this session): resume audit of the prior pass's uncommitted implementation; 3 conformance fixes in `bin/pos-docker-vbox` (teardown-line funnel, name-prompt EOF determinism, `set -e` relabel race + empty-GPU-basket normalization); docs (howto/docker.md section, POS.md row+paragraph); GEN regen; full gate + probe verification of the combined result including the inherited micro-fix.

Flag contract (category → emitted flags):
| Category | UI picks | Verb flags emitted |
|---|---|---|
| Image & distro | quick-picks / free ref | positional `<image>` |
| GPU/Nvidia path A | `--gpus all` | `--gpu` |
| GPU/Nvidia path B/C | node picks / manual | `--device </dev/nvidia*>…` (repeatable) |
| Host devices | usb/serial/video/snd/disks/manual | `--device <node>…` |
| Host dir mounts | typed absolute paths | `--dir <path>` (first = working dir `~/<name>` passed explicitly; mounts appended as repeatable `--dir`) |
| Ports | typed H:C pairs | `--port H:C…` |
| CPU/RAM | blank=Docker defaults | `--cpus N`, `--memory SIZE` |
| Network | v2 (not in UI) | `--network MODE` (verb supports it already) |

Deviations from spec letter (all justified):
1. ro/rw mount choice: the dispatching brief's summary mentioned a "ro/rw choice", but the authoritative spec (§2 table, §3 mechanics, §8 flag contract) defines same-path rw-only mounts with no ro/rw encoding anywhere — followed the spec. If ro/rw is wanted it needs a verb contract addition (`-v p:p:ro`) ⇒ new Architect decision required.
2. Raw `read -rp` instead of `menu_ask_value` for typed loops/resources: ask_value cannot distinguish empty-answer ("done") from EOF; §3's binding EOF rule requires the distinction (inherited deviation, kept).
3. Path-A GPU info line wording is implementation-authored (spec fixed only B/C wording verbatim).
4. Teardown arbitration is streak-based (two consecutive quits) because menu-lib primitives cannot distinguish typed-q from dead-stream EOF; raw reads tear down immediately. Name-prompt failure (empty or dead — indistinguishable at a no-default prompt) tears down loudly with the single discard line.

Out-of-scope changes made by me: none.

Remaining risks:
1. Review-'n' counts as quit tick #1, so an immediate hub-quit afterwards tears down without the protective confirm — consistent with the documented streak rule but worth Reviewer awareness.
2. `--network` has no UI surface (spec OPTIONAL v2); verb support verified by composition probe only.
3. The micro-fix guidance text names the unit file; users must cross-reference `list` output (matches T7 style).

Recommended next agent: Reviewer
Reason: implementation complete, all gates green, 107/107 probe assertions pass; adversarial review of the conformance-fix funnel, the streak-arbitration edge cases, and the ro/rw spec-conflict resolution is the remaining acceptance step before commit.

Changes made by Builder: see Steps 3b–5 above plus verification of inherited Steps 1–3.

REPORT_PATH: ./reportAgents/2026-08-23-builder-t8-vbox-categories.md