#!/usr/bin/env bash
set -euo pipefail
# t-install-version.sh — install.sh version gate contract:
#   match→skip with "Already installed", mismatch→proceed, --force bypass,
#   no-git (empty) skip, dry-run variant, flag write after run,
#   numeric comparison correctness (0.0c10 > 0.0c9).
#
# Seam: INSTALL_VERSION_OVERRIDE env var (presence check → empty = no-git path),
# FLAGS_DIR env var (existing flag store seam).
#
# Proceed-path cases (2/3/4/5/8) use --skip all phases instead of --dry-run
# because postinstall.sh is not fully dry-run safe (cat on non-existent file
# after dry-run copy). Skipping all phases is functionally equivalent — the
# gate fires before phases, and the banner + flag write still execute.

run_test() {
    local sandbox stubs flags_dir install_sh

    sandbox="$(mksandbox install-version)"
    stubs="$sandbox/stubs"
    flags_dir="$sandbox/flags"
    mkdir -p "$stubs" "$flags_dir"

    install_sh="$ROOT/install.sh"

    # sudo stub: just exec its arguments (bypasses real sudo in sandbox)
    cat > "$stubs/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    chmod +x "$stubs/sudo"

    # install stub: delegate to the real install binary (needed so -d/-m flags
    # work; we only shadow 'sudo' to avoid needing a tty/password)
    cat > "$stubs/install" <<'STUB'
#!/usr/bin/env bash
exec /usr/bin/install "$@"
STUB
    chmod +x "$stubs/install"

    # mkdir stub: just exec its arguments
    cat > "$stubs/mkdir" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    chmod +x "$stubs/mkdir"

    local base_env=(PATH="$stubs:/usr/bin:/bin"
        HOME="$sandbox/home"
        FLAGS_DIR="$flags_dir")

    # Helper: run install.sh with env overrides and capture output+rc.
    run_install() {
        local envs=() args=()
        while [ $# -gt 0 ]; do
            if [ "$1" = "--" ]; then shift; break; fi
            envs+=("$1"); shift
        done
        args=("$@")
        set +e
        TR_OUT="$(env "${base_env[@]}" "${envs[@]}" bash "$install_sh" "${args[@]}" 2>&1)"
        TR_RC=$?
        set -e
    }

    # Helper: set a flag value directly (for pre-seeding installed_version)
    set_flag() {
        local name="$1" value="$2"
        mkdir -p "$flags_dir"
        printf '%s' "$value" > "$flags_dir/$name"
    }

    # Helper: read a flag value
    get_flag() {
        local name="$1"
        local f="$flags_dir/$name"
        [ -f "$f" ] && cat "$f" || printf ''
    }

    # ═══════════════════════════════════════════════════════════════
    # Case 1: Match → skip ("Already installed")
    #   Gate exits BEFORE any phase — safe without --dry-run or --skip.
    # ═══════════════════════════════════════════════════════════════
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE=0.0c10
    check_rc "C1 match→skip exit code" 0 "$TR_RC"
    check_contains "C1 match→skip message" "Already installed (0.0c10)" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Case 2: Mismatch → proceed (gate doesn't match, phases skipped)
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE=0.0c11 -- --skip preinstall,scripts,postinstall,scalepoint
    check_rc "C2 mismatch→proceed exit code" 0 "$TR_RC"
    check_not_contains "C2 mismatch does not skip" "Already installed" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Case 3: Force bypasses match
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE=0.0c10 -- --skip preinstall,scripts,postinstall,scalepoint --force
    check_rc "C3 force bypasses exit code" 0 "$TR_RC"
    check_not_contains "C3 force bypasses skip" "Already installed" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Case 4: No git (empty version via presence check)
    #   INSTALL_VERSION_OVERRIDE="" with ${var+x} → empty → gate skipped
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE="" -- --skip preinstall,scripts,postinstall,scalepoint
    check_rc "C4 empty override→proceeds exit code" 0 "$TR_RC"
    check_not_contains "C4 empty override does not skip" "Already installed" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Case 5: No installed flag → gate doesn't block
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    run_install INSTALL_VERSION_OVERRIDE=0.0c10 -- --skip preinstall,scripts,postinstall,scalepoint
    check_rc "C5 no flag→proceeds exit code" 0 "$TR_RC"
    check_not_contains "C5 no flag does not skip" "Already installed" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Case 6: Dry-run + match → "Would skip" (not "Already installed")
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE=0.0c10 -- --dry-run
    check_rc "C6 dry-run match exit code" 0 "$TR_RC"
    check_contains "C6 dry-run shows Would skip" "Would skip install" "$TR_OUT"
    check_not_contains "C6 dry-run not Already installed" "Already installed" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Case 7: Flag written after successful run
    #   All phases skipped; sudo/install/mkdir stubs on PATH so
    #   flag_set's `run sudo install` actually creates the flag file.
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE=0.0c11 -- --skip preinstall,scripts,postinstall,scalepoint
    check_rc "C7 all-skip exit code" 0 "$TR_RC"
    local flag_val
    flag_val="$(get_flag installed_version)"
    check_eq "C7 flag written with current version" "0.0c11" "$flag_val"

    # ═══════════════════════════════════════════════════════════════
    # Case 8: Numeric comparison — 0.0c10 > 0.0c9 (not blocked)
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c9"
    run_install INSTALL_VERSION_OVERRIDE=0.0c10 -- --skip preinstall,scripts,postinstall,scalepoint
    check_rc "C8 numeric 10>9 proceeds exit code" 0 "$TR_RC"
    check_not_contains "C8 numeric 10>9 does not skip" "Already installed" "$TR_OUT"

    # Also test: 0.0c9 with installed 0.0c10 → NOT a match
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE=0.0c9 -- --skip preinstall,scripts,postinstall,scalepoint
    check_rc "C8 numeric 9≠10 proceeds exit code" 0 "$TR_RC"
    check_not_contains "C8 numeric 9≠10 does not skip" "Already installed" "$TR_OUT"

    # ═══════════════════════════════════════════════════════════════
    # Case 9: Force + match → still writes flag
    # ═══════════════════════════════════════════════════════════════
    rm -f "$flags_dir/installed_version"
    set_flag "installed_version" "0.0c10"
    run_install INSTALL_VERSION_OVERRIDE=0.0c10 -- --skip preinstall,scripts,postinstall,scalepoint --force
    check_rc "C9 force+match exit code" 0 "$TR_RC"
    local flag_val9
    flag_val9="$(get_flag installed_version)"
    check_eq "C9 force writes flag" "0.0c10" "$flag_val9"
}
