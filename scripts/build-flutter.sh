#!/usr/bin/env bash
# Локальная сборка Flutter (Linux + Windows). macOS/Android — через GitHub Actions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$ROOT/tools/git-extract/usr/bin:$ROOT/tools/flutter/bin:$PATH"

if ! command -v flutter >/dev/null; then
  echo "Flutter не найден. Установите SDK в tools/flutter или PATH."
  exit 1
fi

if [ ! -f "$ROOT/grey_vless/assets/bin/sing-box-linux-amd64" ]; then
  "$ROOT/scripts/download-cores.sh"
fi

cd "$ROOT/grey_vless"
flutter pub get
flutter create . --org com.grey --project-name grey_vless --platforms=linux,windows,android

if ! command -v cmake >/dev/null; then
  echo "Нужен cmake: sudo apt install cmake ninja-build clang pkg-config libgtk-3-dev"
  echo "Или запустите сборку в GitHub Actions (см. BUILD.md)"
  exit 1
fi

flutter build linux --release
flutter build windows --release

echo "Linux: grey_vless/build/linux/x64/release/bundle/"
echo "Windows: grey_vless/build/windows/x64/runner/Release/"
