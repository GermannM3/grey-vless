#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="$ROOT/tools/android-sdk"
mkdir -p "$SDK/cmdline-tools"

if [ ! -d "$SDK/cmdline-tools/latest" ]; then
  echo "==> Загрузка Android command-line tools..."
  TMP=$(mktemp -d)
  curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$TMP/cmdtools.zip"
  unzip -qo "$TMP/cmdtools.zip" -d "$TMP"
  rm -rf "$SDK/cmdline-tools/latest"
  mv "$TMP/cmdline-tools" "$SDK/cmdline-tools/latest"
  rm -rf "$TMP"
fi

export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

yes | sdkmanager --licenses >/dev/null 2>&1 || yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" "ndk;27.0.12077973"

echo "ANDROID_HOME=$SDK"
