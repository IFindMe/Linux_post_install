# Linux_post_install — Agent Instructions

Personal bootstrap & homelab toolkit for Debian/Ubuntu (Bash). `install.sh` bootstraps a machine; `bin/pos` is the unified CLI.

## External File Loading

CRITICAL: real guidance lives in DOC/. When you encounter a reference below, use your Read tool to load it on a need-to-know basis — do NOT preemptively load all of them. Once loaded, treat the content as mandatory instructions.

- @DOC/AGENT_Context_Project.md — project overview, directory structure, `pos` dispatch table, "How to modify" table. Read FIRST for any non-trivial task. It opens with a **Document Map** (auto-generated line ranges for every section) — use it to jump straight to the relevant section.
- @DOC/DEV.md — conventions, verification, and the "Adding a new Feature/App/Tool" checklists. Read before creating or changing code/docs.
- @DOC/POS.md — `pos` CLI reference (dispatcher + every command). Read when working on `bin/pos*` scripts or their docs.
- @DOC/README.md — index of all docs. Read to find the right doc.
- @DOC/HOWTO.md — hands-on per-category guides (network, docker, media, system, ssh, usb, communication, entertainment). Read when a task is about *using* `pos` day-to-day rather than extending it.

## Quick facts

- **Tool model:** `bin/pos-<category>-<command>`, or **category-less** `bin/pos-<cmd>` for dispatcher/dev-level commands that fit no category (`pos-config`, `pos-tree`) — they dispatch like any tool and show with an empty category in the generated tables. `bin/pos` dispatches by longest-prefix arg matching. New tools are auto-discovered but must be executable (`100755`) and carry a `# POS: <cat> <cmd> — <desc>` header right after the shebang; `make gen` only uses the text after the first `— ` (the leading words are convention-only), so keep the one-line description concise. `# POS_FLAGS:` / `# POS_SUBCMDS:` / `# POS_CONFIG:` headers feed tab-completion and the `pos config` scope registry. A missing `# POS:` header hard-fails `make gen`.
- **Generated code:** blocks between `GEN:START`/`GEN:END` markers in `DOC/AGENT_Context_Project.md` (tree, dispatch, selfcontained, filetable, docmap) and `completions/pos.bash` (flags, subcmds, config scopes) are `make gen` output — never hand-edit them. After touching `bin/pos-*`, run `make gen` then `make check` (bash -n + exec-bit check + doc-sync gate + dispatch smoke; definition of done). Hand-maintained, not gen-checked: `DOC/POS.md`, the line-count rows above the filetable marker (e.g. `lib/common.sh`), `bin/pos` usage() EXAMPLES, root README.
- **Stdin gotcha:** any tool that reads stdin must be added to `INTERACTIVE_CMDS` in `bin/pos` — otherwise the logging `tee` pipe hangs on (or swallows) the prompt.
- **Deps:** apt packages → `PACKAGES` array in `preinstall.sh`; non-apt/manual installers (e.g. `usbsrv`) → `command -v <bin> || err "…"` guard inside the tool, never in PACKAGES.
- **Secrets:** never commit keys/tokens. `config/authorized_keys` and `config/rclone.conf` are gitignored; runtime tool config is `~/.config/linux_post_install/<tool>.env` (chmod 600, env-var precedence). Mask tokens in `config` output.
- **entertainment plugins:** standalone scripts in `entertainment/` that must NOT source `lib/common.sh` — stdout is the message that gets sent to Telegram (helper chatter would leak into it). Markers: `# POS_PLUGIN: <name>` + `# POS_KEYS:` declarations.
- **Conventions:** `set -euo pipefail`, `-h|--help` via case, idempotent writes, use `run`/`spawn` helpers (respect `$DRY_RUN`), `make hook` installs the opt-in pre-commit gate.
- Maintain `AGENT_TODO.md` (Now / Next / Later / Done): when you finish a task, move it to **Done** (dated) in the same commit.
