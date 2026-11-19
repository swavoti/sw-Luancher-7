package co.za.launcher3.swavoti.widgets

import android.app.PendingIntent
import android.app.usage.UsageStatsManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import android.view.View
import android.widget.RemoteViews
import co.za.launcher3.swavoti.R
import java.util.Calendar

class SmartFolderTimeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action
        if (action == ACTION_REFRESH_SMART_FOLDER || action == Intent.ACTION_USER_PRESENT) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, SmartFolderTimeWidgetProvider::class.java)
            )
            for (id in ids) {
                updateWidget(context, manager, id)
            }
        }
    }

    private data class AppSlotEntry(
        val packageName: String,
        val label: String,
        val usageMillis: Long
    )

    companion object {
        const val ACTION_REFRESH_SMART_FOLDER =
            "co.za.launcher3.swavoti.ACTION_REFRESH_SMART_FOLDER"

        private val SLOT_IDS = intArrayOf(
            R.id.smart_app_slot_0,
            R.id.smart_app_slot_1,
            R.id.smart_app_slot_2,
            R.id.smart_app_slot_3
        )
        private val ICON_IDS = intArrayOf(
            R.id.smart_app_icon_0,
            R.id.smart_app_icon_1,
            R.id.smart_app_icon_2,
            R.id.smart_app_icon_3
        )
        private val LABEL_IDS = intArrayOf(
            R.id.smart_app_label_0,
            R.id.smart_app_label_1,
            R.id.smart_app_label_2,
            R.id.smart_app_label_3
        )

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_smart_folder_time)
            val hasUsageAccess = WidgetIntentHelper.hasUsageStatsPermission(context)

            val (totalMillis, entries) = loadSmartAppEntries(context, hasUsageAccess)

            if (hasUsageAccess) {
                views.setTextViewText(
                    R.id.smart_folder_screen_time,
                    "Today · ${WidgetIntentHelper.formatDuration(totalMillis)}"
                )
            } else {
                views.setTextViewText(
                    R.id.smart_folder_screen_time,
                    "Screen Time · Enable"
                )
            }

            // Tap pill: open Usage Access settings if not granted, or Digital Wellbeing / Usage settings
            val headerIntent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val headerPending = PendingIntent.getActivity(
                context,
                7300 + appWidgetId,
                headerIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.smart_folder_time_pill, headerPending)

            // Refresh button
            val refreshIntent = Intent(context, SmartFolderTimeWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_SMART_FOLDER
            }
            val refreshPending = PendingIntent.getBroadcast(
                context,
                7400 + appWidgetId,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.smart_folder_refresh_btn, refreshPending)

            val pm = context.packageManager
            for (i in 0 until 4) {
                val entry = entries.getOrNull(i)
                if (entry == null) {
                    views.setViewVisibility(SLOT_IDS[i], View.INVISIBLE)
                    continue
                }

                views.setViewVisibility(SLOT_IDS[i], View.VISIBLE)
                val subtitle = if (hasUsageAccess && entry.usageMillis >= 60_000L) {
                    WidgetIntentHelper.formatDuration(entry.usageMillis)
                } else {
                    entry.label
                }
                views.setTextViewText(LABEL_IDS[i], subtitle)

                try {
                    val iconDrawable = pm.getApplicationIcon(entry.packageName)
                    val bitmap = WidgetIntentHelper.drawableToCompactBitmap(iconDrawable, sizePx = 96)
                    views.setImageViewBitmap(ICON_IDS[i], bitmap)
                } catch (_: Throwable) {
                    views.setImageViewResource(ICON_IDS[i], R.mipmap.ic_launcher)
                }

                val launchIntent = pm.getLaunchIntentForPackage(entry.packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                }
                if (launchIntent != null) {
                    val launchPending = PendingIntent.getActivity(
                        context,
                        7500 + appWidgetId * 10 + i,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(SLOT_IDS[i], launchPending)
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun loadSmartAppEntries(
            context: Context,
            hasUsageAccess: Boolean
        ): Pair<Long, List<AppSlotEntry>> {
            val pm = context.packageManager
            val selfPackage = context.packageName

            val launchableIntent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolveInfos = pm.queryIntentActivities(launchableIntent, PackageManager.MATCH_ALL)
            val launchableApps = linkedMapOf<String, String>()
            for (ri in resolveInfos) {
                val pkg = ri.activityInfo?.packageName ?: continue
                if (pkg == selfPackage || launchableApps.containsKey(pkg)) continue
                val label = ri.loadLabel(pm)?.toString()?.trim().orEmpty()
                launchableApps[pkg] = if (label.isNotEmpty()) label else pkg.substringAfterLast('.')
            }

            var totalUsageMillis = 0L
            val ranked = mutableListOf<AppSlotEntry>()

            if (hasUsageAccess) {
                val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
                if (usm != null) {
                    val cal = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, 0)
                        set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    val startOfDay = cal.timeInMillis
                    val now = System.currentTimeMillis()
                    val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, startOfDay, now)

                    val aggregated = mutableMapOf<String, Long>()
                    if (stats != null) {
                        for (s in stats) {
                            val pkg = s.packageName ?: continue
                            if (pkg == selfPackage || !launchableApps.containsKey(pkg)) continue
                            val fg = s.totalTimeInForeground
                            if (fg > 0) {
                                aggregated[pkg] = (aggregated[pkg] ?: 0L) + fg
                            }
                        }
                    }

                    for ((pkg, ms) in aggregated) {
                        totalUsageMillis += ms
                        ranked.add(AppSlotEntry(pkg, launchableApps[pkg] ?: pkg, ms))
                    }
                    ranked.sortByDescending { it.usageMillis }
                }
            }

            val result = ranked.take(4).toMutableList()
            if (result.size < 4) {
                val alreadyAdded = result.map { it.packageName }.toSet()
                for ((pkg, label) in launchableApps) {
                    if (result.size >= 4) break
                    if (pkg !in alreadyAdded) {
                        result.add(AppSlotEntry(pkg, label, 0L))
                    }
                }
            }

            return Pair(totalUsageMillis, result)
        }
    }
}
