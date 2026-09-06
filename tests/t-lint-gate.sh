#!/usr/bin/env bash
set -euo pipefail
# t-lint-gate.sh — convention lint gate behavior:
#   positive: `make lint` on the real tree passes with "0 FAIL, 0 WARN";
#   negative: a planted tool without a `# POS:` header and a planted app
#     without an uninstall function are both reported by name (rc != 0).
# The negative case runs in a temp tracked-file copy so the dirty tree state
# cannot mask or fabricate violations.

run_test() {
    require_cmd make "lint gate" || return 0

    local lint="$ROOT/scripts/lint-conventions.sh"

    # ── positive: real tree lints clean ──
    test_run timeout 120 bash "$lint"
    check_rc "lint on real tree exits 0" 0 "$TR_RC"
    check_contains "lint reports zero failures" "0 FAIL, 0 WARN" "$TR_OUT"

    # ── negative: planted violations are caught and named ──
    local sandbox copy
    sandbox="$(mksandbox lint-gate)"
    copy="$sandbox/tree"
    tracked_tree_copy "$copy" || { skip_case "lint gate" "tracked tree copy failed"; return 0; }

    # plant 1: executable tool without a # POS: header
    cat > "$copy/bin/pos-zz-test-broken" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
usage() { cat <<HELP
Usage: pos zz-test-broken
HELP
exit 0
}
case "${1:-}" in -h|--help) usage ;; esac
EOF
    chmod +x "$copy/bin/pos-zz-test-broken"

    # plant 2: apps script without an uninstall case/function
    mkdir -p "$copy/apps/zztest"
    cat > "$copy/apps/zztest/zztest.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "zztest installed"
EOF

    # lint resolves its own ROOT from $0 and `cd`s there — so run the COPY's
    # lint (relative path) to lint the copy, not the real repo
    ( cd "$copy" && timeout 120 bash scripts/lint-conventions.sh ) >"$sandbox/lint.out" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        printf '  FAIL  lint did not reject planted violations (rc 0)\n'
    else
        printf '  PASS  lint rejects planted violations (rc %s)\n' "$rc"
    fi
    check_contains "violating tool named in lint output" "pos-zz-test-broken" "$(cat "$sandbox/lint.out")"
    check_contains "violating app named in lint output" "zztest" "$(cat "$sandbox/lint.out")"
}