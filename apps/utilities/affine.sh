#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

install_affine() {
    command -v affine &>/dev/null && { log "affine already installed"; return 0; }

    local appimage_url="https://github.com/toeverything/AFFiNE/releases/download/v0.26.3/affine-0.26.3-stable-linux-x64.appimage"

    local icon_url="https://raw.githubusercontent.com/toeverything/AFFiNE/master/packages/frontend/apps/electron/resources/icons/icon.png"

    spawn "Installing AFFiNE AppImage" bash -c "
        mkdir -p /opt/affine
        curl -fsSL '$appimage_url' -o /opt/affine/affine.AppImage
        chmod +x /opt/affine/affine.AppImage
        ln -sf /opt/affine/affine.AppImage /usr/local/bin/affine
    "

    spawn "Adding desktop entry" bash -c "
        curl -fsSL '$icon_url' -o /opt/affine/icon.png
        cat > /usr/share/applications/affine.desktop <<-EOF
[Desktop Entry]
Name=AFFiNE
Comment=Next-gen knowledge base
Exec=/opt/affine/affine.AppImage
Icon=/opt/affine/icon.png
Terminal=false
Type=Application
Categories=Office;Utility;
StartupNotify=false
EOF
    "
}

install_affine
