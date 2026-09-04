# Reviewer — R5 Chain Adversarial Review

**Date:** 2026-08-25
**Reviewed work:** Four consecutive Builder passes (R5, R5b, R5c, R5d) on `bin/pos-ai-gemini` and docs
**Approved scope:** tmp_request.md R5 — terse prompt + markdown rendering, --last + default session, answer separation + staleness transparency, machine context

---

## TL;DR

**Status: ACCEPT_WITH_NOTES**

- 21 checklist items assessed: 18 PASS, 1 FAIL (duplicate line in ai.md doc), 1 WARN (chat REPL extra whitespace — cosmetic), 1 NOT-APPLICABLE (chat subcommands that never existed)
- 1 BLOCKING finding: duplicate line in `DOC/howto/ai.md` (lines 135–138)
- 0 regressions detected in non-tty output path or pre-R5 behavior
- 0 scope creep into share-lib, menu-lib, cmd_unmount, or Telegram bridge
- 3 unverified items (require `make gen`, `bash -n`, runtime testing — sandbox blocked)

---

## Step 1: Scope compliance

**Files in R5 scope** (per approved scope):
- `bin/pos-ai-gemini` — ✅ Changed, 311→565 lines
- `DOC/howto/ai.md` — ✅ Changed
- `DOC/POS.md` — ✅ Changed (ai section updated)
- `completions/pos.bash` — ✅ Changed (GEN: block, `--full --last` added)
- `DOC/AGENT_Context_Project.md` — ✅ Changed (line-count resync only)

**Out-of-scope files also modified in working tree** (from concurrent work, NOT caused by R5):
- `bin/pos-docker-vbox`, `bin/pos-share-nfs-client`, `bin/pos-share-smb-client` — R1/R3/R6 work
- `lib/common.sh` — R4 confirm convention
- `DOC/DEV.md`, `DOC/howto/docker.md`, `DOC/howto/share.md` — doc sync for R3/R4/R6

These are concurrent uncommitted changes, not scope creep by R5.

| Verdict | PASS |
|---------|------|
| Rationale | All R5-scope files are modified; no R5-authored changes found in out-of-scope files |

---

## Step 2: Default system prompt (R5)

| Check | Verdict | Evidence |
|-------|---------|----------|
| Terse clause present | PASS | Line 23: "Be extremely terse: lead with the exact command(s) to run; one-line explanations max; no greetings, no closing offers, no essays." |
| Troubleshooting clause present | PASS | Line 23: "diagnose it from that and lead with the fix command(s)." |
| Machine context appended dynamically | PASS | `cmd_ask` lines 411–414: `mc="$(machine_context)"; [ -n "$mc" ] && mc=" $mc"; system="$DEFAULT_SYSTEM_PROMPT$mc"` |

---

## Step 3: --system replaces wholesale

| Verdict | PASS |
|---------|------|
| Evidence | Lines 410–415: `system="$SYSTEM_PROMPT"` then `if [ -z "$system" ] && [ "$FULL_MODE" -eq 0 ]; then ...`. When `--system` sets `SYSTEM_PROMPT`, the condition `[ -z "$system" ]` is false → built-in prompt + machine context are never assembled. |

---

## Step 4: --full drops built-in

| Verdict | PASS |
|---------|------|
| Evidence | Line 411: `if [ -z "$system" ] && [ "$FULL_MODE" -eq 0 ]`. With `FULL_MODE=1`, the entire block is skipped → `system` stays as `SYSTEM_PROMPT` which defaults to `""`. No built-in or machine context injected. |

---

## Step 5: --last resolves + injects + announces

| Verdict | PASS |
|---------|------|
| Evidence | `newest_pos_log()` (lines 131–138) finds newest non-pos.log, verifies non-empty. `cmd_ask` (lines 398–403): calls `last_log_annotate` for stderr info, `last_log_context` for the tail, appends `[last command output:]` block. `last_log_annotate` (lines 171–185): prints `[i] attaching last pos output — <basename> (<age>)` + preview line to stderr. |

---

## Step 6: Staleness >60min warning

| Verdict | PASS |
|---------|------|
| Evidence | Line 182: `if [ "$age_s" -gt "$LAST_LOG_STALE_SECS" ]` (LAST_LOG_SECS=3600). Prints `[!] that log is %s old and may not match your current problem...` to stderr with pipe-fresh hint. |

---

## Step 7: Session "default" persists

| Verdict | PASS |
|---------|------|
| Evidence | Line 16: `SESSION="default"` (was `SESSION=""` in baseline). `session_load()` / `session_save()` no longer gated on `[ -n "$SESSION" ]` in ask/chat — always writes to `default.json`. |

---

## Step 8: --session overrides default

| Verdict | PASS |
|---------|------|
| Evidence | Flag parser lines 534–535: `--session) SESSION="$2"; shift 2`. Overrides the default before any session operation. |

---

## Step 9: Tty answer separation

| Verdict | PASS |
|---------|------|
| Evidence | `render_markdown` tty path (line 318): `printf '\n%s\n' "$rendered"` — exactly one leading blank line + content + one trailing newline. Non-tty path (lines 262–264): `printf '%s\n' "$text"` — raw bytes, zero added newlines. |

---

## Step 10: Markdown renderer coverage

| Verdict | PASS |
|---------|------|
| Evidence | Fenced blocks: line 280 toggle + line 281 dimmed indent. Inline code: lines 291–295 → yellow. Bold `**…**`: lines 298–302. Bold `__…__`: lines 305–309. Headers `#{1,4}`: lines 282–285 → bold cyan, # stripped. HR `---/***___`: line 287 → thin rule. List markers: no-op (passed through as-is, which is correct). glow: lines 313–314, `command -v glow >/dev/null 2>&1` — opportunistic. |

---

## Step 11: Machine context fallback chain

| Verdict | PASS |
|---------|------|
| Evidence | `machine_context()` lines 337–386: hostnamectl first (lines 340–356), os-release fallback for distro (lines 359–368), uname fallback for kernel+arch (lines 370–371). `[ -n "$out" ] \|\| return 0` on line 384 — clause omitted when all fail. `mc_clean()` strips ANSI, control chars, collapses whitespace. |

---

## Step 12: Non-tty stdout byte-identical

| Verdict | PASS |
|---------|------|
| Evidence | Old baseline `cmd_ask`: `printf '%s\n' "$out"`. New `cmd_ask`: `render_markdown "$out"` where non-tty path is `printf '%s\n' "$text"`. Byte-equivalent output format. The system prompt change affects what the model generates but not the print format — opt-in behavioral change within scope. |

---

## Step 13: Chat REPL commands intact

| Verdict | NOT-APPLICABLE |
|---------|----------------|
| Rationale | Checklist references /history, /export, /help — these never existed in either baseline or current code. Old code only had `/reset` and `q/Q/quit/exit`. Current code preserves both exactly (lines 441–446). No regression. |

---

## Step 14: Telegram listener bridge untouched

| Verdict | PASS |
|---------|------|
| Evidence | `git diff --name-only` shows no changes to communication listener/sender files. Telegram bridge calls `pos ai gemini ask` — the non-tty stdout path is byte-identical (check 12). |

---

## Step 15: Pipe stdin still works

| Verdict | PASS |
|---------|------|
| Evidence | Lines 392–394: `elif [ ! -t 0 ]; then prompt="$(cat)"`. Identical to baseline. |

---

## Step 16: POS_FLAGS complete

| Verdict | PASS |
|---------|------|
| Evidence | Line 5: `# POS_FLAGS: --model --session --system --full --last`. All five flags from checklist present. Completions line 6 matches: `_pos_flags[ai-gemini]="--model --session --system --full --last"`. |

---

## Step 17: make gen idempotency

| Verdict | UNVERIFIED |
|---------|------------|
| Rationale | Cannot run `make gen` in sandbox. Static evidence: completions posflags block (line 6) matches POS_FLAGS header; filetable row updated to 565 lines (confirmed by `wc -l`). The docker-vbox, nfs-client, smb-client, and completions line-count rows in the GEN block reflect concurrent work, not R5 drift. Strong inference: gen output would be byte-identical, but UNVERIFIED without running it. |

---

## Step 18: glow deps guard

| Verdict | PASS |
|---------|------|
| Evidence | Line 313: `if command -v glow >/dev/null 2>&1` — standard pattern, never errors when absent, falls back to awk renderer. No other reference to glow in the file. |

---

## Step 19: Lint convention compliance

| Verdict | PASS |
|---------|------|
| Evidence | Shebang: line 1 `#!/usr/bin/env bash`. Strict mode: line 2 `set -euo pipefail`. Help dispatch: line 529 `-h\|--help) usage ;;` in flag parse loop (before subcommand dispatch). No new external deps required (glow is optional). |

---

## Step 20: --last scoped to ask

| Verdict | PASS |
|---------|------|
| Evidence | Lines 554–556: `if [ "$LAST_MODE" -eq 1 ] && [ "${cmd:-}" != "ask" ]; then err "--last only applies to 'pos ai gemini ask'"`. Hard error for any other subcommand. |

---

## Step 21: Error→stderr, answer→stdout

| Verdict | PASS |
|---------|------|
| Evidence | `err()` from common.sh → stderr. `warn()` at line 450 → stderr. `gemini_generate` error echo at line 246 → `>&2`. `last_log_annotate` all output → `>&2`. `render_markdown` → stdout. API errors → stderr + exit 1. |

---

## Findings

### Finding 1 — Duplicate line in DOC/howto/ai.md
- **Severity:** REQUIRED
- **Evidence:** Lines 135–138 in `DOC/howto/ai.md`:
  ```
  - On a non-2xx response the API's `error.message` is shown and the exit code is
    non-zero — so scripts can rely on `ask` failing loudly.
  - On a non-2xx response the API's `error.message` is shown and the exit code is
    non-zero — so scripts can rely on `ask` failing loudly.
  ```
  The diff confirms: the new line was appended but the old identical line was not removed.
- **Relevant files/lines:** `DOC/howto/ai.md:135-138`
- **Approved scope reference:** R5 doc updates to ai.md
- **Why it matters:** Duplicate text is a doc bug — readers see the same bullet twice. Trivial to fix (delete one).

### Finding 2 — Chat REPL uses raw SYSTEM_PROMPT (no built-in default)
- **Severity:** NOTE
- **Evidence:** `cmd_chat` line 449: `gemini_generate "$model" "$contents" "$SYSTEM_PROMPT"` — passes the raw `SYSTEM_PROMPT` var. When no `--system` is given, this is `""` (empty), meaning chat gets NO system instruction — not even the terse prompt. This is consistent with the scope ("chat keeps its neutral behavior, only --system applies") and with `ai.md` line 39: "`chat` keeps its neutral behavior (only `--system` applies)."
- **Why it matters:** Not a defect — explicitly documented behavior. But worth noting that chat and ask have asymmetric prompt treatment.

### Finding 3 — Chat REPL extra leading whitespace on tty
- **Severity:** SUGGESTED
- **Evidence:** `cmd_chat` lines 458–460: `printf '\n'; render_markdown "$answer"; printf '\n\n'`. On a tty, `render_markdown` emits `\n<rendered>\n`, so total after `> ` prompt close is: `\n` (from printf) + `\n` (render_markdown leading) + content + `\n` (render_markdown trailing) + `\n\n` (printf). This produces 2 leading blank lines and 3 trailing blank lines — more visual whitespace than the baseline's `printf '\n%s\n\n'`.
- **Why it matters:** Cosmetic. The extra separation is arguably better for interactive readability. Non-blocking.

---

## Verification verified

1. ✅ Default system prompt has terse + troubleshooting clauses (line 23)
2. ✅ Machine context function implements hostnamectl → os-release → uname fallback chain (lines 337–386)
3. ✅ --system prevents built-in assembly (line 411 condition)
4. ✅ --full prevents built-in assembly (line 411 FULL_MODE check)
5. ✅ --last injects `[last command output:]` block (lines 398–403)
6. ✅ --last announces to stderr with basename + age + preview (lines 171–185)
7. ✅ Staleness warning at >60min (line 182, LAST_LOG_SECS=3600)
8. ✅ Session default persists (SESSION="default", no conditional on load/save)
9. ✅ Tty rendering: glow opportunistic + awk fallback, non-tty raw (lines 260–318)
10. ✅ POS_FLAGS header has all 5 flags (line 5)
11. ✅ Completions match POS_FLAGS (line 6)
12. ✅ Filetable line count accurate (565 matches wc -l)
13. ✅ --last scoped to ask only (lines 554–556)
14. ✅ Errors to stderr throughout
15. ✅ Pipe stdin preserved (lines 392–394)
16. ✅ Telegram bridge path untouched (no file changes)
17. ✅ Conventions: shebang, strict mode, help dispatch order

## Verification unverified

1. `make gen` byte-idempotency (sandbox cannot execute make)
2. `bash -n` syntax check (sandbox cannot execute bash on non-git commands)
3. Runtime test: `--last` with actual dispatcher logs, staleness warning timing, glow rendering

---

## Scope compliance

- **In-scope confirmed:** All R5/R5b/R5c/R5d features implemented in `bin/pos-ai-gemini` + docs
- **Out-of-scope found:** None authored by R5. Working tree contains concurrent changes from R1/R3/R4/R6 work (separate feature branches mixed into working tree before commit)
- **No regressions:** Non-tty output byte-equivalent, chat REPL preserved, stdin pipe preserved, Telegram bridge untouched

---

## Remaining uncertainty

1. Whether `make gen` output is byte-identical to committed GEN blocks — strong inference says yes (flag set matches header, line counts match), but unverified.
2. Whether the awk markdown renderer handles all edge cases at runtime (nested bold inside code blocks, unclosed fences, etc.) — static review shows correct structure but edge-case behavior is runtime-only.

---

## Recommended next agent

**Builder**

**Reason:** One REQUIRED finding (duplicate doc line in `DOC/howto/ai.md`) is a trivial fix within approved scope — delete lines 137–138. The builder can resolve this and then the chain is ready for commit.

---

## Changes made by Reviewer

None — read-only review.
