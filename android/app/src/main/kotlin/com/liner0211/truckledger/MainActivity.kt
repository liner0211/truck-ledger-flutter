package com.liner0211.truckledger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowInsets
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 内容画到屏幕边缘，系统栏透明叠加（真正全屏）
        WindowCompat.setDecorFitsSystemWindows(window, false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
        super.onCreate(savedInstanceState)
        ensureMessageChannel()
    }

    // Flutter 3.29+：关闭深链接，避免极光厂商通道离线点击白屏
    override fun shouldHandleDeeplinking(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.liner0211.truckledger/system_nav",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getBottomNavInfo") {
                result.success(
                    mapOf(
                        "mode" to navigationMode(),
                        "heightPx" to navigationBarHeightPx(),
                    ),
                )
            } else {
                result.notImplemented()
            }
        }
    }

    /** 0=三键, 1=两键, 2=手势 */
    private fun navigationMode(): Int {
        return try {
            Settings.Secure.getInt(contentResolver, "navigation_mode")
        } catch (_: Settings.SettingNotFoundException) {
            val id = resources.getIdentifier(
                "config_navBarInteractionMode",
                "integer",
                "android",
            )
            if (id > 0) resources.getInteger(id) else 0
        } catch (_: Exception) {
            0
        }
    }

    private fun navigationBarHeightPx(): Int {
        val insets = window.decorView.rootWindowInsets ?: return 0
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.getInsets(WindowInsets.Type.navigationBars()).bottom
        } else {
            @Suppress("DEPRECATION")
            insets.systemWindowInsetBottom
        }
    }

    private fun ensureMessageChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            "messages",
            "消息",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "站内信、客服与聊天通知"
        }
        nm.createNotificationChannel(channel)
    }
}
