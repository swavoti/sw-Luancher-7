package co.za.launcher3.swavoti

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // Re-warm the Flutter engine after a cold reboot or self-update.
                // android:persistent keeps the process alive at runtime; this handles
                // the initial cold-boot case where the process hasn't started yet.
                (context.applicationContext as? GoLauncherApplication)?.ensureEngineWarmed()
            }
        }
    }
}
