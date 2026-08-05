#!/usr/bin/env bash
set -euo pipefail
# Repo self-consistency check — run via `make check` (also as a pre-commit hook).
#   bash -n every script, executability, doc<->code sync (gen-docs --check),
#   and a dispatch smoke test. Exit 1 on any failure.

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail=0
note() { echo "  ✗ $*"; }

# ── 1. Syntax ───────────────────────────────────────────────────
for f in bin/pos bin/pos-* lib/*.sh install.sh preinstall.sh postinstall.sh \
         completions/pos.bash scripts/*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" 2>/dev/null || { note "syntax error in $f"; fail=1; }
done

# ── 2. Executability ────────────────────────────────────────────
for f in bin/pos bin/pos-*; do
    [ -x "$f" ] || { note "not executable: $f"; fail=1; }
done

# ── 3. Doc <-> code sync ────────────────────────────────────────
if ! bash scripts/gen-docs.sh --check >/dev/null 2>&1; then
    note "doc/code drift — run 'make gen' and commit the regenerated files"
    fail=1
fi

# ── 4. Dispatch smoke test ──────────────────────────────────────
bash bin/pos --help >/dev/null 2>&1 || { note "pos --help failed"; fail=1; }
bash bin/pos docker --help >/dev/null 2>&1 || { note "pos docker --help failed"; fail=1; }
bash bin/pos bogus >/dev/null 2>&1 && { note "pos bogus should have failed"; fail=1; }

if [ "$fail" -eq 0 ]; then
    echo "check-sync: OK"
else
    echo "check-sync: FAILED" >&2
    exit 1
fi
