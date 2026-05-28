package com.grey.grey_vless

object HevBridge {
    init {
        System.loadLibrary("hev-socks5-tunnel")
        System.loadLibrary("grey_hev_bridge")
    }

    @Volatile
    private var running = false

    fun runBlocking(configPath: String, tunFd: Int) {
        running = true
        try {
            nativeRun(configPath, tunFd)
        } finally {
            running = false
        }
    }

    fun stop() {
        if (running) {
            nativeStop()
        }
    }

    private external fun nativeRun(configPath: String, tunFd: Int): Int
    private external fun nativeStop()
}
