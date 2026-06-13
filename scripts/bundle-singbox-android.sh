#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/grey_vless/assets/bin/sing-box-android-arm64"
DEST_DIR="$ROOT/grey_vless/android/app/src/main/jniLibs/arm64-v8a"
DEST="$DEST_DIR/libsingbox.so"

if [[ ! -f "$SRC" ]]; then
  echo "sing-box android binary not found: $SRC" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "Bundled sing-box -> $DEST ($(du -h "$DEST" | awk '{print $1}'))"
