package co.za.launcher3.swavoti

import android.app.Application
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugins.GeneratedPluginRegistrant

class GoLauncherApplication : Application() {

    lateinit var appWidgetManager: AppWidgetManager
        private set
    lateinit var appWidgetHost: AppWidgetHost
        private set

    override fun onCreate() {
        super.onCreate()
        appWidgetManager = AppWidgetManager.getInstance(this)
        appWidgetHost = AppWidgetHost(this, APPWIDGET_HOST_ID)
        try {
            appWidgetHost.startListening()
        } catch (_: Exception) {
            // Widgets unavailable on this device — launcher still works.
        }
        ensureEngineWarmed()
    }

    fun ensureEngineWarmed() {
        if (FlutterEngineCache.getInstance().get(ENGINE_ID) != null) return

        val engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine)
        try {
            engine.platformViewsController.registry.registerViewFactory(
                "widget_view",
                WidgetViewFactory(appWidgetHost)
            )
        } catch (_: Exception) {
            // Factory already registered.
        }
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "go_launcher_engine"
        const val APPWIDGET_HOST_ID = 1024
    }
}
