#!/usr/bin/env bash
set -euo pipefail
# t-uninstall-manifest.sh — install/uninstall symmetry (D-E):
#   - the installed-file manifest (POS_LIBS in pos-system-uninstall) matches
#     install.sh's phase-2 lib list EXACTLY (set equality) and every named
#     lib exists,
#   - scan_tier1() user-unit discovery honors XDG_CONFIG_HOME and only picks
#     pos-* units (never unrelated user units) — extracted function run in a
#     sandboxed XDG_CONFIG_HOME,
#   - plugin removal stays marker-driven (POS_PLUGIN), not hardcoded.

run_test() {
    local sandbox
    sandbox="$(mksandbox uninstall-manifest)"
    local uninstall="$ROOT/bin/pos-system-uninstall"

    # ── static manifest equality ──
    local install_libs uninstall_libs
    install_libs="$(sed -n 's/.*for lf in \(.*\); do.*/\1/p' "$ROOT/install.sh" | head -1)"
    if [ -z "$install_libs" ]; then
        printf '  FAIL  could not extract install.sh lib list\n'
        return 0
    fi
    # POS_LIBS spans one or two lines: "(… \⏎ …)" or "(…)". Strip markers,
    # backslash continuations and parens, join to one token string.
    uninstall_libs="$(sed -n '/^POS_LIBS=(/,/)$/p' "$uninstall" \
        | sed -e '1s/^POS_LIBS=(//' -e 's/[()\\]//g' \
        | tr '\n' ' ')"
    # normalize whitespace (line-continuation gap collapses to single spaces)
    uninstall_libs="$(printf '%s' "$uninstall_libs" | tr -s ' \t\n' ' ' | sed -e 's/^ //' -e 's/ $//')"

    local il uil
    il="$(printf '%s' "$install_libs" | tr ' ' '\n' | sort | tr '\n' ' ')"
    uil="$(printf '%s' "$uninstall_libs" | tr ' ' '\n' | sort | tr '\n' ' ')"
    check_eq "install.sh lib list == POS_LIBS (sorted)" "$il" "$uil"

    local lib
    for lib in $install_libs; do
        if [ -f "$ROOT/lib/$lib" ]; then
            printf '  PASS  lib/%s exists\n' "$lib"
        else
            printf '  FAIL  lib/%s missing\n' "$lib"
        fi
    done

    # ── behavioral: user-unit discovery honors XDG_CONFIG_HOME, pos-* only ──
    local fakeroot="$sandbox/fakeroot"
    mkdir -p "$fakeroot/systemd/user"
    touch "$fakeroot/systemd/user/pos-aria2.service"
    touch "$fakeroot/systemd/user/pos-entertainment-weather.timer"
    touch "$fakeroot/systemd/user/unrelated.service"

    # extract POS_LIBS + installed_plugins + scan_tier1 verbatim
    local extract
    extract="$(awk '
        /^POS_LIBS=\(/ { infn=1 }
        /^scan_tier1\(\) \{/ { inscan=1 }
        infn { print }
        inscan && /^}/ { exit }
    ' "$uninstall")"
    if [ -z "$extract" ]; then
        printf '  FAIL  could not extract scan_tier1 function body\n'
        return 0
    fi
    local runner="$sandbox/run-scan.sh"
    {
        printf '#!/usr/bin/env bash\nset -euo pipefail\n'
        printf '%s\n' "$extract"
        printf '\nscan_tier1\n'
    } > "$runner"

    test_run env XDG_CONFIG_HOME="$fakeroot" bash "$runner"
    check_contains "scan_tier1 finds pos-* unit file" "user-unit: pos-aria2.service" "$TR_OUT"
    check_contains "scan_tier1 finds pos-* timer file" "user-unit: pos-entertainment-weather.timer" "$TR_OUT"
    check_not_contains "scan_tier1 ignores unrelated user unit" "user-unit: unrelated.service" "$TR_OUT"

    # ── plugin removal stays marker-driven ──
    if grep -q "POS_PLUGIN" "$uninstall"; then
        printf '  PASS  plugin removal is POS_PLUGIN-marker driven\n'
    else
        printf '  FAIL  plugin removal is hardcoded (no POS_PLUGIN marker)\n'
    fi
    if command -v compgen >/dev/null 2>&1; then
        printf '  PASS  compgen-based discovery available (bash builtin)\n'
    else
        printf '  FAIL  compgen not available\n'
    fi
}