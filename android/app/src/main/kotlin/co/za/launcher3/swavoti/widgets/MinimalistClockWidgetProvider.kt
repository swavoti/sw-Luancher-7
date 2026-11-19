package co.za.launcher3.swavoti.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import co.za.launcher3.swavoti.R

class MinimalistClockWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_minimalist_clock)
            val clockIntent = WidgetIntentHelper.createClockPendingIntent(
                context,
                requestCode = 7100 + appWidgetId
            )
            if (clockIntent != null) {
                views.setOnClickPendingIntent(R.id.minimalist_clock_root, clockIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
