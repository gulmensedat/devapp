#!/bin/bash
# DevApp.app paketini oluşturur: ./scripts/build-app.sh [release|debug] [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
INSTALL="${2:-}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/DevApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/DevApp" "$APP/Contents/MacOS/DevApp"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# SwiftPM kaynak paketleri (SwiftTerm vb.)
for bundle in "$BIN"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --deep --sign - "$APP" >/dev/null
echo "✓ $APP oluşturuldu"

if [ "$INSTALL" = "--install" ]; then
  rm -rf /Applications/DevApp.app
  cp -R "$APP" /Applications/
  echo "✓ /Applications/DevApp.app yüklendi"
  open /Applications/DevApp.app
fi
