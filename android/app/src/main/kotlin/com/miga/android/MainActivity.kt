package com.miga.android

import android.Manifest
import android.app.AppOpsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 除了 Flutter 自身的插件注册，这里只多挂一个方法通道：
 * 让 Dart 侧能控制后台剪贴板监听服务、并查询「后台能不能读剪贴板」。
 */
class MainActivity : FlutterFragmentActivity() {

    private var channel: MethodChannel? = null

    /** 通知点击带过来的「载入剪贴板」请求；由 Dart 侧 pull 走（避免冷启动时丢事件） */
    private var pendingLoadRequest = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (intent?.getBooleanExtra(EXTRA_LOAD_CLIPBOARD, false) == true) {
            pendingLoadRequest = true
        }
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startWatchService()
                        result.success(true)
                    }

                    "stop" -> {
                        stopService(Intent(this@MainActivity, ClipboardWatchService::class.java))
                        result.success(true)
                    }

                    "isRunning" -> result.success(ClipboardWatchService.isRunning)

                    "canReadInBackground" -> result.success(canReadClipboardInBackground())

                    "requestNotificationPermission" -> {
                        requestNotificationPermission()
                        result.success(true)
                    }

                    "hasNotificationPermission" ->
                        result.success(hasNotificationPermission())

                    "consumeLoadRequest" -> {
                        val pending = pendingLoadRequest
                        pendingLoadRequest = false
                        result.success(pending)
                    }

                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_LOAD_CLIPBOARD, false)) {
            pendingLoadRequest = true
            // App 还活着（退在后台）时立即通知 Dart，不用等 resume 轮询
            channel?.invokeMethod("loadRequested", null)
        }
    }

    private fun startWatchService() {
        val intent = Intent(this, ClipboardWatchService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /** READ_CLIPBOARD 这个 app-op 是否已允许（Android 10 以下没有这个限制） */
    private fun canReadClipboardInBackground(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true
        val appOps = getSystemService(AppOpsManager::class.java) ?: return false
        val mode = appOps.unsafeCheckOpNoThrow(
            // AppOpsManager.OPSTR_READ_CLIPBOARD 是 @hide，只能写字面量
            "android:read_clipboard",
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (hasNotificationPermission()) return
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }

    companion object {
        const val CHANNEL = "miga/clipboard_watch"
        const val EXTRA_LOAD_CLIPBOARD = "miga_load_clipboard"
        private const val REQUEST_NOTIFICATIONS = 4201
    }
}
