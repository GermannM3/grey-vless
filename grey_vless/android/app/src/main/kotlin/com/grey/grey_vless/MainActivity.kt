package com.grey.grey_vless

import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.grey.vless/android"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "chmodExecutable" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "Path is empty", null)
                            return@setMethodCallHandler
                        }
                        val file = File(path)
                        val ok = file.exists() && file.setReadable(true, false) && file.setExecutable(true, false)
                        result.success(ok && file.canExecute())
                    }
                    "prepareVpn" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            startActivityForResult(intent, 44)
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
