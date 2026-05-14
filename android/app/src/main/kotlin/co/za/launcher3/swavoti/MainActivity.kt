package co.za.launcher3.swavoti

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.ByteArrayOutputStream
import android.os.Handler
import android.os.Looper
import android.graphics.Rect
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController

class MainActivity : FlutterActivity() {

    private val WIDGET_CHANNEL = "co.za.launcher3.swavoti/widgets"
    private val SYSTEM_CHANNEL = "co.za.launcher3.swavoti/system"
    private val NOTIFICATION_CHANNEL = "co.za.launcher3.swavoti/notifications"

    private val appWidgetManager: AppWidgetManager
        get() = goApp.appWidgetManager
    private val appWidgetHost: AppWidgetHost
        get() = goApp.appWidgetHost

    private val goApp: GoLauncherApplication
        get() = application as GoLauncherApplication

    private val REQUEST_BIND_APPWIDGET = 100

    private var pendingWidgetIdToBind: Int = -1
    private var pendingWidgetMethodResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 10+ (Q): exclude the full bottom of the window from system
        // gesture handling so the OS home-gesture zone cannot steal touches that
        // we use for the app-drawer drag.  We set it after the first layout pass
        // so the window size is already known.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.decorView.viewTreeObserver.addOnGlobalLayoutListener {
                val height = window.decorView.height
                val width  = window.decorView.width
                // Exclude left/right edges (back gestures) and full bottom strip
                window.decorView.systemGestureExclusionRects = listOf(
                    Rect(0, height - 200, width, height)  // bottom 200 px
                )
            }
        }
    }

    override fun getCachedEngineId(): String = GoLauncherApplication.ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun onDestroy() {
        // Do not destroy the cached Flutter engine — android:persistent keeps
        // this process alive so the engine survives lock/unlock naturally.
        super.onDestroy()
    }


    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            flutterEngine.platformViewsController.registry.registerViewFactory(
                "widget_view",
                WidgetViewFactory(appWidgetHost)
            )
        } catch (_: Exception) {
            // Already registered on the cached engine.
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllWidgets" -> {
                    val widgetList = mutableListOf<Map<String, Any>>()
                    try {
                        val providers = appWidgetManager.installedProviders
                        if (providers != null) {
                            for (info in providers) {
                                val map = mutableMapOf<String, Any>()
                                map["providerPackage"] = info.provider.packageName
                                map["providerClass"] = info.provider.className
                                map["label"] = info.loadLabel(packageManager) ?: "Widget"
                                
                                val previewImage = try { info.loadPreviewImage(context, 0) } catch (e: Exception) { null }
                                val iconImage = try { info.loadIcon(context, 0) } catch (e: Exception) { null }
                                
                                val drawableToConvert = previewImage ?: iconImage
                                if (drawableToConvert != null) {
                                    try {
                                        val bytes = drawableToByteArray(drawableToConvert)
                                        map["preview"] = bytes
                                    } catch (e: Exception) {
                                        // Ignore preview if drawable conversion fails
                                    }
                                }
                                widgetList.add(map)
                            }
                        }
                    } catch (e: Exception) {
                        // Return empty list if installedProviders query fails
                    }
                    result.success(widgetList)
                }
                "allocateWidgetId" -> {
                    val id = appWidgetHost.allocateAppWidgetId()
                    result.success(id)
                }
                "bindWidget" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    val providerPackage = call.argument<String>("providerPackage") ?: ""
                    val providerClass = call.argument<String>("providerClass") ?: ""

                    if (appWidgetId != -1 && providerPackage.isNotEmpty()) {
                        val provider = ComponentName(providerPackage, providerClass)
                        val success = appWidgetManager.bindAppWidgetIdIfAllowed(appWidgetId, provider)
                        if (success) {
                            result.success(true)
                        } else {
                            // Request permission
                            pendingWidgetIdToBind = appWidgetId
                            pendingWidgetMethodResult = result
                            val intent = Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
                            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, provider)
                            startActivityForResult(intent, REQUEST_BIND_APPWIDGET)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Missing arguments", null)
                    }
                }
                "deleteWidgetId" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    if (appWidgetId != -1) {
                        appWidgetHost.deleteAppWidgetId(appWidgetId)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "uninstallApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val intent = Intent(Intent.ACTION_DELETE)
                        intent.data = Uri.parse("package:$packageName")
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "startApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        try {
                            val intent = packageManager.getLaunchIntentForPackage(packageName)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "appInfo" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        intent.data = Uri.parse("package:$packageName")
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "changeWallpaper" -> {
                    val intent = Intent(Intent.ACTION_SET_WALLPAPER)
                    startActivity(Intent.createChooser(intent, "Select Wallpaper"))
                    result.success(null)
                }
                "setWallpaper" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val type = call.argument<Int>("type") ?: 3
                    if (bytes != null) {
                        try {
                            val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            val wm = android.app.WallpaperManager.getInstance(context)
                            var flags = 0
                            if (type == 1 || type == 3) flags = flags or android.app.WallpaperManager.FLAG_SYSTEM
                            if (type == 2 || type == 3) flags = flags or android.app.WallpaperManager.FLAG_LOCK
                            wm.setBitmap(bitmap, null, true, flags)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "openGoogleDiscover" -> {
                    try {
                        val intent = Intent(Intent.ACTION_MAIN)
                        intent.setClassName("com.google.android.googlequicksearchbox", "com.google.android.apps.gsa.staticplugins.opa.OpaActivity")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    } catch (e: Exception) {
                        try {
                            val intent2 = Intent(Intent.ACTION_MAIN)
                            intent2.setPackage("com.google.android.googlequicksearchbox")
                            startActivity(intent2)
                        } catch (e2: Exception) {}
                    }
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    try {
                        val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                        startActivity(intent)
                    } catch (e: Exception) {}
                    result.success(null)
                }
                "isDefaultLauncher" -> {
                    try {
                        val intent = Intent(Intent.ACTION_MAIN)
                        intent.addCategory(Intent.CATEGORY_HOME)
                        val resolveInfo = packageManager.resolveActivity(
                            intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
                        )
                        val isDefault = resolveInfo?.activityInfo?.packageName == packageName
                        result.success(isDefault)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openDefaultLauncherSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(android.app.role.RoleManager::class.java)
                            if (roleManager != null && !roleManager.isRoleHeld(android.app.role.RoleManager.ROLE_HOME)) {
                                val roleIntent = roleManager.createRequestRoleIntent(android.app.role.RoleManager.ROLE_HOME)
                                startActivity(roleIntent)
                            }
                        } else {
                            val intent = Intent(Settings.ACTION_HOME_SETTINGS)
                            startActivity(intent)
                        }
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
                        } catch (_: Exception) {}
                    }
                    result.success(null)
                }
                "launchGoogleWeather" -> {
                    try {
                        // Method 1: Exported Activity
                        val intent = Intent(Intent.ACTION_MAIN)
                        intent.setClassName("com.google.android.googlequicksearchbox", "com.google.android.apps.search.weather.WeatherExportedActivity")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    } catch (e: Exception) {
                        try {
                            // Method 2: Deep Link
                            val intent2 = Intent(Intent.ACTION_VIEW)
                            intent2.data = Uri.parse("dynact://velour/weather/ProxyActivity")
                            intent2.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent2)
                        } catch (e2: Exception) {
                            try {
                                // Method 3: Deep Shortcut
                                val intent3 = Intent(Intent.ACTION_MAIN)
                                intent3.setPackage("com.google.android.googlequicksearchbox")
                                intent3.putExtra("s.shortcut_id", "Weather")
                                intent3.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent3)
                            } catch (e3: Exception) {
                                // Fallback fails
                            }
                        }
                    }
                    result.success(null)
                }
                "shareApp" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName != null) {
                        val sendIntent: Intent = Intent().apply {
                            action = Intent.ACTION_SEND
                            putExtra(Intent.EXTRA_TEXT, "Check out this app: https://play.google.com/store/apps/details?id=$packageName")
                            type = "text/plain"
                        }
                        val shareIntent = Intent.createChooser(sendIntent, null)
                        shareIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(shareIntent)
                    }
                    result.success(null)
                }
                "openUrlInBrowser" -> {
                    val url = call.argument<String>("url")
                    val packageName = call.argument<String>("packageName")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            if (packageName != null && packageName.isNotEmpty()) {
                                intent.setPackage(packageName)
                            }
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        } catch (_: Exception) {}
                    }
                    result.success(null)
                }
                "getInstalledBrowsers" -> {
                    val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse("http://www.google.com"))
                    val resolveInfos = packageManager.queryIntentActivities(browserIntent, android.content.pm.PackageManager.MATCH_ALL)
                    val browsers = mutableListOf<Map<String, Any>>()
                    for (info in resolveInfos) {
                        try {
                            val appInfo = packageManager.getApplicationInfo(info.activityInfo.packageName, 0)
                            val label = packageManager.getApplicationLabel(appInfo).toString()
                            val icon = packageManager.getApplicationIcon(appInfo)
                            val iconBytes = drawableToByteArray(icon)
                            
                            val map = mapOf(
                                "packageName" to info.activityInfo.packageName,
                                "label" to label,
                                "icon" to iconBytes
                            )
                            if (browsers.none { it["packageName"] == info.activityInfo.packageName }) {
                                browsers.add(map)
                            }
                        } catch (e: Exception) { }
                    }
                    result.success(browsers)
                }
                "expandNotifications" -> {
                    try {
                        @Suppress("DEPRECATION")
                        val sbService = getSystemService("statusbar")
                        val sbClass = Class.forName("android.app.StatusBarManager")
                        val expandMethod = sbClass.getMethod("expandNotificationsPanel")
                        expandMethod.invoke(sbService)
                    } catch (_: Exception) {}
                    result.success(null)
                }
                "openGoogleVoiceSearch" -> {
                    try {
                        val intent = Intent(Intent.ACTION_VOICE_COMMAND)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    } catch (_: Exception) {
                        try {
                            val intent2 = Intent("android.speech.action.VOICE_SEARCH_HANDS_FREE")
                            intent2.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent2)
                        } catch (_: Exception) {}
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NotificationDotService.listener = { map ->
                        Handler(Looper.getMainLooper()).post {
                            events?.success(map)
                        }
                    }
                    // Trigger initial
                    NotificationDotService.listener?.invoke(NotificationDotService.notificationCounts)
                }

                override fun onCancel(arguments: Any?) {
                    NotificationDotService.listener = null
                }
            }
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_BIND_APPWIDGET) {
            if (resultCode == Activity.RESULT_OK) {
                pendingWidgetMethodResult?.success(true)
            } else {
                if (pendingWidgetIdToBind != -1) {
                    appWidgetHost.deleteAppWidgetId(pendingWidgetIdToBind)
                }
                pendingWidgetMethodResult?.success(false)
            }
            pendingWidgetIdToBind = -1
            pendingWidgetMethodResult = null
        }
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        var width = Math.max(1, drawable.intrinsicWidth)
        var height = Math.max(1, drawable.intrinsicHeight)
        
        // Scale down large drawables to prevent OOM / TransactionTooLargeException
        val maxSize = 150
        if (width > maxSize || height > maxSize) {
            val ratio = Math.min(maxSize.toFloat() / width, maxSize.toFloat() / height)
            width = (width * ratio).toInt()
            height = (height * ratio).toInt()
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.WEBP, 80, stream)
        return stream.toByteArray()
    }
}
