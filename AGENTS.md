# Linux_post_install — Agent Instructions

Personal bootstrap & homelab toolkit for Debian/Ubuntu (Bash). `install.sh` bootstraps a machine; `bin/pos` is the unified CLI.

## External File Loading

CRITICAL: real guidance lives in DOC/. When you encounter a reference below, use your Read tool to load it on a need-to-know basis — do NOT preemptively load all of them. Once loaded, treat the content as mandatory instructions.

- @DOC/AGENT_Context_Project.md — project overview, directory structure, `pos` dispatch table, "How to modify" table. Read FIRST for any non-trivial task. It opens with a **Document Map** (auto-generated line ranges for every section) — use it to jump straight to the relevant section.
- @DOC/DEV.md — conventions, verification, and the "Adding a new Feature/App/Tool" checklists. Read before creating or changing code/docs.
- @DOC/POS.md — `pos` CLI reference (dispatcher + every command). Read when working on `bin/pos*` scripts or their docs.
- @DOC/README.md — index of all docs. Read to find the right doc.

## Quick facts

- Each tool is `bin/pos-<category>-<command>`; `bin/pos` dispatches via smart arg matching; bash completion derives from filenames.
- Verify edits with `make check` (runs `bash -n` + the generated-doc sync gate). Generated sections (dispatch table, file table, line counts, completion flags, this doc's Document Map) are code-derived — after changing `bin/pos-*`, `lib/*`, or `completions/`, run `make gen` and commit the refreshed output.
