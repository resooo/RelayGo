package com.relaygo.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * 保活前台服务。
 *
 * 该 App 作为本地 AI API 中转站（RelayGo），绝大多数时间在后台运行。Android 8.0+
 * 对后台服务有严格限制，只有「前台服务 + 常驻通知」才能持续运行并显著
 * 提升进程优先级，降低被系统回收的概率。
 *
 * 启动时机：
 *  - 用户启动代理服务时，由 Flutter 层通过 MethodChannel 拉起；
 *  - 开机自启时，由 [BootReceiver] 拉起。
 *
 * 使用 START_STICKY：被系统杀死后，系统会尝试重建服务，实现崩溃自愈。
 */
class KeepAliveService : Service() {

    companion object {
        private const val TAG = "KeepAliveService"
        const val CHANNEL_ID = "keep_alive"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "com.relaygo.app.action.START"
        const val ACTION_STOP = "com.relaygo.app.action.STOP"

        /** 启动前台保活服务（Android 8.0+ 需 startForegroundService） */
        fun start(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java)
                .setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        /** 停止前台保活服务 */
        fun stop(context: Context) {
            val intent = Intent(context, KeepAliveService::class.java)
                .setAction(ACTION_STOP)
            context.startService(intent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                startAsForeground()
                // START_STICKY：进程被系统回收后尝试重建，配合 BootReceiver 实现自愈
                return START_STICKY
            }
        }
    }

    private fun startAsForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("RelayGo")
            .setContentText("代理服务正在后台运行")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pending)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun createChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "保活服务",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "保持代理服务在后台持续运行"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
