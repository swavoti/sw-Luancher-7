package co.za.launcher3.swavoti.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import co.za.launcher3.swavoti.R

class SmallTextClockWidgetProvider : AppWidgetProvider() {

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
            val views = RemoteViews(context.packageName, R.layout.widget_small_text_clock)
            val clockIntent = WidgetIntentHelper.createClockPendingIntent(
                context,
                requestCode = 7200 + appWidgetId
            )
            if (clockIntent != null) {
                views.setOnClickPendingIntent(R.id.small_text_clock_root, clockIntent)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
