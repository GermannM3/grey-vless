#!/usr/bin/env bash
# Сборка libhev-socks5-tunnel.so для Android arm64 (нужен Android NDK).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEV_TAG="2.15.0"
JNI_LIBS="$ROOT/grey_vless/android/app/src/main/jniLibs/arm64-v8a"
TMP="$ROOT/build/hev-android"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK:-${NDK_HOME:-}}}"

if [[ -z "$NDK" && -d "$ROOT/tools/android-sdk/ndk" ]]; then
  NDK="$(find "$ROOT/tools/android-sdk/ndk" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1)"
fi
if [[ -z "$NDK" ]]; then
  echo "ANDROID_NDK_HOME не задан — пропуск сборки hev"
  exit 0
fi

export PATH="$NDK:$PATH"
mkdir -p "$TMP" "$JNI_LIBS"
rm -rf "$TMP/src"
git clone --depth 1 --branch "$HEV_TAG" --recursive https://github.com/heiher/hev-socks5-tunnel "$TMP/src"

cd "$TMP/src"
"$NDK/ndk-build" \
  NDK_PROJECT_PATH=. \
  APP_BUILD_SCRIPT=Android.mk \
  APP_ABI=arm64-v8a \
  NDK_LIBS_OUT="$TMP/libs" \
  NDK_OUT="$TMP/obj"

cp -f "$TMP/libs/arm64-v8a/libhev-socks5-tunnel.so" "$JNI_LIBS/"
INCLUDE_DIR="$ROOT/grey_vless/android/app/src/main/cpp/hev-include"
mkdir -p "$INCLUDE_DIR"
cp -f "$TMP/src/src/hev-main.h" "$INCLUDE_DIR/"
echo "OK: $JNI_LIBS/libhev-socks5-tunnel.so"
