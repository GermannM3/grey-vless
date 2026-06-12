#!/usr/bin/env bash
# Диагностика Android-телефона через adb (Xiaomi/Samsung и др.) — без Mi Flash.
set -euo pipefail

ADB="${ADB:-adb}"
OUT="${1:-./dist/android-debug-$(date +%Y%m%d-%H%M%S)}"
PKG="com.grey.grey_vless"

mkdir -p "$OUT"

echo "=== adb devices ===" | tee "$OUT/summary.txt"
"$ADB" devices -l | tee -a "$OUT/summary.txt"

SERIAL=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
if [[ -z "$SERIAL" ]]; then
  echo "Нет авторизованного устройства. На телефоне:" | tee -a "$OUT/summary.txt"
  echo "  1. Параметры разработчика → Отладка по USB" | tee -a "$OUT/summary.txt"
  echo "  2. USB → режим «Передача файлов» или «PTP», не только зарядка" | tee -a "$OUT/summary.txt"
  echo "  3. Подтвердите «Разрешить отладку» на экране" | tee -a "$OUT/summary.txt"
  echo "  Xiaomi: дополнительно «USB debugging (Security settings)» если есть" | tee -a "$OUT/summary.txt"
  exit 1
fi

echo "Serial: $SERIAL" | tee -a "$OUT/summary.txt"

"$ADB" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r' | tee "$OUT/manufacturer.txt"
"$ADB" shell getprop ro.product.model 2>/dev/null | tr -d '\r' | tee "$OUT/model.txt"
"$ADB" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' | tee "$OUT/android_version.txt"

"$ADB" shell dumpsys package "$PKG" 2>/dev/null | grep -E 'versionName|versionCode|firstInstall|lastUpdate' | tee "$OUT/app_version.txt" || true

"$ADB" logcat -d -b crash 2>/dev/null | tail -200 > "$OUT/crash.log" || true
"$ADB" logcat -d 2>/dev/null | grep -iE 'grey_vless|GreyVpn|Singbox|sing-box|HevBridge|AndroidRuntime|FATAL' | tail -300 > "$OUT/app.log" || true

"$ADB" shell run-as "$PKG" ls -la files/ 2>/dev/null > "$OUT/app_files.txt" || echo "run-as недоступен (release APK)" > "$OUT/app_files.txt"
"$ADB" shell run-as "$PKG" ls -la code_cache/bin/ 2>/dev/null > "$OUT/code_cache_bin.txt" || true

echo "OK: отчёт в $OUT"
