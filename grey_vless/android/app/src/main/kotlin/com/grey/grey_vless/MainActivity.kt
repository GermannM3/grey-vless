package com.grey.grey_vless

import android.content.Intent
import android.net.VpnService
import android.os.Build
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
                    "startVpn" -> {
                        val configPath = call.argument<String>("configPath")
                        val binaryPath = call.argument<String>("binaryPath")
                        val proxyPort = call.argument<Int>("proxyPort") ?: 7890
                        if (configPath.isNullOrBlank() || binaryPath.isNullOrBlank()) {
                            result.error("invalid_args", "configPath/binaryPath required", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(this, GreyVpnService::class.java).apply {
                            action = GreyVpnService.ACTION_START
                            putExtra(GreyVpnService.EXTRA_CONFIG, configPath)
                            putExtra(GreyVpnService.EXTRA_BINARY, binaryPath)
                            putExtra(GreyVpnService.EXTRA_PROXY_PORT, proxyPort)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopVpn" -> {
                        val intent = Intent(this, GreyVpnService::class.java).apply {
                            action = GreyVpnService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
