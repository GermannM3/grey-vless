#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="1.11.7"
DEST="$ROOT/grey_vless/assets/bin"
mkdir -p "$DEST"

download() {
  local url="$1"
  local out="$2"
  echo "==> $out"
  curl -fsSL "$url" -o "$out"
  chmod +x "$out" 2>/dev/null || true
}

TMP="$ROOT/build/core-dl"
rm -rf "$TMP"
mkdir -p "$TMP"

# Linux amd64
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-amd64.tar.gz" \
  -o "$TMP/linux.tar.gz"
tar xzf "$TMP/linux.tar.gz" -C "$TMP"
cp "$TMP"/sing-box-${VERSION}-linux-amd64/sing-box "$DEST/sing-box-linux-amd64"

# Windows amd64 (+ wintun.dll для TUN)
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-windows-amd64.zip" \
  -o "$TMP/win.zip"
unzip -qo "$TMP/win.zip" -d "$TMP/win"
cp "$TMP/win"/sing-box-${VERSION}-windows-amd64/sing-box.exe "$DEST/sing-box-windows-amd64.exe"
if [[ -f "$TMP/win"/sing-box-${VERSION}-windows-amd64/wintun.dll ]]; then
  cp "$TMP/win"/sing-box-${VERSION}-windows-amd64/wintun.dll "$DEST/wintun.dll"
else
  # Fallback: официальный WinTun (на случай если sing-box zip без dll)
  curl -fsSL "https://www.wintun.net/builds/wintun-0.14.1.zip" -o "$TMP/wintun.zip"
  unzip -qo "$TMP/wintun.zip" -d "$TMP/wintun"
  cp "$TMP/wintun/wintun/bin/amd64/wintun.dll" "$DEST/wintun.dll"
fi

# macOS amd64 + arm64 (universal-ish packaging)
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-amd64.tar.gz" \
  -o "$TMP/mac-amd.tar.gz"
tar xzf "$TMP/mac-amd.tar.gz" -C "$TMP"
cp "$TMP"/sing-box-${VERSION}-darwin-amd64/sing-box "$DEST/sing-box-darwin-amd64"

curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-darwin-arm64.tar.gz" \
  -o "$TMP/mac-arm.tar.gz"
tar xzf "$TMP/mac-arm.tar.gz" -C "$TMP"
cp "$TMP"/sing-box-${VERSION}-darwin-arm64/sing-box "$DEST/sing-box-darwin-arm64"

# Android arm64
curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-android-arm64.tar.gz" \
  -o "$TMP/android.tar.gz"
tar xzf "$TMP/android.tar.gz" -C "$TMP"
cp "$TMP"/sing-box-${VERSION}-android-arm64/sing-box "$DEST/sing-box-android-arm64"

echo "Готово: $DEST"
ls -lh "$DEST"
