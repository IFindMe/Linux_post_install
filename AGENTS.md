# Linux_post_install — Agent Instructions

Personal bootstrap & homelab toolkit for Debian/Ubuntu (Bash). `install.sh` bootstraps a machine; `bin/pos` is the unified CLI.

## External File Loading

CRITICAL: real guidance lives in DOC/. When you encounter a reference below, use your Read tool to load it on a need-to-know basis — do NOT preemptively load all of them. Once loaded, treat the content as mandatory instructions.

- @DOC/AGENT_Context_Project.md — project overview, directory structure, `pos` dispatch table, "How to modify" table. Read FIRST for any non-trivial task.
- @DOC/DEV.md — conventions, verification, and the "Adding a new Feature/App/Tool" checklists. Read before creating or changing code/docs.
- @DOC/POS.md — `pos` CLI reference (dispatcher + every command). Read when working on `bin/pos*` scripts or their docs.
- @DOC/README.md — index of all docs. Read to find the right doc.

## Quick facts

- Each tool is `bin/pos-<category>-<command>`; `bin/pos` dispatches via smart arg matching; bash completion derives from filenames.
- Verify edits with `bash -n` on touched scripts and smoke-test dispatch; keep line counts in `DOC/AGENT_Context_Project.md`'s file table in sync.
