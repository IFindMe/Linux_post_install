# tmp_request.md — pending user requests (do not lose)

> Living checklist created 2026-08-23. Update status lines as items land; delete file when all are implemented.

## R1 — SMB client: unmount-by-pick  [IMPLEMENTED in working tree — needs install refresh]
Same interactive UX as NFS client: option 4 lists active SMB mounts to pick (with confirm), typed fallback when none.
NOTE: user transcript shows old typed-prompt behavior because `/usr/local/bin` copy is STALE — none of today's share/menu work has been installed yet.

## R2 — BUG: unmount is SILENT when target is persistent-but-not-active  [OPEN — Detective routed]
Symptom: `Choose: 4` → type `/media/he/12T-smb` → returns to menu with ZERO output (no `[+] Unmounted`, no error), even under sudo. Option 3 lists these under "Persistent (automount):" only ⇒ they are NOT currently mounted; plain umount fails invisibly.
Wanted: surface the real state — e.g. "not mounted (it is a persisted automount) — use option 5 to remove the persistence"; never exit silently. Check NFS client for the same pattern.

## R3 — Docker vbox create: categorized capability picker  [OPEN — Designer routed]
After `VM name:`, replace/augment flat create flow with a CATEGORY list because the option space is large. User wants at least:
- Nvidia/GPU integration (device passthrough)
- Ability to select/mount host devices connected to the machine
- Open to more ideas (designer to propose: mounts, cpu/mem, ports, presets)

## R4 — CONVENTION: [y/N] prompts — Enter defaults to YES  [IMPLEMENTED in working tree (T7)]
confirm() honors default arg (y omitted-default); explicit-'n' destructive sites keep deny-on-Enter; EOF deny fail-closed; case-insensitive Y/n; latent compose `"Y"` bug fixed. Awaiting commit/install.

## R5 — `pos ai gemini ask`: terse CLI answers + markdown rendering  [BUILT — Reviewer pass pending]
- ✓ Default terse system prompt (--system overrides wholesale; --full drops it)
- ✓ Markdown→terminal rendering (glow opportunistic + zero-dep awk fallback); RAW bytes when piped
- ✓ `--last`: attaches pos dispatcher log OR captured output (see R7); stderr announces which source + age; >60min staleness warning; no-log → pipe recipe error
- ✓ Troubleshooting clause in default prompt (pasted error → diagnose + fix first)
- ✓ Session "default" always on for ask/chat without --session; bridges untouched
- ✓ Answer separation on tty (leading blank line; piped output byte-identical)
- ✓ Machine context clause (hostnamectl → os-release+uname fallback) appended to default prompt only
- ✓ `capture` subcommand: runs any command, tees output to last_cmd_output for --last
- ✓ `--last` fallback chain: pos logs (priority) → last_cmd_output (fallback)
- ✓ Optional shell hook (`lib/pos-ai-hook.sh`) for auto-capture via .bashrc
- Model default remains gemini-2.5-flash when nothing set (flag > config > hard default)
- PENDING: one consolidated adversarial review over the whole R5 chain before acceptance

## R6 — `pos ai openrouter`  [BUILT — needs Reviewer pass]
New tool cloned from gemini, adapted for OpenRouter REST API (OpenAI-compatible format).
- Same subcommands: ask, chat, sessions (+ capture via R7)
- Same features: --last, --system, --full, default session, tty rendering, machine context
- API: Bearer auth, OpenAI message format, `choices[0].message.content` response
- Config: `pos config ai-openrouter` → `ai-openrouter.env` (OPENROUTER_API_KEY, OPENROUTER_MODEL)
- Default model: `openrouter/auto` (picks best model automatically)
- Sessions separate from gemini (`~/.local/share/linux_post_install/ai-openrouter/`)
- PENDING: Reviewer pass before acceptance

## R7 — `--last` captures ANY command output  [BUILT — needs Reviewer pass]
- ✓ `capture` subcommand on both gemini + openrouter: runs cmd, tees to `last_cmd_output`, shows on terminal
- ✓ `--last` fallback: pos logs first → `last_cmd_output` second
- ✓ `lib/pos-ai-hook.sh`: optional shell hook for .bashrc auto-capture (exec > >(tee ...), 1MB cap)
- PENDING: Reviewer pass before acceptance

## R6+R7 — PAUSED: Phase-2-menu follow-ups (T7/T8) awaiting consolidated Reviewer pass
T7 (unmount fixes + confirm convention) done; T8 (vbox categorized create, 107 assertions green) done; Reviewer pass + commit/push deferred until user resumes.

## Housekeeping reminders
- Working tree holds UNCOMMITTED + UNINSTALLED work. To use anything new, refresh installed copies:
  ```
  sudo install -m 755 bin/pos-share-* bin/pos-docker-vbox bin/pos-ai-openrouter /usr/local/bin/
  sudo install -m 644 lib/menu-lib.sh lib/share-lib.sh /usr/local/bin/
  ```
- `pos config ai-openrouter` needed to set OPENROUTER_API_KEY before first use
- `lib/pos-ai-hook.sh` is optional — add `source /usr/local/bin/pos-ai-hook.sh` to .bashrc for auto-capture
