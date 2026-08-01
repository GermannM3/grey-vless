package com.grey.grey_vless

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class GreyVpnService : VpnService() {
    private var tunInterface: ParcelFileDescriptor? = null
    private var singboxProcess: Process? = null
    private var hevThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wakeRenew: ScheduledFuture<*>? = null
    private val stopping = AtomicBoolean(false)
    private val worker = Executors.newSingleThreadExecutor()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        active = this
    }

    override fun onDestroy() {
        active = null
        stopTunnel()
        worker.shutdownNow()
        scheduler.shutdownNow()
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.w(TAG, "VPN revoked by system")
        clearPersisted()
        stopTunnel()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onRevoke()
    }

    companion object {
        private const val TAG = "GreyVpnService"
        const val ACTION_START = "com.grey.grey_vless.vpn.START"
        const val ACTION_STOP = "com.grey.grey_vless.vpn.STOP"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_BINARY = "binary"
        const val EXTRA_PROXY_PORT = "proxy_port"
        const val EXTRA_ALLOWED = "allowed_apps"
        const val EXTRA_DISALLOWED = "disallowed_apps"
        private const val NOTIF_ID = 42
        private const val CHANNEL_ID = "grey_vless_vpn"
        private const val PREFS = "grey_vpn_state"
        private const val K_CONFIG = "config"
        private const val K_BINARY = "binary"
        private const val K_PORT = "proxy_port"
        private const val K_ALLOWED = "allowed"
        private const val K_DISALLOWED = "disallowed"
        private const val K_ACTIVE = "active"

        @Volatile
        private var active: GreyVpnService? = null

        fun isActive(): Boolean {
            val svc = active ?: return false
            return svc.tunInterface != null && svc.singboxProcess?.isAlive == true
        }
    }

    private fun prefs(): SharedPreferences =
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun persistStart(
        config: String,
        binary: String,
        port: Int,
        allowed: List<String>,
        disallowed: List<String>,
    ) {
        prefs().edit()
            .putBoolean(K_ACTIVE, true)
            .putString(K_CONFIG, config)
            .putString(K_BINARY, binary)
            .putInt(K_PORT, port)
            .putString(K_ALLOWED, allowed.joinToString("\n"))
            .putString(K_DISALLOWED, disallowed.joinToString("\n"))
            .apply()
    }

    private fun clearPersisted() {
        prefs().edit().clear().apply()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                clearPersisted()
                stopTunnel()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val configPath = intent.getStringExtra(EXTRA_CONFIG)
                val binaryPath = intent.getStringExtra(EXTRA_BINARY)
                val proxyPort = intent.getIntExtra(EXTRA_PROXY_PORT, 7890)
                val allowed = intent.getStringArrayListExtra(EXTRA_ALLOWED) ?: arrayListOf()
                val disallowed = intent.getStringArrayListExtra(EXTRA_DISALLOWED) ?: arrayListOf()
                if (configPath.isNullOrBlank() || binaryPath.isNullOrBlank()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                return beginStart(configPath, binaryPath, proxyPort, allowed, disallowed)
            }
            else -> {
                // START_STICKY restart без intent — восстанавливаем из prefs.
                val p = prefs()
                if (!p.getBoolean(K_ACTIVE, false)) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                val configPath = p.getString(K_CONFIG, null)
                val binaryPath = p.getString(K_BINARY, null)
                val proxyPort = p.getInt(K_PORT, 7890)
                val allowed = p.getString(K_ALLOWED, "")!!.lines().filter { it.isNotBlank() }
                val disallowed = p.getString(K_DISALLOWED, "")!!.lines().filter { it.isNotBlank() }
                if (configPath.isNullOrBlank() || binaryPath.isNullOrBlank()) {
                    clearPersisted()
                    stopSelf()
                    return START_NOT_STICKY
                }
                Log.i(TAG, "Sticky restart — восстанавливаем VPN")
                return beginStart(configPath, binaryPath, proxyPort, allowed, disallowed)
            }
        }
    }

    private fun beginStart(
        configPath: String,
        binaryPath: String,
        proxyPort: Int,
        allowed: List<String>,
        disallowed: List<String>,
    ): Int {
        stopping.set(false)
        try {
            startForeground(NOTIF_ID, buildNotification())
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
            return START_NOT_STICKY
        }
        persistStart(configPath, binaryPath, proxyPort, allowed, disallowed)
        worker.execute {
            try {
                stopTunnel()
                stopping.set(false)
                acquireWakeLock()
                startVpnTunnel(configPath, binaryPath, proxyPort, allowed, disallowed)
            } catch (e: Exception) {
                Log.e(TAG, "VPN start failed", e)
                stopTunnel()
                clearPersisted()
                mainHandler.post {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
        return START_STICKY
    }

    private fun acquireWakeLock() {
        releaseWakeLock()
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GreyVless:Vpn").apply {
            setReferenceCounted(false)
            acquire(60 * 60 * 1000L) // 1 час, ниже renew каждые 30 мин
        }
        wakeRenew?.cancel(false)
        wakeRenew = scheduler.scheduleAtFixedRate({
            try {
                if (isActive()) {
                    wakeLock?.acquire(60 * 60 * 1000L)
                }
            } catch (e: Exception) {
                Log.w(TAG, "wake renew failed", e)
            }
        }, 30, 30, TimeUnit.MINUTES)
    }

    private fun releaseWakeLock() {
        wakeRenew?.cancel(false)
        wakeRenew = null
        try {
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun startVpnTunnel(
        configPath: String,
        binaryPath: String,
        proxyPort: Int,
        allowed: List<String>,
        disallowed: List<String>,
    ) {
        if (!File(configPath).exists() || !File(binaryPath).exists()) {
            throw IllegalStateException("config/binary missing after restart")
        }

        singboxProcess = ProcessBuilder(binaryPath, "run", "-c", configPath)
            .redirectErrorStream(true)
            .directory(File(binaryPath).parentFile)
            .start()

        // Не на main thread — sleep ок.
        var alive = false
        for (i in 0 until 20) {
            Thread.sleep(100)
            if (singboxProcess?.isAlive == true) {
                alive = true
                break
            }
        }
        if (!alive) {
            throw IllegalStateException("sing-box не запустился")
        }

        if (!HevBridge.isAvailable()) {
            throw IllegalStateException("TUN-мост недоступен на этом устройстве")
        }

        val builder = Builder()
            .setSession("Grey vless")
            .addAddress("172.19.0.1", 30)
            .addRoute("0.0.0.0", 0)
            .addRoute("128.0.0.0", 1)
            .addRoute("::", 0)
            .addDnsServer("8.8.8.8")
            .addDnsServer("1.1.1.1")
            .setMtu(1500)
            .setBlocking(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        if (allowed.isNotEmpty()) {
            for (pkg in allowed) {
                try {
                    builder.addAllowedApplication(pkg)
                } catch (e: Exception) {
                    Log.w(TAG, "addAllowedApplication $pkg failed", e)
                }
            }
        } else {
            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.w(TAG, "addDisallowedApplication self failed", e)
            }
            for (pkg in disallowed) {
                if (pkg == packageName) continue
                try {
                    builder.addDisallowedApplication(pkg)
                } catch (e: Exception) {
                    Log.w(TAG, "addDisallowedApplication $pkg failed", e)
                }
            }
        }

        tunInterface = builder.establish()

        if (tunInterface == null) {
            throw IllegalStateException("VpnService.establish() вернул null")
        }

        val hevConfig = """
            tunnel:
              name: tun0
              mtu: 1500
              ipv4: 172.19.0.1
            socks5:
              port: $proxyPort
              address: 127.0.0.1
              udp: 'udp'
        """.trimIndent()

        val hevFile = File(filesDir, "hev-socks5.yml")
        hevFile.writeText(hevConfig)

        val tunFd = tunInterface!!.fd
        hevThread = Thread {
            try {
                HevBridge.runBlocking(hevFile.absolutePath, tunFd)
            } catch (e: Exception) {
                Log.e(TAG, "hev tunnel stopped", e)
            }
        }.apply {
            name = "hev-tun2socks"
            isDaemon = false
            start()
        }
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Grey vless VPN",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Держит VPN активным при выключенном экране"
                setShowBadge(false)
            }
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
            .setContentText("VPN активен — экран может быть выключен")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private fun stopTunnel() {
        if (!stopping.compareAndSet(false, true)) return
        try {
            HevBridge.stop()
        } catch (_: Exception) {
        }
        hevThread?.interrupt()
        try {
            hevThread?.join(2000)
        } catch (_: Exception) {
        }
        hevThread = null
        val proc = singboxProcess
        singboxProcess = null
        if (proc != null) {
            proc.destroy()
            try {
                if (!proc.waitFor(3, TimeUnit.SECONDS)) {
                    proc.destroyForcibly()
                }
            } catch (_: Exception) {
                try {
                    proc.destroyForcibly()
                } catch (_: Exception) {
                }
            }
        }
        try {
            tunInterface?.close()
        } catch (_: Exception) {
        }
        tunInterface = null
        releaseWakeLock()
        stopping.set(false)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
