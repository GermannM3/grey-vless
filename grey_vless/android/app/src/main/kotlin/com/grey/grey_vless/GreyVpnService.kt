package com.grey.grey_vless

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Полный VPN: VpnService (иконка в статус-баре) + sing-box (mixed) + hev (tun→socks5).
 */
class GreyVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null
    private var singboxProcess: Process? = null
    private var hevThread: Thread? = null
    private val stopping = AtomicBoolean(false)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTunnel()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val configPath = intent.getStringExtra(EXTRA_CONFIG)
                val binaryPath = intent.getStringExtra(EXTRA_BINARY)
                val proxyPort = intent.getIntExtra(EXTRA_PROXY_PORT, 7890)
                if (configPath.isNullOrBlank() || binaryPath.isNullOrBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                stopping.set(false)
                startForeground(NOTIF_ID, buildNotification())
                stopTunnel()

                try {
                    startVpnTunnel(configPath, binaryPath, proxyPort)
                } catch (e: Exception) {
                    stopTunnel()
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        return START_STICKY
    }

    private fun startVpnTunnel(configPath: String, binaryPath: String, proxyPort: Int) {
        val binary = File(binaryPath)
        if (binary.exists()) {
            binary.setReadable(true, false)
            binary.setExecutable(true, false)
        }

        tunInterface = Builder()
            .setSession("Grey vless")
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addRoute("128.0.0.0", 1)
            .addDnsServer("8.8.8.8")
            .addDnsServer("1.1.1.1")
            .setMtu(1500)
            .setBlocking(false)
            .establish()

        if (tunInterface == null) {
            throw IllegalStateException("VpnService.establish() вернул null")
        }

        singboxProcess = ProcessBuilder(binaryPath, "run", "-c", configPath)
            .redirectErrorStream(true)
            .start()

        Thread.sleep(800)

        val hevConfig = """
            tunnel:
              name: tun0
              mtu: 1500
              ipv4: 172.19.0.1
            socks5:
              port: $proxyPort
              address: 127.0.0.1
              udp: 'tcp'
        """.trimIndent()

        val hevFile = File(filesDir, "hev-socks5.yml")
        hevFile.writeText(hevConfig)

        val tunFd = tunInterface!!.fd
        hevThread = Thread {
            try {
                HevBridge.runBlocking(hevFile.absolutePath, tunFd)
            } catch (_: UnsatisfiedLinkError) {
                // lib не собрана — VPN-иконка есть, туннеля нет
            }
        }.apply {
            name = "hev-tun2socks"
            start()
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Grey vless VPN",
                NotificationManager.IMPORTANCE_LOW,
            )
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Grey vless")
            .setContentText("VPN активен")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    private fun stopTunnel() {
        if (!stopping.compareAndSet(false, true)) return
        HevBridge.stop()
        hevThread?.interrupt()
        hevThread = null
        singboxProcess?.destroy()
        try {
            singboxProcess?.waitFor()
        } catch (_: InterruptedException) {
        }
        singboxProcess = null
        tunInterface?.close()
        tunInterface = null
        stopping.set(false)
    }

    override fun onDestroy() {
        stopTunnel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.grey.grey_vless.vpn.START"
        const val ACTION_STOP = "com.grey.grey_vless.vpn.STOP"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_BINARY = "binary"
        const val EXTRA_PROXY_PORT = "proxy_port"
        private const val NOTIF_ID = 42
        private const val CHANNEL_ID = "grey_vless_vpn"
    }
}
