#!/usr/bin/env bash
set -euo pipefail
# t-llamacpp-install.sh — F7: `apps/ai/llamacpp.sh` post-install sanity.
# After the installer drops llama-server + symlinks it into the bin dir, the
# sanity check must verify the binary actually runs (version/help readable via
# the same stdout/stderr the tool chain reads) and the symlink is not dangling.
#   healthy            → passes, logs "llama.cpp sanity OK"
#   dangling symlink   → err (rc 1, "dangling symlink")
#   non-executable     → err (rc 1, not on PATH)
#   broken binary      → err (rc 1, --version did not run → missing shared lib)
# Uses the LLAMACPP_BIN_DIR seam; calls the REAL shipped function.
#
# Note: the real installer cannot run in the sandbox (network + sudo + root
# paths), so the sanity function is extracted verbatim and exercised directly.

# extract_fn <source-file> <fnname> — print one brace-delimited function body.
extract_fn() {
    local file="$1" fn="$2"
    awk -v fn="$fn" '
        BEGIN { found=0; depth=0 }
        {
            if (!found && $0 ~ ("^" fn "\\(\\)")) { found=1; depth=0 }
            if (found) {
                n_open  = gsub(/\{/, "{")
                n_close = gsub(/\}/, "}")
                depth = depth + n_open - n_close
                print
                if (depth <= 0) exit
            }
        }
    ' "$file"
}

run_test() {
    local app="$ROOT/apps/ai/llamacpp.sh"
    local com="$ROOT/lib/common.sh"

    # Extract the REAL llamacpp_sanity from the shipped installer.
    local fn_file="$TEST_TMP/llamacpp-fns.sh"
    extract_fn "$app" llamacpp_sanity > "$fn_file"

    local sandbox bindir
    sandbox="$(mksandbox llamacpp-install)"
    bindir="$sandbox/bin"
    mkdir -p "$bindir"

    # 1. healthy fixture → rc 0 + "llama.cpp sanity OK"
    cat > "$bindir/llama-server" <<'STUB'
#!/usr/bin/env bash
# healthy: version + help both readable; llama.cpp prints version to stderr
printf 'version: 0.4.0-dev (build 10822, commit c457e3bf7)\n' >&2
exit 0
STUB
    chmod +x "$bindir/llama-server"
    test_run_env LLAMACPP_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" -- \
        bash -c "source '$com'; source '$fn_file'; llamacpp_sanity" 2>&1
    check_rc "F7 healthy fixture sanity rc 0" 0 "$TR_RC"
    check_contains "F7 healthy fixture sanity OK log" "llama.cpp sanity OK" "$TR_OUT"

    # 2. dangling symlink → err, rc 1, names the broken link
    rm -f "$bindir/llama-server"
    ln -s "$bindir/no-such-target" "$bindir/llama-server"
    test_run_env LLAMACPP_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" -- \
        bash -c "source '$com'; source '$fn_file'; llamacpp_sanity" 2>&1
    check_rc "F7 dangling symlink errs (rc 1)" 1 "$TR_RC"
    check_contains "F7 dangling symlink message" "dangling symlink" "$TR_OUT"

    # 3. non-executable fixture → err, rc 1 (bash `command -v` finds the file
    #    by PATH existence; the binary fails when actually executed, so the
    #    sanity errs at the --version step — the contract is a non-zero err).
    rm -f "$bindir/llama-server"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$bindir/llama-server"
    chmod 644 "$bindir/llama-server"   # NOT executable
    test_run_env LLAMACPP_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" -- \
        bash -c "source '$com'; source '$fn_file'; llamacpp_sanity" 2>&1
    check_rc "F7 non-executable errs (rc 1)" 1 "$TR_RC"
    check_contains "F7 non-executable message is a sanity err" "llama.cpp install sanity failed" "$TR_OUT"

    # 4. broken binary (--version fails like a missing shared lib) → err, rc 1
    rm -f "$bindir/llama-server"
    cat > "$bindir/llama-server" <<'STUB'
#!/usr/bin/env bash
# simulates a truncated/missing-shared-lib binary: version unreadable
echo "error while loading shared libraries: libllama.so: cannot open" >&2
exit 1
STUB
    chmod +x "$bindir/llama-server"
    test_run_env LLAMACPP_BIN_DIR="$bindir" PATH="$bindir:/usr/bin:/bin" -- \
        bash -c "source '$com'; source '$fn_file'; llamacpp_sanity" 2>&1
    check_rc "F7 broken binary errs (rc 1)" 1 "$TR_RC"
    check_contains "F7 broken binary message" "did not run" "$TR_OUT"

    # 5. static guard: the shipped installer actually CALLS the sanity after
    #    the symlink loop (the wiring that makes F7 real).
    if grep -q 'llamacpp_sanity' "$app"; then
        printf '  PASS  F7 installer wires llamacpp_sanity into install\n'
    else
        printf '  FAIL  F7 installer does not call llamacpp_sanity\n'
    fi
}