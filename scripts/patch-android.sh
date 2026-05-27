#!/usr/bin/env bash
set -euo pipefail
# Run after: flutter create ... --platforms=android

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIN="$ROOT/grey_vless/android/app/src/main/kotlin/com/grey/grey_vless/MainActivity.kt"
MANIFEST="$ROOT/grey_vless/android/app/src/main/AndroidManifest.xml"

if [ ! -f "$MAIN" ]; then
  echo "MainActivity not found. Run flutter create first."
  exit 1
fi

if ! grep -q "com.grey.vless/proxy" "$MAIN"; then
  cat >> "$MAIN" <<'KOTLIN'

// Grey vless proxy channel (local sing-box SOCKS)
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.net.VpnService

class GreyVlessPlugin {
  companion object {
    fun register(flutterEngine: FlutterEngine, activity: MainActivity) {
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.grey.vless/proxy")
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "enable" -> {
              val intent = VpnService.prepare(activity)
              if (intent != null) activity.startActivityForResult(intent, 44)
              result.success(true)
            }
            "disable" -> result.success(true)
            else -> result.notImplemented()
          }
        }
    }
  }
}
KOTLIN
fi

grep -q 'android.permission.INTERNET' "$MANIFEST" || sed -i '0,/<manifest/{//a\
    <uses-permission android:name="android.permission.INTERNET"/>\
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
}' "$MANIFEST" 2>/dev/null || true

echo "Android patch applied"
