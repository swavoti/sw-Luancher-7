package co.za.launcher3.swavoti

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
 * Play-Store-compliant on-demand keep-alive foreground service using `shortService`.
 *
 * Started ONLY while `MainActivity` is in the foreground right as the user launches
 * an external app, and stopped immediately in `MainActivity.onResume()` when they
 * return home. Using `FOREGROUND_SERVICE_TYPE_SHORT_SERVICE` keeps the launcher
 * process out of Android's Cached App Freezer during app switches without needing
 * restricted foreground service declarations in Play Console.
 */
class LauncherKeepAliveService : Service() {

    companion object {
        private const val CHANNEL_ID = "swavoti_keep_alive"
        private const val NOTIFICATION_ID = 7001

        @Volatile
        private var isRunning = false

        fun start(context: Context) {
            if (isRunning) return
            val intent = Intent(context.applicationContext, LauncherKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.applicationContext.startForegroundService(intent)
                } else {
                    context.applicationContext.startService(intent)
                }
            } catch (e: Throwable) {
                android.util.Log.w("LauncherKeepAliveService", "Could not start keep-alive service", e)
            }
        }

        fun stop(context: Context) {
            if (!isRunning) return
            isRunning = false
            try {
                context.applicationContext.stopService(
                    Intent(context.applicationContext, LauncherKeepAliveService::class.java)
                )
            } catch (_: Throwable) {
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        promoteToForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isRunning = true
        promoteToForeground()
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        isRunning = false
        stopSelf(startId)
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun promoteToForeground() {
        ensureNotificationChannel()

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_HOME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingFlags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle("sw Launcher 7")
            .setContentText("Keeping home screen ready")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_DEFERRED)
                }
            }
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Throwable) {
            android.util.Log.w("LauncherKeepAliveService", "startForeground failed", e)
            stopSelf()
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Home Screen Quick Return",
            NotificationManager.IMPORTANCE_MIN
        ).apply {
            description = "Temporarily keeps the home screen warm while switching apps"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }
}
