#!/usr/bin/env bash
# Последовательная сборка всех артефактов, которые можно собрать на этой машине.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist/release"
VERSION="0.3.0"
mkdir -p "$DIST"
LOG="$DIST/build.log"
exec > >(tee -a "$LOG") 2>&1

echo "========== Grey vless — полная сборка $(date) =========="

echo ""
echo ">>> [1/4] .deb (Python GTK, автономный)"
"$ROOT/scripts/build-deb.sh"
cp -f "$ROOT/build/deb/grey-vless_${VERSION}_amd64.deb" "$DIST/"

echo ""
echo ">>> [2/4] AppImage (Python GTK)"
if [ -f "$ROOT/build/Grey-vless-0.3.0-x86_64.AppImage" ] && fuser "$ROOT/build/Grey-vless-0.3.0-x86_64.AppImage" >/dev/null 2>&1; then
  echo "Старый AppImage занят (запущен). Собираем новый файл..."
  "$ROOT/scripts/bundle-runtime.py" 2>/dev/null || python3 "$ROOT/scripts/bundle-runtime.py"
  rm -rf "$ROOT/build/AppDir"
  mkdir -p "$ROOT/build/AppDir"
  # quick rebuild via build-appimage internals
  bash -c 'source "'"$ROOT"'/scripts/build-appimage.sh"' 2>/dev/null || true
fi
if [ ! -f "$ROOT/build/Grey-vless-python-${VERSION}-x86_64.AppImage" ]; then
  if [ -x "$ROOT/build/tools/appimagetool-x86_64.AppImage" ] && [ -d "$ROOT/build/AppDir" ]; then
    ARCH=x86_64 "$ROOT/build/tools/appimagetool-x86_64.AppImage" "$ROOT/build/AppDir" \
      "$ROOT/build/Grey-vless-python-${VERSION}-x86_64.AppImage" || true
  fi
fi
for f in "$ROOT/build/Grey-vless"*x86_64.AppImage; do
  [ -f "$f" ] && cp -f "$f" "$DIST/" && echo "AppImage: $f"
done

echo ""
echo ">>> [3/4] Портативные ядра macOS / Windows (для Flutter CI или ручного запуска)"
CORES="$DIST/Grey-vless-cores-${VERSION}"
mkdir -p "$CORES"
if [ ! -f "$ROOT/grey_vless/assets/bin/sing-box-linux-amd64" ]; then
  "$ROOT/scripts/download-cores.sh"
fi
cp -f "$ROOT/grey_vless/assets/bin/sing-box-darwin-amd64" "$CORES/" 2>/dev/null || true
cp -f "$ROOT/grey_vless/assets/bin/sing-box-darwin-arm64" "$CORES/" 2>/dev/null || true
cp -f "$ROOT/grey_vless/assets/bin/sing-box-windows-amd64.exe" "$CORES/" 2>/dev/null || true
cp -f "$ROOT/grey_vless/assets/bin/sing-box-android-arm64" "$CORES/" 2>/dev/null || true
(
  cd "$DIST"
  zip -qr "Grey-vless-cores-${VERSION}.zip" "Grey-vless-cores-${VERSION}"
)

echo ""
echo ">>> [4/4] Flutter (Linux/Win/Android/macOS)"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "Запуск GitHub Actions workflow..."
  gh workflow run "Build Grey vless (all platforms)" 2>/dev/null || gh workflow run build-all.yml 2>/dev/null || echo "Не удалось запустить workflow"
else
  echo "Flutter-сборки требуют: sudo apt install cmake ninja-build clang pkg-config libgtk-3-dev"
  echo "Или: gh auth login + push на GitHub → Actions"
  if [ -x "$ROOT/scripts/build-flutter.sh" ]; then
  if command -v cmake >/dev/null 2>&1; then
    "$ROOT/scripts/build-flutter.sh" || echo "Flutter build skipped (ошибка)"
  fi
  fi
fi

echo ""
echo ">>> Упаковка итогов"
cat > "$DIST/README.txt" <<EOF
Grey vless — сборка ${VERSION}
Дата: $(date)

Файлы для канала:
- grey-vless_${VERSION}_amd64.deb          — Linux (установка)
- Grey-vless-*-x86_64.AppImage           — Linux (без установки)
- Grey-vless-cores-${VERSION}.zip        — ядра sing-box (mac/win/android)

Flutter (полный GUI на всех ОС):
  GitHub Actions → Build Grey vless → скачать артефакты:
  - grey-vless-windows-x64
  - grey-vless-macos (.dmg)
  - grey-vless-android-apk
  - grey-vless-linux-x64 / appimage

Важно: запускайте без sudo, иначе системный прокси не включится.
EOF

ls -lh "$DIST"
echo ""
echo "Готово. Папка для отправки: $DIST"
