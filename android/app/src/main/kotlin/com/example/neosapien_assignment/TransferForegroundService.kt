package com.example.neosapien_assignment

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class TransferForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "NeoSapien Transfer"
        val message = intent?.getStringExtra(EXTRA_MESSAGE) ?: "Transfer in progress"
        return try {
            createChannelIfNeeded()
            val notification = buildNotification(title, message)
            startForeground(NOTIFICATION_ID, notification)
            START_STICKY
        } catch (t: Throwable) {
            android.util.Log.e("NeoSapienFG", "Foreground service start failed", t)
            stopSelf()
            START_NOT_STICKY
        }
    }

    private fun buildNotification(title: String, message: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setColor(0xFF3ECF8E.toInt())
            .setContentTitle(title)
            .setContentText(message)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "NeoSapien Transfers",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Ongoing upload or download"
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "neosapien_transfer_fg_v2"
        const val NOTIFICATION_ID = 7701
        const val EXTRA_TITLE = "title"
        const val EXTRA_MESSAGE = "message"
    }
}
