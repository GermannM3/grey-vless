package com.grey.grey_vless

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.grey.vless/android"
    private var vpnPermissionResult: MethodChannel.Result? = null

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VPN_REQUEST_CODE) {
            vpnPermissionResult?.success(resultCode == Activity.RESULT_OK)
            vpnPermissionResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isHevAvailable" -> result.success(HevBridge.isAvailable())
                    "prepareSingboxBinary" -> {
                        try {
                            val ready = SingboxHelper.resolveBinary(applicationContext)
                            result.success(ready)
                        } catch (e: Exception) {
                            result.error("prepare_failed", e.message, null)
                        }
                    }
                    "prepareSingboxConfig" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "Path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val ready = SingboxHelper.prepareConfig(applicationContext, path)
                            result.success(ready)
                        } catch (e: Exception) {
                            result.error("prepare_failed", e.message, null)
                        }
                    }
                    "chmodExecutable" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "Path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            SingboxHelper.prepareExecutable(applicationContext, path)
                            result.success(true)
                        } catch (_: Exception) {
                            val file = File(path)
                            val ok = file.exists() && file.setReadable(true, false) && file.setExecutable(true, false)
                            result.success(ok && file.canExecute())
                        }
                    }
                    "singboxCheck" -> {
                        val binaryPath = call.argument<String>("binaryPath")
                        val configPath = call.argument<String>("configPath")
                        if (binaryPath.isNullOrBlank() || configPath.isNullOrBlank()) {
                            result.error("invalid_args", "binaryPath/configPath required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(SingboxHelper.check(applicationContext, binaryPath, configPath))
                        } catch (e: Exception) {
                            result.error("check_failed", e.message, null)
                        }
                    }
                    "singboxStart" -> {
                        val binaryPath = call.argument<String>("binaryPath")
                        val configPath = call.argument<String>("configPath")
                        if (binaryPath.isNullOrBlank() || configPath.isNullOrBlank()) {
                            result.error("invalid_args", "binaryPath/configPath required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val readyConfig = SingboxHelper.prepareConfig(applicationContext, configPath)
                            val readyBinary = SingboxHelper.resolveBinary(applicationContext)
                            SingboxHelper.startProxy(applicationContext, readyBinary, readyConfig)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("start_failed", e.message, null)
                        }
                    }
                    "singboxStop" -> {
                        SingboxHelper.stopProxy()
                        result.success(true)
                    }
                    "singboxIsRunning" -> result.success(SingboxHelper.isProxyRunning())
                    "isVpnActive" -> result.success(GreyVpnService.isActive())
                    "isOtherVpnActive" -> result.success(isOtherVpnActive())
                    "singboxLastLog" -> result.success(SingboxHelper.getLastLog(applicationContext))
                    "listInstalledApps" -> {
                        try {
                            result.success(listInstalledApps())
                        } catch (e: Exception) {
                            result.error("list_failed", e.message, null)
                        }
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        result.success(requestIgnoreBatteryOptimizations())
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "prepareVpn" -> {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            if (vpnPermissionResult != null) {
                                result.error("busy", "VPN permission request already pending", null)
                                return@setMethodCallHandler
                            }
                            vpnPermissionResult = result
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, VPN_REQUEST_CODE)
                        } else {
                            result.success(true)
                        }
                    }
                    "startVpn" -> {
                        val configPath = call.argument<String>("configPath")
                        val binaryPath = call.argument<String>("binaryPath")
                        val proxyPort = call.argument<Int>("proxyPort") ?: 7890
                        @Suppress("UNCHECKED_CAST")
                        val allowed = (call.argument<List<*>>("allowedApps") ?: emptyList<Any>())
                            .mapNotNull { it?.toString() }
                        @Suppress("UNCHECKED_CAST")
                        val disallowed = (call.argument<List<*>>("disallowedApps") ?: emptyList<Any>())
                            .mapNotNull { it?.toString() }
                        if (configPath.isNullOrBlank() || binaryPath.isNullOrBlank()) {
                            result.error("invalid_args", "configPath/binaryPath required", null)
                            return@setMethodCallHandler
                        }
                        if (!HevBridge.isAvailable()) {
                            result.error("no_hev", "TUN bridge not available on this device", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val readyConfig = SingboxHelper.prepareConfig(applicationContext, configPath)
                            val readyBinary = SingboxHelper.prepareExecutable(applicationContext, binaryPath)
                            val intent = Intent(this, GreyVpnService::class.java).apply {
                                action = GreyVpnService.ACTION_START
                                putExtra(GreyVpnService.EXTRA_CONFIG, readyConfig)
                                putExtra(GreyVpnService.EXTRA_BINARY, readyBinary)
                                putExtra(GreyVpnService.EXTRA_PROXY_PORT, proxyPort)
                                putStringArrayListExtra(GreyVpnService.EXTRA_ALLOWED, ArrayList(allowed))
                                putStringArrayListExtra(GreyVpnService.EXTRA_DISALLOWED, ArrayList(disallowed))
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("start_failed", e.message, null)
                        }
                    }
                    "stopVpn" -> {
                        val intent = Intent(this, GreyVpnService::class.java).apply {
                            action = GreyVpnService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid_path", "Path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("missing", "APK not found", null)
                                return@setMethodCallHandler
                            }
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                file,
                            )
                            val intent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        // Не трогаем VPN-сервис — он живёт отдельно при выключенном экране.
        // Proxy-only процесс тоже оставляем, если пользователь отключил VPN явно через stop.
        if (!GreyVpnService.isActive()) {
            // Нельзя стопать proxy при повороте/пересоздании Activity — только если процесс умирает.
            // onDestroy вызывается и при смене конфигурации; не убиваем proxy здесь.
        }
        super.onDestroy()
    }

    private fun listInstalledApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            PackageManager.MATCH_UNINSTALLED_PACKAGES
        } else {
            0
        }
        val apps = pm.getInstalledApplications(flag)
        val out = ArrayList<Map<String, Any?>>(apps.size)
        for (info in apps) {
            if (info.packageName == packageName) continue
            val label = try {
                pm.getApplicationLabel(info).toString()
            } catch (_: Exception) {
                info.packageName
            }
            val system = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            // Показываем launchable и крупные system apps с иконкой/лейблом
            val launch = pm.getLaunchIntentForPackage(info.packageName)
            if (launch == null && system) continue
            out.add(
                mapOf(
                    "package" to info.packageName,
                    "label" to label,
                    "system" to system,
                ),
            )
        }
        out.sortBy { (it["label"] as? String)?.lowercase() ?: "" }
        return out
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (isIgnoringBatteryOptimizations()) return true
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    /** Другой VPN-профиль активен (не Grey vless). */
    private fun isOtherVpnActive(): Boolean {
        if (GreyVpnService.isActive() || SingboxHelper.isProxyRunning()) {
            return false
        }
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                return true
            }
        }
        return false
    }

    companion object {
        private const val VPN_REQUEST_CODE = 1001
    }
}
