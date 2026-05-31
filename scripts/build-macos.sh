#!/usr/bin/env bash
set -euo pipefail
ARCH="${1:-arm64}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/grey_vless"

chmod +x "$ROOT/scripts/prepare-icons.sh" "$ROOT/scripts/patch-macos.sh"
"$ROOT/scripts/prepare-icons.sh"

flutter pub get
dart run flutter_launcher_icons 2>/dev/null || true
"$ROOT/scripts/patch-macos.sh" "$ARCH"

flutter build macos --release

mkdir -p dist
rm -rf "dist/grey_vless.app"
cp -R build/macos/Build/Products/Release/grey_vless.app dist/

DMG="dist/Grey-vless-macos-${ARCH}.dmg"
rm -f "$DMG"
hdiutil create -volname "Grey vless" -srcfolder dist/grey_vless.app -ov -format UDZO "$DMG"

file "dist/grey_vless.app/Contents/MacOS/grey_vless" || true
echo "Built $DMG"
