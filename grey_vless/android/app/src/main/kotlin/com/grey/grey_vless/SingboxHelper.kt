package com.grey.grey_vless

import android.content.Context
import android.system.Os
import android.util.Log
import java.io.File
import java.io.IOException

object SingboxHelper {
    private const val TAG = "SingboxHelper"
    private const val BIN_NAME = "sing-box"

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

    fun check(binaryPath: String, configPath: String): Map<String, Any> {
        val process = ProcessBuilder(binaryPath, "check", "-c", configPath)
            .redirectErrorStream(true)
            .start()
        val output = process.inputStream.bufferedReader().readText()
        val code = process.waitFor()
        return mapOf("exitCode" to code, "output" to output.trim())
    }

    @Volatile
    private var proxyProcess: Process? = null

    fun startProxy(binaryPath: String, configPath: String) {
        stopProxy()
        proxyProcess = ProcessBuilder(binaryPath, "run", "-c", configPath)
            .redirectErrorStream(true)
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
}
