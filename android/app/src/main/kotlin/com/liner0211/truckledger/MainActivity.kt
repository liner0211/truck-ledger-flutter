package com.liner0211.truckledger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ensureMessageChannel()
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
