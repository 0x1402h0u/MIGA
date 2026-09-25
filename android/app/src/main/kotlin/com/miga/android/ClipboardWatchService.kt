package com.miga.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * 后台剪贴板监听：前台服务保活 + 定时读剪贴板，命中牌桌数据就发横幅通知。
 *
 * Android 10+ 默认禁止后台读剪贴板（ClipboardService 按调用方焦点判定，直接拒），
 * 必须先给应用打开 READ_CLIPBOARD 这个 app-op：
 *
 *     adb shell appops set com.miga.android READ_CLIPBOARD allow
 *
 * 没打开时读取返回空 → 这里自然什么都不做，不会误报、不会崩。
 * 命中判定只做粗筛（行数 + 三个关键词），严格解析仍在 Dart 侧完成。
 */
class ClipboardWatchService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var lastText: String? = null
    private var lastBannerAt = 0L

    private val poll = object : Runnable {
        override fun run() {
            checkClipboard()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        ensureChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        startForegroundCompat()
        handler.removeCallbacks(poll)
        handler.postDelayed(poll, POLL_INTERVAL_MS)
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        handler.removeCallbacks(poll)
        super.onDestroy()
    }

    // ---- 服务本体 ----

    private fun startForegroundCompat() {
        val notification = buildPersistentNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                PERSISTENT_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(PERSISTENT_ID, notification)
        }
    }

    private fun checkClipboard() {
        val manager =
            getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
        val clip = manager.primaryClip ?: return
        if (clip.itemCount == 0) return
        val text = clip.getItemAt(0).coerceToText(this)?.toString() ?: return
        if (text.isBlank() || text == lastText) return
        lastText = text
        if (!looksLikeBoard(text)) return
        val now = System.currentTimeMillis()
        if (now - lastBannerAt < BANNER_COOLDOWN_MS) return
        lastBannerAt = now
        notifyBanner()
    }

    /** 粗筛：够长、且含这三个关键词就认为「像对局数据」 */
    private fun looksLikeBoard(text: String): Boolean {
        if (text.count { it == '\n' } < MIN_LINES) return false
        return text.contains("骨头") && text.contains("手牌数") && text.contains("天平")
    }

    // ---- 通知 ----

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_PERSISTENT,
                "后台剪贴板监听",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "常驻通知，用于保持后台监听"
                setShowBadge(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_BANNER,
                "牌桌数据提醒",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "检测到剪贴板里是牌桌数据时弹出"
            },
        )
    }

    private fun builder(channelId: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun activityIntent(loadClipboard: Boolean): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (loadClipboard) putExtra(MainActivity.EXTRA_LOAD_CLIPBOARD, true)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(this, if (loadClipboard) 1 else 0, intent, flags)
    }

    private fun buildPersistentNotification(): Notification {
        val stop = PendingIntent.getService(
            this,
            2,
            Intent(this, ClipboardWatchService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }),
        )
        return builder(CHANNEL_PERSISTENT)
            .setSmallIcon(R.drawable.ic_clipboard_watch)
            .setContentTitle("MIGA 正在监听剪贴板")
            .setContentText("在游戏里复制牌桌数据，这里会提醒你导入")
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(activityIntent(false))
            .addAction(0, "停止", stop)
            .build()
    }

    private fun notifyBanner() {
        val notification = builder(CHANNEL_BANNER)
            .setSmallIcon(R.drawable.ic_clipboard_watch)
            .setContentTitle("检测到牌桌数据")
            .setContentText("点这里回到 MIGA 并载入")
            .setAutoCancel(true)
            .setContentIntent(activityIntent(true))
            .build()
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(BANNER_ID, notification)
    }

    companion object {
        const val ACTION_STOP = "com.miga.android.action.STOP_WATCH"
        const val CHANNEL_PERSISTENT = "miga_clipboard_watch"
        const val CHANNEL_BANNER = "miga_clipboard_banner"
        const val PERSISTENT_ID = 1001
        const val BANNER_ID = 1002

        /** 供 Dart 侧查询服务是否在跑（同进程，直接用静态标记） */
        @Volatile
        var isRunning: Boolean = false
            private set

        private const val POLL_INTERVAL_MS = 1200L
        private const val BANNER_COOLDOWN_MS = 3000L
        private const val MIN_LINES = 8
    }
}
