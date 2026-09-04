# Builder Report — T5 (Phase 2, final piece): migrate `bin/pos-system-firewall` menu to repo-standard interaction mechanics

## TL;DR
- Status: **IMPLEMENTED** — mechanics-only migration done, zero semantic drift proven against byte-baselines.
- Files changed: `bin/pos-system-firewall` ONLY (308→325 ln; +59/−42 vs pre-edit tree == HEAD for this file) · GEN row via `make gen` (`DOC/AGENT_Context_Project.md` filetable 308→325). DOC/POS.md untouched (row describes semantics — confirm/dry-run/history/notify — not stream mechanics; nothing became inaccurate).
- Mechanics: new tool-local seam `tty_read()` = `read -rp … < /dev/tty` + EOF/no-TTY fail-closed handler (2-line pointer → exit 1); menu heredoc wrapped `{ … } >&2`; `prompt_ipver` de-command-substituted so its EOF exits the whole tool gracefully.
- Library adoption: **none** — justified per brief escape clause ("semantic equivalence wins"): no menu-lib primitive is a pure drop-in here (details Step 0).
- Gates: `bash -n` ✓ · `make gen` idempotent ✓ · `make check` OK ✓ · `make lint` **0 FAIL, 0 WARN** ✓.
- Probes (pty harness, stubbed ufw/systemctl): menu render byte-identical after relocating stdout→stderr; flow outputs byte-equal ×6 scenarios; prompt streams byte-equal; abort-before-mutate with ZERO ufw calls; RESET wrong-word aborts; non-tty exits in 36 ms rc1 (no hang); `--help` byte-identical; root gate identical. No commits.

## Step 0: Scope confirmation + plan [DONE]
- Approved scope: `bin/pos-system-firewall` ONLY (+ DOC/POS.md row wording only if it describes interaction mechanics; GEN regen). Mechanics-only, zero semantic change.
- Plan inputs read: explorer survey E-001/E-002 (stdout-rendered firewall vs stderr+/dev/tty patterns A/B), T1 report (menu-lib contracts), T2 report (byte-baseline + pty-harness discipline), `lib/menu-lib.sh`, target file (308 ln).
- Library adoption decision: **none** — `menu_run`/`menu_pick`/`menu_ask_value` all change rendering/prompt/flow wording (not drop-ins); `menu_guard` checks `[ -t 0 ]` which would REFUSE legitimate runs where stdin is redirected but a controlling TTY exists (firewall has no CLI verbs, so the menu is its only interface — refusing could only reduce capability). Per-read fail-closed on `/dev/tty` gives the required no-hang guarantee without the guard. Semantic equivalence wins per brief.
- Key mechanic: single tool-local seam `tty_read <prompt> <var>` = `read -rp … < /dev/tty` + EOF handler (pointer message → exit 1, fail-closed like menu_guard semantics). `/dev/tty` open failure (cron, no controlling terminal) also lands in the handler — graceful, never hangs.
- Errexit trap found: `apply_for_versions` uses `ipver=$(prompt_ipver)` — inside command substitution an EOF `exit 1` would only kill the subshell (parent dies silently via errexit, pointer notwithstanding). De-substituted to direct call assigning `ipver` through bash dynamic scoping (`local ipver` kept) — capture mechanism only, value semantics identical. Necessary to make item 2's "each EOF-checked with graceful exit" true for EVERY read.
- Color gating check: grep shows NO `[ -t … ]` checks and no color variables in the tool (plain echo, own inline log/warn/err) → brief item 4 is N/A (verified again post-edit).
- Dispatcher membership / headers / verbs: untouched by design (stays in `INTERACTIVE_CMDS`; no `POS_SUBCMDS` exists; `# POS:` header unchanged).

## Step 1: BEFORE baselines [DONE]
- Harness `/tmp/opencode/t5-fw/` (throwaway): stub `ufw`/`systemctl` logging `$*` to `$T5_UFW_LOG`; `NOTIFY_PLATFORM=probe-noop` (notify sender not found → warn+skip, no network — notify.sh:72–75 verified); pty via `script(1)` with inner stream split (runner.sh captures stdout/stderr/rc separately); root gate neutralized ONLY in harness copies (`sed` of :6–10) since uid≠0 — gate itself proven separately below.
- Baselines vs current tree (pre-edit snapshot `firewall.orig`): b1_quit rc0 · b2_abort rc0 + **empty ufwlog** · b3_reset_wrong rc0 · b4_reset_dry rc0 · b6_status rc0 · b7_addboth rc0 (two `>>> ufw …` previews, both Cancelled) · e_eof **silent** rc1 (8-byte stderr = bare `Choose: ` prompt) · nontty (setsid, no controlling tty) rc1 silent · rootgate (unpatched orig) rc1 + "ERROR: Please run as root".
- Stream layout captured: menu block on STDOUT; prompts (`read -p`) on STDERR (stdin=tty in pty). Post-change expectation: menu block byte-moves stdout→stderr; everything else identical.

## Step 2: Implementation [DONE]
Single file `bin/pos-system-firewall`; full diff audited hunk-by-hunk against a pre-edit snapshot (four intents, nothing else):
1. **`tty_read()` seam** (+15 ln after `err()`, :43–56): `read -rp "$prompt" "$@" < /dev/tty`; on failure prints to stderr `[!] Terminal closed or unavailable (EOF) — stopping; nothing more was executed.` + `[!] Re-open interactively with: sudo pos system firewall (see --help)` and `exit 1`. Covers both mid-session EOF and open-failure of `/dev/tty` (cron/no controlling terminal — verified in probe (e)).
2. **Menu render → stderr** (:259–277): `{ cat <<'MENU' … MENU } >&2`; heredoc body byte-untouched (only `cat` indented 4 cols + brace lines). Every item, label, order, wording preserved.
3. **22 `read -rp` → `tty_read` conversions** — prompts and target vars verbatim, incl. confirm (:60), RESET gate (:288), default-policy pair, Enter-pager (:323, now explicit `REPLY` = bash's implicit target), all add/delete/status/prompt_ipver reads.
4. **`prompt_ipver` de-substitution** (:118–122, call site :129): was `ipver=$(prompt_ipver)` — inside command substitution an EOF `exit` would only kill the subshell (parent then dies silently via errexit). Now direct call assigning `ipver` through bash dynamic scoping (`local ipver` kept in caller) — capture mechanism only; value semantics identical. Necessary for item 2's "every read EOF-graceful" guarantee.
- Preserved exactly (verified by diff): root gate (:6–10), usage/-h, headers (`# POS:` unchanged; no POS_SUBCMDS existed), log/warn/err, run_cmd confirm+notify-on-mutation logic (:53 area), build_ufw_cmd, ALL ufw invocations incl. unquoted `$ruletext`, case dispatch, HISTORY, goodbye summary, `clear`.
- Color gating: N/A — grep confirms no `[ -t … ]` checks and no color variables in the tool.
- Not touched: `bin/pos` (stays in `INTERACTIVE_CMDS`), dispatcher, completions beyond regen (none needed — no header change), DOC/POS.md.

## Step 3: Gates [DONE]
- `bash -n bin/pos-system-firewall` — OK.
- `make gen` → snapshot → re-run → `cmp` identical ⇒ **idempotent**; my delta = exactly one generated row: `| bin/pos-system-firewall | 308 | … |` → `325` (other diff hunks in those files are T1/T2/T3 tracks' pre-existing uncommitted WIP, untouched by me).
- `make check` — **OK**.
- `make lint` — **0 FAIL, 0 WARN**.

## Step 4: pty-harness probes (after) + parity proofs [DONE]
Harness `/tmp/opencode/t5-fw/` (throwaway; stubs log every ufw/systemctl call to `$T5_UFW_LOG`; `NOTIFY_PLATFORM=probe-noop` keeps notify_send off-network via notify.sh:72–75 not-found path; pty via `script(1)` with inner stdout/stderr/rc split; root gate sed-neutralized in harness copies only — uid≠0 — and separately proven on the real file). Baselines captured BEFORE editing; AFTER runs use identical inputs.

**(a) Render parity** — first render, before-stdout lines 1–14 vs after-stderr lines 1–14:
```
==============================        |   ==============================
   UFW POWER — human friendly         |      UFW POWER — human friendly
==============================        |   ==============================
1) Add rule (port/service/ip/directional)
… (all 8 items + 0) Exit + separator identical)
```
`cmp` clean ⇒ **menu block BYTE-IDENTICAL, relocated stdout→stderr**. Flow outputs byte-equal in all 6 scenarios (b1 quit, b2 enable-abort, b3 reset-wrong-word, b4 dry-reset, b6 status-exec, b7 add-rule both-versions double-abort) once menu lines are stripped from the before side. Prompt streams byte-equal modulo the relocated menu blocks' own leading `\n` (tr-d '\n' comparison clean ×6).

**(b) q/EOF exits** — firewall's exit key is `0`: b1 exits rc0 with goodbye flow intact. EOF (pty closed): renders menu, then
```
Choose: [!] Terminal closed or unavailable (EOF) — stopping; nothing more was executed.
[!] Re-open interactively with: sudo pos system firewall (see --help)     rc=1
```
(no verb list exists to point at — `--help` is the tool's entire CLI surface, so the pointer names it; fail-closed like menu_guard semantics).

**(c) Mutating PROMPT+ABORT** — input `4`,`n`: `[y/N]:` answered `n` → `Cancelled.`; **ufw call log EMPTY before AND after** (zero invocations); loop redraws; exit rc0. Also b7: two rule builds (`both`) each confirmed `n` → zero calls, logs identical pre/post.

**(d) Typed RESET gate** — wrong word (`nope`): `Reset aborted.`, **0** `>>> ufw` previews. Right word under `--dry-run`: `>>> ufw reset` preview → `(dry-run) skipping execution` → history shows it; real-exec path separately proven by b6 (`ufw status` executed via stub, log identical to baseline).

**(e) Non-tty invocation** — `setsid` (no controlling terminal) + stdin `/dev/null`, timeout-guarded:
```
…/firewall.probe.new: line 45: /dev/tty: No such device or address
[!] Terminal closed or unavailable (EOF) — stopping; nothing more was executed.
[!] Re-open interactively with: sudo pos system firewall (see --help)
rc=1  elapsed=36ms (budget 10000ms) — NO HANG
```
(bash's redirect-error line is inherent noise before our handler; pre-change this scenario died SILENTLY via errexit.)

**(f) CLI byte-compat vs pre-change tree (== HEAD for this file)** — `-h/--help` output `cmp` clean; root-gate run (unpatched file): stdout/stderr/rc identical (`ERROR: Please run as root (sudo).` / usage, rc1).

## Final diff summary (this task only)
| File | Change |
|---|---|
| `bin/pos-system-firewall` | 308→325: `tty_read()` seam (+15 ln) · menu heredoc `{ … } >&2` (+2) · 22 read conversions (0 net) · `prompt_ipver` direct-call form (±0 net, +2 comment lines) |
| `DOC/AGENT_Context_Project.md` | GEN only: filetable row 308→325 |
| `reportAgents/2026-08-23-builder-t5-firewall-menu-migration.md` | this report |

## Scope compliance
- In-scope changes confirmed: exactly `bin/pos-system-firewall` + GEN-regen. DOC/POS.md deliberately untouched (row never described stream mechanics; still accurate).
- Out-of-scope changes: **none**. No commits made. Dispatcher/INTERACTIVE_CMDS, headers, verbs, libs, other tools untouched.

## Remaining risks / notes for next agent
- Behavior deltas are exactly the mandated ones: (1) EOF/non-tty now prints the pointer and exits rc1 where it previously died silently via errexit; (2) menu bytes appear on stderr instead of stdout — `pos system firewall > file` now captures only flow output, and `pos system firewall | tee` can no longer swallow the render. Everything else byte-proven equal.
- Under the dispatcher's bare-exec path (INTERACTIVE_CMDS membership kept) fd0 already is the tty, so `/dev/tty` reads are behavior-neutral there; they additionally survive future tee'd/redirected invocation styles.
- AGENT_TODO.md "firewall style-migration" phase item left for Orchestrator to mark Done (file out of my approved scope; T-track precedent).
- Harness removed (`/tmp/opencode/t5-fw/` cleaned post-verification).

REPORT_PATH: ./reportAgents/2026-08-23-builder-t5-firewall-menu-migration.md
