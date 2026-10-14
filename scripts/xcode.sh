#!/bin/bash
# DevApp.xcodeproj'u (uygulama + masaüstü widget) oluşturur ve Xcode'da açar.
#
#   ./scripts/xcode.sh            → projeyi oluştur ve aç
#   ./scripts/xcode.sh build      → komut satırından derle, /Applications'a kur ve aç
#
# Widget'ların imzalanması için Apple geliştirici takımınız gerekir (ücretsiz Apple ID de olur).
# Takım kimliğini bir kez kaydedin:  echo ABCDE12345 > .devapp-team
# (Xcode > Settings > Accounts > takımınız > "Team ID", ya da developer.apple.com > Membership)
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen bulunamadı. Kurmak için: brew install xcodegen"
  exit 1
fi

if [ -z "${DEVAPP_TEAM:-}" ] && [ -f .devapp-team ]; then
  DEVAPP_TEAM="$(tr -d '[:space:]' < .devapp-team)"
fi
export DEVAPP_TEAM="${DEVAPP_TEAM:-}"
if [ -z "$DEVAPP_TEAM" ]; then
  echo "⚠︎  Takım kimliği yok. Widget için gerekli: echo TAKIM_ID > .devapp-team"
  echo "   (Şimdilik Xcode'da Signing & Capabilities sekmesinden de seçebilirsiniz.)"
fi

mkdir -p Support/Generated
xcodegen generate --quiet
echo "✓ DevApp.xcodeproj oluşturuldu"

if [ "${1:-}" = "build" ]; then
  xcodebuild -project DevApp.xcodeproj -scheme DevApp -configuration Release \
    -derivedDataPath build/xcode -allowProvisioningUpdates build | tail -5
  APP="build/xcode/Build/Products/Release/DevApp.app"
  rm -rf /Applications/DevApp.app
  cp -R "$APP" /Applications/
  echo "✓ /Applications/DevApp.app kuruldu"
  open /Applications/DevApp.app
  echo "Widget: masaüstüne sağ tık > Widget'ları Düzenle > DevApp"
else
  open DevApp.xcodeproj
fi
