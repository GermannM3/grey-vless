package com.grey.grey_vless

object HevBridge {
    private var loadAttempted = false
    private var loadOk = false

    fun isAvailable(): Boolean {
        ensureLoaded()
        return loadOk
    }

    private fun ensureLoaded() {
        if (loadAttempted) return
        loadAttempted = true
        try {
            // hev-socks5-tunnel нельзя грузить напрямую — JNI_OnLoad падает без своего Java-класса.
            // grey_hev_bridge подтягивает libhev-socks5-tunnel.so как зависимость линковки.
            System.loadLibrary("grey_hev_bridge")
            loadOk = nativeHasRealHev()
        } catch (_: UnsatisfiedLinkError) {
            loadOk = false
        } catch (_: Exception) {
            loadOk = false
        }
    }

    @Volatile
    private var running = false

    fun runBlocking(configPath: String, tunFd: Int) {
        if (!isAvailable()) {
            throw UnsatisfiedLinkError("hev-socks5-tunnel unavailable")
        }
        running = true
        try {
            nativeRun(configPath, tunFd)
        } finally {
            running = false
        }
    }

    fun stop() {
        if (running && loadOk) {
            nativeStop()
        }
    }

    private external fun nativeHasRealHev(): Boolean
    private external fun nativeRun(configPath: String, tunFd: Int): Int
    private external fun nativeStop()
}
