package com.grey.grey_vless

import android.content.Context
import android.system.Os
import android.util.Log
import java.io.File
import java.io.IOException

object SingboxHelper {
    private const val TAG = "SingboxHelper"
    private const val BIN_NAME = "sing-box"
    private const val LOG_NAME = "singbox-last.log"

    /** Копирует бинарник в codeCacheDir — на Xiaomi/Samsung из files/ exec часто запрещён. */
    fun prepareExecutable(context: Context, sourcePath: String): String {
        val source = File(sourcePath)
        if (!source.exists()) {
            throw IOException("sing-box не найден: $sourcePath")
        }

        val binDir = File(context.codeCacheDir, "bin").apply { mkdirs() }
        val dest = File(binDir, BIN_NAME)

        source.inputStream().use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }

        dest.setReadable(true, false)
        dest.setWritable(true, true)
        dest.setExecutable(true, false)
        try {
            Os.chmod(dest.absolutePath, 493) // 0755
        } catch (e: Exception) {
            Log.w(TAG, "Os.chmod failed, using File flags only", e)
        }

        if (!dest.canExecute()) {
            throw IOException("Не удалось сделать sing-box исполняемым на этом устройстве")
        }
        return dest.absolutePath
    }

    /** Конфиг тоже в codeCacheDir — temp/files иногда недоступны для нативного процесса. */
    fun prepareConfig(context: Context, sourcePath: String): String {
        val source = File(sourcePath)
        if (!source.exists()) {
            throw IOException("Конфиг не найден: $sourcePath")
        }
        val configDir = File(context.codeCacheDir, "configs").apply { mkdirs() }
        val dest = File(configDir, "active-${System.currentTimeMillis()}.json")
        source.copyTo(dest, overwrite = true)
        dest.setReadable(true, false)
        return dest.absolutePath
    }

    fun check(binaryPath: String, configPath: String): Map<String, Any> {
        val process = ProcessBuilder(binaryPath, "check", "-c", configPath)
            .redirectErrorStream(true)
            .directory(File(binaryPath).parentFile)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        val code = process.waitFor()
        return mapOf("exitCode" to code, "output" to output.trim())
    }

    @Volatile
    private var proxyProcess: Process? = null

    fun startProxy(context: Context, binaryPath: String, configPath: String) {
        stopProxy()
        val logFile = File(context.codeCacheDir, LOG_NAME)
        logFile.writeText("")
        proxyProcess = ProcessBuilder(binaryPath, "run", "-c", configPath)
            .redirectErrorStream(true)
            .redirectOutput(ProcessBuilder.Redirect.appendTo(logFile))
            .directory(File(binaryPath).parentFile)
            .start()
    }

    fun stopProxy() {
        val proc = proxyProcess ?: return
        proxyProcess = null
        proc.destroy()
        try {
            proc.waitFor()
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
