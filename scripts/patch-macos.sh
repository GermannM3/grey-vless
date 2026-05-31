#!/usr/bin/env bash
# MACOSX_DEPLOYMENT_TARGET=11.0 (Monterey 12+) и выбор архитектуры.
set -euo pipefail
ARCH="${1:-arm64}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/grey_vless"

PBX="macos/Runner.xcodeproj/project.pbxproj"
INFO="macos/Runner/Info.plist"

if [[ ! -f "$PBX" ]]; then
  echo "macos/ not found — сначала flutter create --platforms=macos"
  exit 1
fi

perl -pi -e 's/MACOSX_DEPLOYMENT_TARGET = 10\.\d+/MACOSX_DEPLOYMENT_TARGET = 11.0/g' "$PBX"
perl -pi -e 's/MACOSX_DEPLOYMENT_TARGET = 11\.\d+/MACOSX_DEPLOYMENT_TARGET = 11.0/g' "$PBX"

RELEASE_XC="macos/Runner/Configs/Release.xcconfig"
DEBUG_XC="macos/Runner/Configs/Debug.xcconfig"
for f in "$RELEASE_XC" "$DEBUG_XC"; do
  grep -q '^MACOSX_DEPLOYMENT_TARGET' "$f" 2>/dev/null && \
    perl -pi -e 's/^MACOSX_DEPLOYMENT_TARGET.*$/MACOSX_DEPLOYMENT_TARGET = 11.0/' "$f" || \
    echo 'MACOSX_DEPLOYMENT_TARGET = 11.0' >> "$f"
done

if command -v plutil >/dev/null 2>&1; then
  plutil -replace LSMinimumSystemVersion -string "11.0" "$INFO"
else
  perl -pi -e 's/<key>LSMinimumSystemVersion<\/key>\s*<string>[^<]+<\/string>/<key>LSMinimumSystemVersion<\/key>\n\t<string>11.0<\/string>/' "$INFO" 2>/dev/null || true
fi

if [[ "$ARCH" == "x86_64" ]]; then
  for f in "$RELEASE_XC" "$DEBUG_XC"; do
    grep -q '^ARCHS' "$f" && perl -pi -e 's/^ARCHS.*$/ARCHS = x86_64/' "$f" || echo 'ARCHS = x86_64' >> "$f"
    grep -q '^ONLY_ACTIVE_ARCH' "$f" || echo 'ONLY_ACTIVE_ARCH = NO' >> "$f"
    grep -q '^EXCLUDED_ARCHS' "$f" && perl -pi -e 's/^EXCLUDED_ARCHS.*$/EXCLUDED_ARCHS = arm64/' "$f" || echo 'EXCLUDED_ARCHS = arm64' >> "$f"
  done
  echo "macOS patch: Intel x86_64, min 11.0"
else
  for f in "$RELEASE_XC" "$DEBUG_XC"; do
    grep -q '^ARCHS' "$f" 2>/dev/null && perl -pi -e 's/^ARCHS.*$/ARCHS = arm64/' "$f" || true
  done
  echo "macOS patch: Apple Silicon arm64, min 11.0"
fi
