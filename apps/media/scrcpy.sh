#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib/common.sh"

RELEASE_URL="https://api.github.com/repos/Genymobile/scrcpy/releases/latest"

install_scrcpy() {
    command -v scrcpy &>/dev/null && { log "scrcpy already installed"; return 0; }

    spawn "Fetching latest scrcpy release info" bash -c "
        curl -fsSL '$RELEASE_URL' -o /tmp/scrcpy-release.json
    "

    local tag asset_url
    tag=$(python3 -c "import json; print(json.load(open('/tmp/scrcpy-release.json'))['tag_name'])")
    asset_url=$(python3 -c "
import json
r = json.load(open('/tmp/scrcpy-release.json'))
for a in r['assets']:
    if a['name'].startswith('scrcpy-linux-x86_64') and a['name'].endswith('.tar.gz'):
        print(a['browser_download_url'])
        break
")
    version="${tag#v}"

    spawn "Downloading scrcpy $version" bash -c "
        install_dir=/usr/local/lib/scrcpy-$version
        curl -fsSL '$asset_url' -o /tmp/scrcpy.tar.gz
        sudo rm -rf \$install_dir /usr/local/lib/scrcpy
        sudo mkdir -p \$install_dir
        sudo tar xzf /tmp/scrcpy.tar.gz -C \$install_dir --strip-components=1
        sudo ln -sf \$install_dir/scrcpy /usr/local/bin/scrcpy
        rm -f /tmp/scrcpy.tar.gz /tmp/scrcpy-release.json
    "

    spawn "Adding desktop entry" bash -c "
        sudo tee /usr/share/applications/scrcpy.desktop >/dev/null <<-EOF
[Desktop Entry]
Name=scrcpy
Comment=Display and control Android devices
Exec=/usr/local/bin/scrcpy
Icon=/usr/local/lib/scrcpy-$version/scrcpy.png
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=false
EOF
    "

    log "scrcpy $version installed (adb included in the bundle)"
}

install_scrcpy
