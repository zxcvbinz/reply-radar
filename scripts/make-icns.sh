#!/bin/zsh
# Genera Resources/AppIcon.icns da Resources/icon/icon-1024.png.
set -euo pipefail
cd "${0:A:h}/.."
ISET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ISET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon/icon-1024.png --out "$ISET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/icon/icon-1024.png --out "$ISET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ISET" -o Resources/AppIcon.icns
echo "Scritto Resources/AppIcon.icns"
