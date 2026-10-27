#!/bin/zsh
# Compila e impacchetta build/WhatsApp Bridge.app con dentro il server MCP (Contents/MacOS/whatsapp-local-mcp).
#
# Variabili:
#   CONFIG=release|debug   configurazione (predefinita: release)
#   UNIVERSAL=1            binario per Apple Silicon e Intel
#   VERSION=1.2.0          versione mostrata dall'app (CFBundleShortVersionString)
#   BUILD=42               numero di build (CFBundleVersion)
#   SIGN_ID="..."          identità di firma; senza, usa il primo certificato Apple Development o la firma ad-hoc
#   INSTALL=1              copia l'app in ~/Applications
#
# Con la firma ad-hoc macOS dimentica l'Accesso completo al disco a ogni build: in locale meglio un certificato stabile.
set -euo pipefail
cd "${0:A:h}/.."

CONFIG=${CONFIG:-release}
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
swift build -c "$CONFIG" $ARCH_FLAGS
BIN="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)"

APP="build/WhatsApp Bridge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WhatsAppBridge" "$BIN/whatsapp-local-mcp" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
[[ -n "${VERSION:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
[[ -n "${BUILD:-}" ]] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}
SIGN_ID=${SIGN_ID:--}
SIGN_OPTS=(--force --sign "$SIGN_ID")
# La notarizzazione richiede hardened runtime e timestamp, disponibili solo con un certificato Developer ID.
if [[ "$SIGN_ID" == "Developer ID Application"* ]]; then
    SIGN_OPTS+=(--options runtime --timestamp)
fi
codesign $SIGN_OPTS --identifier io.github.zxcvbinz.whatsappbridge.mcp "$APP/Contents/MacOS/whatsapp-local-mcp"
codesign $SIGN_OPTS "$APP"
codesign --verify --strict "$APP"
echo "Pronta: $APP (firmata con: $([[ "$SIGN_ID" == "-" ]] && echo ad-hoc || echo "$SIGN_ID"))"

if [[ "${INSTALL:-0}" == 1 ]]; then
    mkdir -p ~/Applications
    rm -rf ~/Applications/"WhatsApp Bridge.app"
    cp -R "$APP" ~/Applications/
    echo "Installata in ~/Applications/WhatsApp Bridge.app"
fi
