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

    /**
     * Копирует конфиг в filesDir (не codeCache — система может чистить).
     * Никогда не делает copy файла в самого себя (иначе ENOENT / пустой файл).
     */
    fun prepareConfig(context: Context, sourcePath: String): String {
        val source = File(sourcePath)
        if (!source.exists() || source.length() == 0L) {
            throw IOException("Конфиг не найден: $sourcePath")
        }
        // filesDir стабильнее codeCacheDir (тот OS чистит → ENOENT).
        val configDir = File(context.filesDir, "configs").apply { mkdirs() }
        val dest = File(configDir, "active.json")

        val srcCanon = try {
            source.canonicalPath
        } catch (_: Exception) {
            source.absolutePath
        }
        val dstCanon = try {
            dest.canonicalPath
        } catch (_: Exception) {
            dest.absolutePath
        }

        if (srcCanon == dstCanon) {
            // Уже наш active.json — не копируем сам в себя.
            dest.setReadable(true, false)
            return dest.absolutePath
        }

        // Пишем через temp + rename, чтобы не было полупустого active.json.
        val tmp = File(configDir, "active.tmp")
        try {
            if (tmp.exists()) tmp.delete()
            source.copyTo(tmp, overwrite = true)
            if (dest.exists()) dest.delete()
            if (!tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true)
                tmp.delete()
            }
        } catch (e: Exception) {
            try {
                tmp.delete()
            } catch (_: Exception) {
            }
            throw IOException("Не удалось сохранить конфиг: ${e.message}", e)
        }

        dest.setReadable(true, false)
        if (!dest.exists() || dest.length() == 0L) {
            throw IOException("Конфиг пуст после копирования: ${dest.absolutePath}")
        }

        // Старые active-*.json из прошлых сборок.
        configDir.listFiles()?.forEach { f ->
            if (f.name.startsWith("active-") && f.name.endsWith(".json")) {
                try {
                    f.delete()
                } catch (_: Exception) {
                }
            }
        }
        // codeCache configs — подчистить, чтобы не путаться со старым путём.
        try {
            File(context.codeCacheDir, "configs").listFiles()?.forEach { f ->
                try {
                    f.delete()
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }

        Log.i(TAG, "config ready: ${dest.absolutePath} (${dest.length()} bytes)")
        return dest.absolutePath
    }

    fun check(context: Context, binaryPath: String, configPath: String): Map<String, Any> {
        val binary = if (File(binaryPath).exists()) binaryPath else resolveBinary(context)
        val cfg = File(configPath)
        if (!cfg.exists()) {
            return mapOf("exitCode" to 1, "output" to "config missing: $configPath")
        }
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
        val readyConfig = prepareConfig(context, configPath)
        val logFile = File(context.filesDir, LOG_NAME)
        logFile.writeText("")
        proxyProcess = ProcessBuilder(binary, "run", "-c", readyConfig)
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
        val primary = File(context.filesDir, LOG_NAME)
        val fallback = File(context.codeCacheDir, LOG_NAME)
        val logFile = when {
            primary.exists() -> primary
            fallback.exists() -> fallback
            else -> return ""
        }
        return logFile.readText().takeLast(2000).trim()
    }
}
