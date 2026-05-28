package com.grey.grey_vless

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import java.io.File

/** Запуск sing-box в контексте VPN-сервиса (TUN на Android). */
class GreyVpnService : VpnService() {
    private var process: Process? = null

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
                if (configPath.isNullOrBlank() || binaryPath.isNullOrBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForeground(NOTIF_ID, buildNotification())
                stopTunnel()

                val binary = File(binaryPath)
                if (binary.exists()) {
                    binary.setReadable(true, false)
                    binary.setExecutable(true, false)
                }

                try {
                    process = ProcessBuilder(binaryPath, "run", "-c", configPath)
                        .redirectErrorStream(true)
                        .start()
                } catch (e: Exception) {
                    stopTunnel()
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        return START_STICKY
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
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setContentTitle("Grey vless")
            .setContentText("VPN активен")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    private fun stopTunnel() {
        process?.destroy()
        try {
            process?.waitFor()
        } catch (_: InterruptedException) {
        }
        process = null
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
        private const val NOTIF_ID = 42
        private const val CHANNEL_ID = "grey_vless_vpn"
    }
}
