package com.grey.grey_vless

import android.content.Context
import android.util.Log
import java.io.File
import java.io.IOException

object SingboxHelper {
    private const val TAG = "SingboxHelper"
    private const val LIB_NAME = "libsingbox.so"
    private const val LOG_NAME = "singbox-last.log"

    /**
     * sing-box упакован как libsingbox.so в jniLibs — Android разрешает exec только из nativeLibraryDir.
     * codeCacheDir/files на Samsung часто дают error=13 Permission denied.
     */
    fun resolveBinary(context: Context): String {
        val nativeBin = File(context.applicationInfo.nativeLibraryDir, LIB_NAME)
        if (nativeBin.exists() && nativeBin.length() > 0) {
            return nativeBin.absolutePath
        }
        throw IOException(
            "sing-box ($LIB_NAME) не найден в APK. Переустановите приложение из последнего релиза.",
        )
    }

    /** @deprecated Используйте resolveBinary. Оставлено для совместимости с Dart. */
    fun prepareExecutable(context: Context, @Suppress("UNUSED_PARAMETER") sourcePath: String): String =
        resolveBinary(context)

    fun prepareConfig(context: Context, sourcePath: String): String {
        val source = File(sourcePath)
        if (!source.exists()) {
            throw IOException("Конфиг не найден: $sourcePath")
        }
        val configDir = File(context.codeCacheDir, "configs").apply { mkdirs() }
        // Один active.json — не копить active-*.json
        configDir.listFiles()?.forEach { f ->
            if (f.name.startsWith("active-") && f.name.endsWith(".json")) {
                try {
                    f.delete()
                } catch (_: Exception) {
                }
            }
        }
        val dest = File(configDir, "active.json")
        source.copyTo(dest, overwrite = true)
        dest.setReadable(true, false)
        return dest.absolutePath
    }

    fun check(context: Context, binaryPath: String, configPath: String): Map<String, Any> {
        val binary = if (File(binaryPath).exists()) binaryPath else resolveBinary(context)
        return try {
            val process = ProcessBuilder(binary, "check", "-c", configPath)
                .redirectErrorStream(true)
                .directory(File(binary).parentFile)
                .start()
            val output = StringBuilder()
            val reader = Thread {
                try {
                    process.inputStream.bufferedReader().use { br ->
                        var line: String?
                        while (br.readLine().also { line = it } != null) {
                            output.appendLine(line)
                        }
                    }
                } catch (_: Exception) {
                }
            }.apply { isDaemon = true; start() }
            val finished = process.waitFor(8, java.util.concurrent.TimeUnit.SECONDS)
            if (!finished) {
                process.destroyForcibly()
                reader.join(500)
                return mapOf("exitCode" to 1, "output" to "sing-box check timeout")
            }
            reader.join(1000)
            mapOf("exitCode" to process.exitValue(), "output" to output.toString().trim())
        } catch (e: Exception) {
            Log.e(TAG, "singbox check failed", e)
            mapOf("exitCode" to 1, "output" to (e.message ?: "Permission denied"))
        }
    }

    @Volatile
    private var proxyProcess: Process? = null

    fun startProxy(context: Context, binaryPath: String, configPath: String) {
        stopProxy()
        val binary = if (File(binaryPath).exists()) binaryPath else resolveBinary(context)
        val logFile = File(context.codeCacheDir, LOG_NAME)
        logFile.writeText("")
        proxyProcess = ProcessBuilder(binary, "run", "-c", configPath)
            .redirectErrorStream(true)
            .redirectOutput(ProcessBuilder.Redirect.appendTo(logFile))
            .directory(File(binary).parentFile)
            .start()
    }

    fun stopProxy() {
        val proc = proxyProcess ?: return
        proxyProcess = null
        proc.destroy()
        try {
            if (!proc.waitFor(3, java.util.concurrent.TimeUnit.SECONDS)) {
                proc.destroyForcibly()
            }
        } catch (_: InterruptedException) {
            proc.destroyForcibly()
        }
    }

    fun isProxyRunning(): Boolean = proxyProcess?.isAlive == true

    fun getLastLog(context: Context): String {
        val logFile = File(context.codeCacheDir, LOG_NAME)
        if (!logFile.exists()) return ""
        return logFile.readText().takeLast(2000).trim()
    }
}
