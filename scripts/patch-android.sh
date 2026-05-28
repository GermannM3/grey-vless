#!/usr/bin/env bash
# Android fixes are now in repo sources (MainActivity + AndroidManifest).
# This script only verifies required files exist.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test -f "$ROOT/grey_vless/android/app/src/main/AndroidManifest.xml"
grep -q 'android.permission.INTERNET' "$ROOT/grey_vless/android/app/src/main/AndroidManifest.xml"
grep -q 'chmodExecutable' "$ROOT/grey_vless/android/app/src/main/kotlin/com/grey/grey_vless/MainActivity.kt"
echo "Android patch OK"
