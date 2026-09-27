package co.za.launcher3.swavoti

import android.appwidget.AppWidgetHost
import android.content.Context
import android.view.View
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class WidgetViewFactory(
    private val appWidgetHost: AppWidgetHost
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val appWidgetId = params?.get("appWidgetId") as? Int ?: -1
        return WidgetPlatformView(context, appWidgetHost, appWidgetId)
    }
}

class WidgetPlatformView(
    private val context: Context,
    private val appWidgetHost: AppWidgetHost,
    private val appWidgetId: Int
) : PlatformView {

    private var view: View? = null

    init {
        try {
            val appWidgetManager = android.appwidget.AppWidgetManager.getInstance(context)
            val appWidgetInfo = appWidgetManager.getAppWidgetInfo(appWidgetId)
            if (appWidgetInfo != null) {
                view = appWidgetHost.createView(context, appWidgetId, appWidgetInfo)
            }
        } catch (t: Throwable) {
            view = android.widget.FrameLayout(context)
        }
    }

    override fun getView(): View? {
        return view
    }

    override fun dispose() {
    }
}
