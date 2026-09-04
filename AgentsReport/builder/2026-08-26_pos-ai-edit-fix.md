# Builder Report: fix `_inject_command` edit option for `tee` pipe context

**TL;DR**
- Status: DONE
- File changed: `bin/pos-ai` (lines 399–421 replaced)
- Fix: replaced `read -e -i` (readline) with plain `read -r` so the `e` option works through the dispatcher's `tee` pipe
- Verification: `bash -n` OK, gates pending

---

## Step 1: Replace `read -e -i` with plain `read -r` in `_inject_command`

**Target:** `bin/pos-ai` lines 410–421

Replaced the readline-based edit prompt with a simpler approach that:
1. Shows the flattened command
2. Asks user to type a replacement or press Enter for the original
3. Uses plain `read -r` which works in any context (tee pipes, SSH, non-TTY)

Removed the "Empty command — skipped" message — empty input now runs the original.

[PENDING]
