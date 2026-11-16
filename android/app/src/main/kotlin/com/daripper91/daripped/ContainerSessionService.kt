package com.daripper91.daripped

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
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

class ContainerSessionService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        if (action == ACTION_STOP) {
            stopContainerService()
            return START_NOT_STICKY
        }

        startForegroundServiceInternal()
        return START_STICKY
    }

    private fun startForegroundServiceInternal() {
        acquireWakeLock()

        val notification = buildNotification()
        val notificationId = NOTIFICATION_ID

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_NONE)
        } else {
            startForeground(notificationId, notification)
        }
        Log.i(TAG, "ContainerSessionService started in foreground")
    }

    private fun stopContainerService() {
        releaseWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
        Log.i(TAG, "ContainerSessionService stopped")
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock == null || wakeLock?.isHeld == false) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "IntelNode:ContainerSession")?.apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to acquire wake lock", t)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to release wake lock", t)
        } finally {
            wakeLock = null
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "IntelNode Container Runtime",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Linux container processes and X11 display server active in background"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingLaunch = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, ContainerSessionService::class.java).apply {
            action = ACTION_STOP
        }
        val pendingStop = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("IntelNode Desktop Active")
            .setContentText("Container runtime & X11 display running")
            .setSmallIcon(R.mipmap.launcher_icon)
            .setOngoing(true)
            .setContentIntent(pendingLaunch)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", pendingStop)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val TAG = "ContainerSessionService"
        const val CHANNEL_ID = "intelnode_container_runtime"
        const val NOTIFICATION_ID = 47190
        const val ACTION_START = "com.daripper91.daripped.ACTION_START_CONTAINER_SERVICE"
        const val ACTION_STOP = "com.daripper91.daripped.ACTION_STOP_CONTAINER_SERVICE"

        fun start(context: Context) {
            try {
                val intent = Intent(context, ContainerSessionService::class.java).apply {
                    action = ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to start ContainerSessionService", t)
            }
        }

        fun stop(context: Context) {
            try {
                val intent = Intent(context, ContainerSessionService::class.java).apply {
                    action = ACTION_STOP
                }
                context.startService(intent)
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to stop ContainerSessionService", t)
            }
        }
    }
}
