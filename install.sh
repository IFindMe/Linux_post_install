#!/usr/bin/env bash
set -euo pipefail

# ── Parse --no-color BEFORE sourcing common.sh ──────────────────
NO_COLOR=0
for arg in "$@"; do
    [ "$arg" = "--no-color" ] && NO_COLOR=1
done
if [ "$NO_COLOR" -eq 1 ]; then
    export TERM=dumb
    unset CYAN GREEN YELLOW RED BLUE BOLD RESET
fi

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/flags.sh"

DRY_RUN=0
RUN_APPS=0
RUN_FEATURES=0
SKIP_PHASES=""
STEPS_SPEC=""

usage() {
    cat <<EOF
Usage: ./install.sh [OPTIONS]

Bootstrap a fresh Debian/Ubuntu install.

Options:
  --apps            Run interactive app picker after core install
  --full            Core install + all optional apps (non-interactive)
  --feature         Install features/ scripts (prompts before overwriting)
  --dry-run         Show what would be done without executing
  --skip <phase>    Skip a phase (repeatable):
                      preinstall, scripts, postinstall, scalepoint, apps
  --steps <spec>    Run only specific phases. Format: 1,3,4 or 1-3
                    (1=preinstall, 2=scripts, 3=postinstall, 4=scalepoint)
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
        --feature) RUN_FEATURES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --skip)
            [ -z "${2:-}" ] && err "Missing value for --skip"
            SKIP_PHASES="${SKIP_PHASES:+$SKIP_PHASES,}$2"
            shift 2
            ;;
        --steps)
            [ -z "${2:-}" ] && err "Missing value for --steps"
            STEPS_SPEC="$2"
            shift 2
            ;;
        --no-color) shift ;;
        -h|--help) usage ;;
        *) err "Unknown option: $1" ;;
    esac
done

# ── Phase runner ────────────────────────────────────────────────
# Phase names → numbers:  preinstall=1 scripts=2 postinstall=3 scalepoint=4
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

section "Linux_post_install Bootstrap"
timer_start

# ── Phase 1: preinstall ────────────────────────────────────────
if should_run 1 preinstall; then
    step 1 4 "Installing system packages"
    if [ -f preinstall.sh ]; then
        spawn "apt update" sudo apt update
        bash preinstall.sh
    fi
fi

# ── Phase 2: install wrappers ──────────────────────────────────
if should_run 2 scripts; then
    step 2 4 "Installing wrapper scripts"
    run sudo mkdir -p /usr/local/bin
    count=0
    for f in bin/*; do
        [ -f "$f" ] || continue
        run sudo install -m 755 "$f" /usr/local/bin/
        count=$((count + 1))
    done
    run sudo install -m 644 lib/common.sh /usr/local/bin/common.sh
    run sudo install -m 644 lib/flags.sh /usr/local/bin/flags.sh

    # ── Entertainment plugins ────────────────────────────────
    run sudo mkdir -p /usr/local/share/linux_post_install/entertainment
    pcount=0
    for f in entertainment/*.sh; do
        [ -f "$f" ] || continue
        run sudo install -m 755 "$f" /usr/local/share/linux_post_install/entertainment/
        pcount=$((pcount + 1))
    done
    ok "$pcount entertainment plugins -> /usr/local/share/linux_post_install/entertainment"

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
        for f in "$prebuilt_dir"/*; do
            [ -f "$f" ] || continue
            run sudo install -m 755 "$f" /usr/local/bin/
        done
        ok "$prebuilt_dir binaries -> /usr/local/bin"
    fi

    # ── Optional features ──────────────────────────────────────
    if [ "$RUN_FEATURES" -eq 1 ]; then
        for f in features/*; do
            [ -f "$f" ] || continue
            name=$(basename "$f")
            flag_name="${name%.sh}"
            dest="/usr/local/bin/$name"
            if [ -e "$dest" ]; then
                if confirm "Overwrite existing $dest?" n; then
                    run sudo install -m 755 "$f" "$dest"
                else
                    log "Keeping existing $dest"
                fi
            else
                run sudo install -m 755 "$f" "$dest"
            fi
            flag_set "$flag_name"
        done
        ok "features installed"
    fi
    ok "$count scripts + libs -> /usr/local/bin"
fi

# ── Phase 3: postinstall ───────────────────────────────────────
if should_run 3 postinstall; then
    step 3 4 "Post-install configuration"
    if [ -f postinstall.sh ]; then
        bash postinstall.sh
    fi
fi

# ── Phase 4: ScaleTail templates ────────────────────────────────
if should_run 4 scalepoint; then
    step 4 4 "Cloning ScaleTail templates"
    scale_dest="/usr/local/share/linux_post_install/scale-tail"
    if [ ! -d "$scale_dest" ]; then
        spawn "Cloning ScaleTail" sudo git clone --depth 1 \
            https://github.com/tailscale-dev/ScaleTail.git "$scale_dest"
    else
        log "ScaleTail already cloned"
    fi
fi

echo
echo "${GREEN}════════════════════════════════════════════${RESET}"
echo "${GREEN}  Bootstrap complete ($(timer_stop))${RESET}"
echo "${GREEN}════════════════════════════════════════════${RESET}"

# ── Optional apps ──────────────────────────────────────────────
if [ "$RUN_APPS" -eq 1 ]; then
    echo
    bash apps/install.sh
elif [ "$RUN_APPS" -eq 2 ]; then
    echo
    bash apps/install.sh --all
elif should_run 5 apps && [ -f apps/install.sh ]; then
    # --skip apps disables app phase even if --apps/--full is not used
    true
fi
