#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

usage() {
    cat <<EOF
Usage: bash apps/install.sh [OPTIONS] [app ...]

Install or uninstall optional desktop applications.

Options:
  --all          Apply action to all available apps without prompting
  --uninstall    Uninstall the selected apps instead of installing
  -h, --help     Show this help message

Examples:
  bash apps/install.sh                    # interactive install selection
  bash apps/install.sh --all              # install everything
  bash apps/install.sh brave vscode       # install specific apps
  bash apps/install.sh --uninstall        # interactive uninstall selection
  bash apps/install.sh --uninstall --all  # uninstall everything
  bash apps/install.sh --uninstall brave  # uninstall specific apps
EOF
    exit 0
}

ALL=0
UNINSTALL=0
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) ALL=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) usage ;;
        -*) err "Unknown option: $1" ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

APPS_DIR="$(dirname "$0")"

# ── Category display names ─────────────────────────────────────
declare -A CAT_NAMES=(
    [browsers]="Browsers"
    [development]="Development"
    [media]="Media"
    [networking]="Networking / VPN"
    [remote-access]="Remote Access"
    [system]="System / Virtualization"
    [utilities]="Utilities"
)

# ── Discover categories and apps ───────────────────────────────
CATEGORIES=()
declare -A CAT_APPS

for cat_dir in "$APPS_DIR"/*/; do
    [ -d "$cat_dir" ] || continue
    cat_name=$(basename "$cat_dir")
    # Skip non-app directories
    [[ "$cat_name" == "install" ]] && continue
    # Check if directory has any .sh files
    has_apps=0
    for f in "$cat_dir"*.sh; do
        [ -f "$f" ] && has_apps=1 && break
    done
    [ "$has_apps" -eq 0 ] && continue

    CATEGORIES+=("$cat_name")
    CAT_APPS["$cat_name"]=""
    for f in "$cat_dir"*.sh; do
        [ -f "$f" ] || continue
        app_name=$(basename "$f" .sh)
        CAT_APPS["$cat_name"]+=" $app_name"
    done
done

# ── Helper: find which category an app belongs to ──────────────
find_app_category() {
    local app="$1"
    for cat in "${CATEGORIES[@]}"; do
        for a in ${CAT_APPS[$cat]}; do
            [ "$a" == "$app" ] && { echo "$cat"; return 0; }
        done
    done
    return 1
}

SELECTED=()

# ── Mode 1: specific apps requested on command line ────────────
if [ "${#POSITIONAL[@]}" -gt 0 ]; then
    for req in "${POSITIONAL[@]}"; do
        cat=$(find_app_category "$req" 2>/dev/null) && {
            SELECTED+=("$req")
        } || {
            warn "Unknown app: $req (skipping)"
        }
    done

# ── Mode 2: --all ─────────────────────────────────────────────
elif [ "$ALL" -eq 1 ]; then
    for cat in "${CATEGORIES[@]}"; do
        for app in ${CAT_APPS[$cat]}; do
            SELECTED+=("$app")
        done
    done

# ── Mode 3: interactive TUI ───────────────────────────────────
else
    section "Optional Applications"
    if [ "$UNINSTALL" -eq 1 ]; then
        echo "Select apps to uninstall (y/n for each):"
    else
        echo "Select apps to install (y/n for each):"
    fi
    echo

    for cat in "${CATEGORIES[@]}"; do
        display="${CAT_NAMES[$cat]:-$cat}"
        echo "  $display"
        for app in ${CAT_APPS[$cat]}; do
            if [ "$UNINSTALL" -eq 1 ]; then
                read -rp "    Remove ${app}? [y/N]: " yn
            else
                read -rp "    Install ${app}? [y/N]: " yn
            fi
            if [[ "$yn" =~ ^[Yy] ]]; then
                SELECTED+=("$app")
            fi
        done
        echo
    done
fi

# ── Apply action to selected apps ─────────────────────────────
[ "${#SELECTED[@]}" -eq 0 ] && { warn "No apps selected"; exit 0; }

echo
if [ "$UNINSTALL" -eq 1 ]; then
    section "Uninstalling ${SELECTED[*]}"
else
    section "Installing ${SELECTED[*]}"
fi

timer_start
count=1
total=${#SELECTED[@]}
for app in "${SELECTED[@]}"; do
    cat=$(find_app_category "$app")
    step "$count" "$total" "$app"
    if [ "$UNINSTALL" -eq 1 ]; then
        bash "$APPS_DIR/$cat/$app.sh" uninstall
    else
        bash "$APPS_DIR/$cat/$app.sh"
    fi
    count=$((count + 1))
    echo
done

echo
if [ "$UNINSTALL" -eq 1 ]; then
    echo "${GREEN}════════════════════════════════════════════${RESET}"
    echo "${GREEN}  Apps uninstalled ($(timer_stop))${RESET}"
    echo "${GREEN}════════════════════════════════════════════${RESET}"
else
    echo "${GREEN}════════════════════════════════════════════${RESET}"
    echo "${GREEN}  Apps installed ($(timer_stop))${RESET}"
    echo "${GREEN}════════════════════════════════════════════${RESET}"
fi
