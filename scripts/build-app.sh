#!/bin/zsh
# Compila e impacchetta build/WhatsApp Bridge.app con dentro il server MCP (Contents/MacOS/whatsapp-local-mcp).
# Firma con un certificato stabile (non ad-hoc): con la firma ad-hoc macOS dimentica l'Accesso completo al disco a ogni build.
set -euo pipefail
cd "${0:A:h}/.."

CONFIG=${CONFIG:-release}
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/WhatsApp Bridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WhatsAppBridge" "$BIN/whatsapp-local-mcp" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}
codesign --force --sign "${SIGN_ID:--}" --identifier it.wearepeople.whatsappbridge.mcp "$APP/Contents/MacOS/whatsapp-local-mcp"
codesign --force --sign "${SIGN_ID:--}" "$APP"
echo "Pronta: $APP (firmata con: ${SIGN_ID:-ad-hoc})"

# `INSTALL=1 ./scripts/build-app.sh` la copia in ~/Applications: è il percorso da registrare in Claude Code.
if [[ "${INSTALL:-0}" == 1 ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/"WhatsApp Bridge.app"
    cp -R "$APP" ~/Applications/
    echo "Installata in ~/Applications/WhatsApp Bridge.app"
fi
