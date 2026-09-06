#!/usr/bin/env bash
set -euo pipefail
# t-gpg-password.sh — backup encryption passphrase handling (D3):
#   - passphrase fed to gpg on fd 3 (here-string), NEVER as argv token,
#   - plaintext archive removed after successful encryption; only .gpg remains,
#   - encryption failure: plaintext removed, rc != 0, nothing left behind,
#   - verification failure: corrupt .gpg removed, rc != 0,
#   - end-to-end success path. gpg/sudo stubbed; tar real; stdin piped (no tty).

run_test() {
    require_cmd timeout "gpg password" || return 0
    command -v tar >/dev/null 2>&1 || { skip_case "gpg password" "tar not available"; return 0; }

    local sandbox stubs work data
    sandbox="$(mksandbox gpg-password)"
    stubs="$sandbox/stubs"
    work="$sandbox/work"
    data="$sandbox/data/My Data"
    mkdir -p "$stubs" "$work" "$data"
    printf 'important file content\n' > "$data/notes.txt"

    local gpg_log="$sandbox/gpg.log"
    : > "$gpg_log"

    printf 'canned\n' > "$sandbox/canned.txt"
    tar -czf "$sandbox/fake.tar.gz" -C "$sandbox" canned.txt || \
        { skip_case "gpg password" "cannot create canned tar fixture"; return 0; }

    # stub gpg: log every argv token (one per line), simulate failures via
    # STUB_GPG_FAIL, decrypt phase emits canned tar.gz stream
    cat > "$stubs/gpg" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$gpg_log"
input=""
for a in "\$@"; do
    case "\$a" in
        -*) ;;
        *) input="\$a" ;;
    esac
done
case "\$*" in
    *--symmetric*)
        if [ "\${STUB_GPG_FAIL:-}" = "encrypt" ]; then exit 1; fi
        cp "\$input" "\$input.gpg"
        ;;
    *--decrypt*)
        if [ "\${STUB_GPG_FAIL:-}" = "verify" ]; then exit 1; fi
        cat "$sandbox/fake.tar.gz"
        ;;
    *) ;;
esac
STUB
    printf '#!/usr/bin/env bash\nexec "$@"\n' > "$stubs/sudo"
    chmod +x "$stubs/gpg" "$stubs/sudo"

    local backup="$ROOT/bin/pos-system-backup"
    local common_env=(PATH="$stubs:/usr/bin:/bin" NOTIFY_PLATFORM=""
        BACKUP_USB_ROOT="$sandbox/usbroot")

    # 1. success path
    ( cd "$work" && printf 's3cr3t-pass\ns3cr3t-pass\n' \
        | timeout 30 env "${common_env[@]}" "$backup" "$data" >"$sandbox/run1.out" 2>&1 )
    local rc1=$?
    check_rc "backup success exits 0" 0 "$rc1"
    check_file_exists "encrypted artifact created (.tar.gz.gpg)" "$work"/*.tar.gz.gpg
    check_eq "plaintext archive removed after encryption" 0 \
        "$(find "$work" -maxdepth 1 -name '*.tar.gz' | wc -l)"
    check_contains "success logs completion" "Backup completed" "$(cat "$sandbox/run1.out")"
    check_contains "gpg invoked with --passphrase-fd" "--passphrase-fd" "$(cat "$gpg_log")"
    check_eq "gpg passphrase-fd used twice (encrypt+decrypt)" 2 \
        "$(count_token --passphrase-fd "$(cat "$gpg_log")")"
    # the security property: no bare --passphrase argv token (check token-exact,
    # because --passphrase-fd legitimately CONTAINS the substring)
    local bare
    bare="$(grep -c '^--passphrase$' "$gpg_log" || true)"
    check_eq "never a bare --passphrase argv token" 0 "$bare"
    check_not_contains "secret never appears in gpg argv" "s3cr3t-pass" "$(cat "$gpg_log")"

    # 2. encryption failure → plaintext removed, rc != 0, nothing left
    rm -rf "$work"; mkdir -p "$work"
    : > "$gpg_log"
    ( cd "$work" && printf 's3cr3t-pass\ns3cr3t-pass\n' \
        | timeout 30 env "${common_env[@]}" STUB_GPG_FAIL=encrypt "$backup" "$data" >"$sandbox/run2.out" 2>&1 )
    local rc2=$?
    check_contains "encrypt-failure reports cleanup" "plaintext archive removed" "$(cat "$sandbox/run2.out")"
    if [ "$rc2" -ne 0 ]; then
        printf '  PASS  encryption failure exits nonzero\n'
    else
        printf '  FAIL  encryption failure exited 0\n'
    fi
    check_eq "nothing left behind after encrypt failure" 0 \
        "$(find "$work" -maxdepth 1 \( -name '*.tar.gz' -o -name '*.tar.gz.gpg' \) | wc -l)"

    # 3. verification failure → corrupt .gpg removed, rc != 0, nothing left
    rm -rf "$work"; mkdir -p "$work"
    : > "$gpg_log"
    ( cd "$work" && printf 's3cr3t-pass\ns3cr3t-pass\n' \
        | timeout 30 env "${common_env[@]}" STUB_GPG_FAIL=verify "$backup" "$data" >"$sandbox/run3.out" 2>&1 )
    local rc3=$?
    check_contains "verify-failure reports cleanup" "corrupt artifact removed" "$(cat "$sandbox/run3.out")"
    if [ "$rc3" -ne 0 ]; then
        printf '  PASS  verification failure exits nonzero\n'
    else
        printf '  FAIL  verification failure exited 0\n'
    fi
    check_eq "nothing left behind after verify failure" 0 \
        "$(find "$work" -maxdepth 1 \( -name '*.tar.gz' -o -name '*.tar.gz.gpg' \) | wc -l)"
}