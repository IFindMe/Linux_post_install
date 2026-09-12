# Decision: lib-registration standard is a 3-surface symmetry (install.sh + POS_LIBS + docs)

## Finding (2026-09-12, MAINTENANCE_COMPLETE)

lib/bank-lib.sh (added 41efc91 feat: pos bank) was never registered in install.sh's
phase-2 lib copy list, bin/pos-system-uninstall's POS_LIBS, or the hand-maintained docs.
lib/yt-lib.sh had been added to install.sh (0b76d4d) but missed POS_LIBS. Result: after
`./install.sh`, `pos bank` failed with `/usr/local/bin/bank-lib.sh: No such file or directory`,
and uninstall would leave stale yt-lib.sh. The symmetry gate tests/t-uninstall-manifest.sh
(set-equality of the two lists) was failing.

## Established standard (restored)

Every lib/ file sourced by a bin/ tool MUST be registered in all THREE places:
1. install.sh phase-2 lib copy loop (`for lf in …; do`) → ships to /usr/local/bin,
2. bin/pos-system-uninstall `POS_LIBS` array (same set, backslash-continuation style),
3. hand-maintained docs: DOC/SCRIPTS.md phase-2 table row + DOC/AGENT_Context_Project.md
   phase-2 lib list AND its hand-maintained filetable row (above GEN:START filetable,
   with real `wc -l` count).

Validator: tests/t-uninstall-manifest.sh (must stay green; it enforces set equality and
that every listed lib exists). Never edit GEN:START/GEN:END blocks by hand — run make gen.