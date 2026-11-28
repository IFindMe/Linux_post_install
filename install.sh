#!/usr/bin/env bash
set -euo pipefail

# ── Parse --no-color BEFORE sourcing common.sh ──────────────────
NO_COLOR=0
for arg in "$@"; do
    [ "$arg" = "--no-color" ] && NO_COLOR=1
done
if [ "$NO_COLOR" -eq 1 ]; then
    export NO_COLOR=1 TERM=dumb
    unset CYAN GREEN YELLOW RED BLUE BOLD RESET DIM
fi

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/flags.sh"
source "$(dirname "$0")/lib/ui.sh"

# Return the current install.sh version (e.g. "0.0c174").
# Derived from git commit count. Empty when .git is absent.
# Override with INSTALL_VERSION_OVERRIDE for testing.
install_version() {
    if [ "${INSTALL_VERSION_OVERRIDE+x}" ]; then
        printf '%s' "$INSTALL_VERSION_OVERRIDE"
        return
    fi
    local repo_dir count
    repo_dir="$(cd "$(dirname "$0")" && pwd)"
    count="$(git -C "$repo_dir" rev-list --count HEAD 2>/dev/null)" || { printf ''; return; }
    printf '0.0c%s' "$count"
}

# Exported so child phases (preinstall.sh, postinstall.sh) inherit it —
# otherwise '--dry-run' silently executes them for real.
export DRY_RUN=0
RUN_APPS=0
FORCE=0
SKIP_PHASES=""
STEPS_SPEC=""

# Expand range syntax in a --steps spec ("1-3" → "1,2,3"; also "1,3-4,6").
normalize_steps_spec() {
    local spec="$1" out="" part from to p
    local oldIFS="$IFS"
    IFS=','
    for part in $spec; do
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            from="${BASH_REMATCH[1]}"
            to="${BASH_REMATCH[2]}"
            if [ "$to" -lt "$from" ]; then
                ui_die "Invalid --steps range '$part' (end < start)"
            fi
            for ((p = from; p <= to; p++)); do
                out="${out:+$out,}$p"
            done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            out="${out:+$out,}$part"
        else
            ui_die "Invalid --steps value '$part' (expected 1-3, comma list, or N-M range)"
        fi
    done
    IFS="$oldIFS"
    printf '%s' "$out"
}

usage() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Bootstrap a fresh Debian/Ubuntu install.

Options:
  --apps            Run interactive app picker after core install
  --full            Core install + all optional apps (non-interactive)
  --dry-run         Show what would be done without executing
  --force           Re-install even if the version matches
  --skip <phase>    Skip a phase (repeatable):
                      preinstall, scripts, postinstall, apps
  --steps <spec>    Run only specific phases. Format: 1,3 or 1-3
                    (1=preinstall, 2=scripts, 3=postinstall)
  --no-color        Disable colored output
  -h, --help        Show this help message

Uninstall optional apps later with:
  ./apps/install.sh --uninstall            # interactive uninstall selection
  ./apps/install.sh --uninstall --all      # uninstall everything
  ./apps/install.sh --uninstall <app>...   # uninstall specific apps
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apps) RUN_APPS=1; shift ;;
        --full) RUN_APPS=2; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        --skip)
            [ -z "${2:-}" ] && ui_die "Missing value for --skip"
            SKIP_PHASES="${SKIP_PHASES:+$SKIP_PHASES,}$2"
            shift 2
            ;;
        --steps)
            [ -z "${2:-}" ] && ui_die "Missing value for --steps"
            STEPS_SPEC="$(normalize_steps_spec "$2")"
            shift 2
            ;;
        --no-color) shift ;;
        -h|--help) usage ;;
        *) ui_die "Unknown option: $1" ;;
    esac
done

# ── Version gate ────────────────────────────────────────────────
CURRENT_VERSION="$(install_version)"
ui_header "Linux_post_install" "$CURRENT_VERSION" "Personal bootstrap & homelab toolkit"

if [ "${FORCE:-0}" -ne 1 ] && [ -n "$CURRENT_VERSION" ]; then
    INSTALLED_VERSION="$(flag_value installed_version 2>/dev/null)" || true
    if [ -n "$INSTALLED_VERSION" ]; then
        current_num="${CURRENT_VERSION#0.0c}"
        installed_num="${INSTALLED_VERSION#0.0c}"
        if [ "$current_num" -eq "$installed_num" ] 2>/dev/null; then
            if [ "${DRY_RUN:-0}" -eq 1 ]; then
                ui_info "(dry-run) Would skip install: already at version $CURRENT_VERSION"
            else
                ui_info "Already installed ($CURRENT_VERSION). Use --force to re-install."
            fi
            exit 0
        fi
    fi
fi

# ── Phase runner ────────────────────────────────────────────────
# Phase names → numbers:  preinstall=1 scripts=2 postinstall=3 apps=4
should_run() {
    local phase_num="$1"
    local phase_name="$2"

    # --skip takes precedence
    if [[ ",$SKIP_PHASES," == *",$phase_name,"* ]]; then
        return 1
    fi

    # --steps restricts to listed phases only
    if [ -n "$STEPS_SPEC" ]; then
        if [[ ",$STEPS_SPEC," != *",$phase_num,"* ]]; then
            return 1
        fi
    fi

    return 0
}

timer_start

# ── Phase 1: preinstall ────────────────────────────────────────
if should_run 1 preinstall; then
    ui_section 1 3 "SYSTEM PACKAGES"
    if [ -f preinstall.sh ]; then
        # preinstall.sh owns 'apt update' — no duplicate update here.
        bash preinstall.sh
    fi
fi

# ── Phase 2: install wrappers ──────────────────────────────────
if should_run 2 scripts; then
    ui_section 2 3 "WRAPPER SCRIPTS"
    run sudo mkdir -p /usr/local/bin
    count=0
    for f in bin/*; do
        [ -f "$f" ] || continue
        run sudo install -m 755 "$f" /usr/local/bin/
        count=$((count + 1))
    done
    lib_count=0
    lib_names=""
    for lf in common.sh flags.sh usb-lib.sh menu-lib.sh registry.sh bank-lib.sh; do
        run sudo install -m 644 "lib/$lf" "/usr/local/bin/$lf"
        lib_count=$((lib_count + 1))
        lib_names+="$lf "
    done
    ui_info "libs -> /usr/local/bin (644): ${lib_names% }"

    # ── Precompiled architecture binaries ─────────────────────
    # Manually-compiled binaries (not available on the internet),
    # copied straight into /usr/local/bin for the matching arch.
    # Drop an arm64_bin/ folder later — it is picked up automatically.
    case "$(uname -m)" in
        x86_64)          prebuilt_dir="x64_bin" ;;
        aarch64|arm64)   prebuilt_dir="arm64_bin" ;;
        *)               prebuilt_dir="" ;;
    esac
    if [ -n "$prebuilt_dir" ] && [ -d "$prebuilt_dir" ]; then
        bcount=0
        bnames=""
        for f in "$prebuilt_dir"/*; do
            [ -f "$f" ] || continue
            run sudo install -m 755 "$f" /usr/local/bin/
            bcount=$((bcount + 1))
            bnames+="$(basename "$f") "
        done
        if [ "${DRY_RUN:-0}" -eq 1 ]; then
            ui_info "(dry-run) would install $bcount $prebuilt_dir binaries -> /usr/local/bin"
        else
            ui_success "$bcount $prebuilt_dir binaries -> /usr/local/bin: ${bnames% }"
        fi
    fi

    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        ui_info "(dry-run) would install $count scripts + $lib_count libs -> /usr/local/bin"
    else
        ui_success "$count scripts + $lib_count libs -> /usr/local/bin"
    fi
fi

# ── Phase 3: postinstall ───────────────────────────────────────
if should_run 3 postinstall; then
    ui_section 3 3 "POST-INSTALL CONFIGURATION"
    if [ -f postinstall.sh ]; then
        bash postinstall.sh
    fi
fi

if [ "${DRY_RUN:-0}" -eq 1 ]; then
    ui_info "(dry-run) Bootstrap plan complete" "$(timer_stop)"
else
    ui_success "Bootstrap complete" "$(timer_stop)"
fi

# ── Record installed version ────────────────────────────────────
if [ "${DRY_RUN:-0}" -ne 1 ] && [ -n "${CURRENT_VERSION:-}" ]; then
    flag_set installed_version "$CURRENT_VERSION"
fi

# ── Optional apps ──────────────────────────────────────────────
if [ "$RUN_APPS" -eq 1 ]; then
    echo
    bash apps/install.sh
elif [ "$RUN_APPS" -eq 2 ]; then
    echo
    bash apps/install.sh --all
elif should_run 4 apps && [ -f apps/install.sh ]; then
    # --skip apps disables app phase even if --apps/--full is not used
    true
fi
