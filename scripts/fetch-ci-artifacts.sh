#!/usr/bin/env bash
# Скачать артефакты последнего успешного CI (нужен gh auth login или GITHUB_TOKEN).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/dist/channel-pack/final"
mkdir -p "$OUT"

if ! command -v gh >/dev/null 2>&1; then
  echo "Установите GitHub CLI: sudo apt install gh && gh auth login"
  echo "Или скачайте вручную: https://github.com/GermannM3/grey-vless/actions"
  exit 1
fi

RUN_ID="$(gh run list --repo GermannM3/grey-vless --workflow "Build Grey vless (all platforms)" --limit 5 --json databaseId,conclusion,headSha -q '.[] | select(.conclusion=="success" or .conclusion=="failure") | .databaseId' | head -1)"
echo "Run ID: $RUN_ID"
gh run download "$RUN_ID" --repo GermannM3/grey-vless --dir "$OUT/raw-ci"

APK="$(find "$OUT/raw-ci" -name '*.apk' | head -1)"
WIN="$(find "$OUT/raw-ci" -name 'grey_vless.exe' -o -name '*.exe' 2>/dev/null | head -1)"
DMG="$(find "$OUT/raw-ci" -name '*.dmg' | head -1)"

[[ -n "$APK" ]] && cp -f "$APK" "$OUT/Grey-vless-android.apk" && echo "OK android"
[[ -n "$DMG" ]] && cp -f "$DMG" "$OUT/Grey-vless-macos.dmg" && echo "OK macos"
if [[ -n "$WIN" ]]; then
  if [[ -d "$(dirname "$WIN")" ]]; then
    (cd "$(dirname "$WIN")" && zip -qr "$OUT/Grey-vless-windows.zip" .)
    echo "OK windows zip"
  fi
fi

echo "Готово: $OUT"
