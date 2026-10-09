package co.za.launcher3.swavoti

import android.app.Activity
import android.content.Context
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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
import android.graphics.RectF
import android.os.Message
import android.os.Messenger
import android.os.Parcelable
import android.view.View
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val WIDGET_CHANNEL = "co.za.launcher3.swavoti/widgets"
    private val SYSTEM_CHANNEL = "co.za.launcher3.swavoti/system"
    private val NOTIFICATION_CHANNEL = "co.za.launcher3.swavoti/notifications"
    private val MEDIA_CHANNEL = "co.za.launcher3.swavoti/media"
    private val HOME_EVENT_CHANNEL = "co.za.launcher3.swavoti/home_events"

    // Sink for firing events to Dart the instant we resume to foreground
    private var homeEventSink: EventChannel.EventSink? = null

    private val appWidgetManager: AppWidgetManager
        get() = goApp.appWidgetManager
    private val appWidgetHost: AppWidgetHost
        get() = goApp.appWidgetHost

    private val goApp: GoLauncherApplication
        get() = application as GoLauncherApplication

    private val REQUEST_BIND_APPWIDGET = 100
    private val REQUEST_CONFIGURE_APPWIDGET = 101
    private val REQUEST_PICK_WALLPAPER = 102

    private var pendingWidgetIdToBind: Int = -1
    private var pendingWidgetMethodResult: MethodChannel.Result? = null
    private var pendingWallpaperPickerResult: MethodChannel.Result? = null
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private lateinit var iconPackManager: IconPackManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        iconPackManager = IconPackManager(this)
        fulfillGestureNavContract(intent)
    }

    override fun onResume() {
        super.onResume()
        // Do not wrap Flutter's SurfaceView in a hardware layer — that blanks
        // the window for QuickStep and is a common Android 10 snap-back cause.
        window.decorView.setLayerType(View.LAYER_TYPE_NONE, null)
        reportFullyDrawn()
        homeEventSink?.success("onHomeResumed")
    }

    override fun onNewIntent(intent: Intent) {
        // Reply to the home-gesture contract immediately so QuickStep can
        // finish the recents animation instead of timing out and snapping back.
        fulfillGestureNavContract(intent)
        setIntent(intent)
        super.onNewIntent(intent)
        reportFullyDrawn()
        homeEventSink?.success("onHomeGesture")
    }

    /**
     * Quickstep sends `gesture_nav_contract_v1` with a Message callback. The
     * callback's replyTo Messenger must receive the destination bounds or the
     * system may abort the Home transition.
     */
    @Suppress("DEPRECATION")
    private fun fulfillGestureNavContract(intent: Intent) {
        try {
            val contractKey = "gesture_nav_contract_v1"
            val extras = intent.getBundleExtra(contractKey) ?: return
            intent.removeExtra(contractKey)

            val callback = extras.getParcelable<Parcelable>(
                "android.intent.extra.REMOTE_CALLBACK"
            )
            val metrics = resources.displayMetrics
            val decor = window.decorView
            val location = IntArray(2)
            decor.getLocationOnScreen(location)
            val width = decor.width.takeIf { it > 0 } ?: metrics.widthPixels
            val height = decor.height.takeIf { it > 0 } ?: metrics.heightPixels
            // A Flutter workspace can place icons dynamically, so use the launcher
            // window as a safe transition target instead of returning no target.
            val result = Bundle().apply {
                putParcelable("gesture_nav_contract_surface_control", null)
                putParcelable(
                    "gesture_nav_contract_icon_position",
                    RectF(
                        location[0].toFloat(),
                        location[1].toFloat(),
                        (location[0] + width).toFloat(),
                        (location[1] + height).toFloat()
                    )
                )
            }

            when (callback) {
                is Message -> {
                    val messenger = callback.replyTo
                    if (messenger == null) {
                        android.util.Log.w(
                            "MainActivity",
                            "Gesture navigation contract Message has no reply Messenger"
                        )
                        return
                    }
                    val reply = Message.obtain().apply {
                        copyFrom(callback)
                        data = result
                    }
                    messenger.send(reply)
                }
                is Messenger -> {
                    callback.send(Message.obtain(null, 0).apply { data = result })
                }
                else -> android.util.Log.w(
                    "MainActivity",
                    "Unsupported gesture navigation callback: ${callback?.javaClass?.name}"
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "Failed to reply to gesture navigation contract", e)
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

        // Home events channel — fires 'onHomeResumed' to Dart every time the
        // OS routes a swipe-home gesture to this Activity.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, HOME_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    homeEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    homeEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllWidgets" -> {
                    backgroundExecutor.execute {
                        val widgetList = mutableListOf<Map<String, Any>>()
                        try {
                            val providers = appWidgetManager.installedProviders
                            if (providers != null) {
                                for (info in providers) {
                                    val map = mutableMapOf<String, Any>()
                                    map["providerPackage"] = info.provider.packageName
                                    map["providerClass"] = info.provider.className
                                    map["label"] = info.loadLabel(packageManager) ?: "Widget"

                                    val previewImage = try { info.loadPreviewImage(context, 0) } catch (_: Throwable) { null }
                                    val iconImage = try { info.loadIcon(context, 0) } catch (_: Throwable) { null }

                                    val drawableToConvert = previewImage ?: iconImage
                                    if (drawableToConvert != null) {
                                        try {
                                            val bytes = drawableToByteArray(drawableToConvert)
                                            map["preview"] = bytes
                                        } catch (_: Throwable) {}
                                    }
                                    widgetList.add(map)
                                }
                            }
                        } catch (_: Throwable) {}
                        Handler(Looper.getMainLooper()).post { result.success(widgetList) }
                    }
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
                "widgetCapabilities" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    val info = if (appWidgetId != -1) {
                        appWidgetManager.getAppWidgetInfo(appWidgetId)
                    } else {
                        null
                    }
                    val resizeMode = info?.resizeMode ?: 0
                    result.success(
                        mapOf(
                            "configurable" to (info?.configure != null),
                            "resizeHorizontal" to (
                                (resizeMode and android.appwidget.AppWidgetProviderInfo.RESIZE_HORIZONTAL) != 0
                            ),
                            "resizeVertical" to (
                                (resizeMode and android.appwidget.AppWidgetProviderInfo.RESIZE_VERTICAL) != 0
                            ),
                            "minResizeWidth" to (info?.minResizeWidth ?: 0),
                            "minResizeHeight" to (info?.minResizeHeight ?: 0)
                        )
                    )
                }
                "configureWidget" -> {
                    val appWidgetId = call.argument<Int>("appWidgetId") ?: -1
                    val info = if (appWidgetId != -1) {
                        appWidgetManager.getAppWidgetInfo(appWidgetId)
                    } else {
                        null
                    }
                    if (info?.configure != null) {
                        appWidgetHost.startAppWidgetConfigureActivityForResult(
                            this,
                            appWidgetId,
                            0,
                            REQUEST_CONFIGURE_APPWIDGET,
                            Bundle()
                        )
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                                "supportsSplitScreen" -> {
                                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N)
                                }
                                "getDeviceTotalMemoryBytes" -> {
                                    val activityManager =
                                        getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                                    val memoryInfo = android.app.ActivityManager.MemoryInfo()
                                    activityManager.getMemoryInfo(memoryInfo)
                                    result.success(memoryInfo.totalMem)
                                }
                                "getAvailableIconPacks" -> {
                    backgroundExecutor.execute {
                        val packs = iconPackManager.getAvailableIconPacks()
                        Handler(Looper.getMainLooper()).post { result.success(packs) }
                    }
                }
                "getThemedIcon" -> {
                    val appPackage = call.argument<String>("appPackage") ?: ""
                    val iconPackPackage = call.argument<String>("iconPackPackage") ?: ""
                    backgroundExecutor.execute {
                        try {
                            val bytes = iconPackManager.getThemedIcon(appPackage, iconPackPackage)
                            Handler(Looper.getMainLooper()).post { result.success(bytes) }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        }
                    }
                }
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
                    val splitScreen = call.argument<Boolean>("splitScreen") ?: false
                    if (packageName != null) {
                        try {
                            val intent = packageManager.getLaunchIntentForPackage(packageName)
                            if (intent != null) {
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                if (splitScreen && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    intent.addFlags(Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
                                    intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                                }
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
                "pickWallpaperImage" -> {
                    if (pendingWallpaperPickerResult != null) {
                        result.error(
                            "PICKER_ALREADY_OPEN",
                            "A wallpaper image picker is already open.",
                            null
                        )
                    } else {
                        pendingWallpaperPickerResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "image/*"
                        }
                        try {
                            startActivityForResult(intent, REQUEST_PICK_WALLPAPER)
                        } catch (e: Exception) {
                            pendingWallpaperPickerResult = null
                            result.error("PICKER_FAILED", e.message, null)
                        }
                    }
                }
                "controlMedia" -> {
                    val action = call.argument<String>("action") ?: ""
                    val position = call.argument<Number>("positionMs")?.toLong()
                    result.success(NotificationDotService.controlMedia(action, position))
                }
                "launchMediaApp" -> {
                    val packageName = call.argument<String>("packageName")
                    val launchIntent = packageName?.let {
                        packageManager.getLaunchIntentForPackage(it)
                    }
                    if (launchIntent == null) {
                        result.success(false)
                    } else {
                        try {
                            startActivity(launchIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MEDIA_APP_LAUNCH_FAILED", e.message, null)
                        }
                    }
                }
                "showMediaOutputSwitcher" -> {
                    try {
                        val mediaOutputIntent = Intent(
                            "com.android.systemui.action.LAUNCH_MEDIA_OUTPUT_DIALOG"
                        ).setPackage("com.android.systemui")
                        startActivity(mediaOutputIntent)
                    } catch (_: Exception) {
                        try {
                            startActivity(Intent("android.settings.panel.action.VOLUME"))
                        } catch (_: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                            } catch (e: Exception) {
                                result.error("MEDIA_OUTPUT_UNAVAILABLE", e.message, null)
                                return@setMethodCallHandler
                            }
                        }
                    }
                    result.success(true)
                }
                "setWallpaperOffset" -> {
                    val offset = call.argument<Double>("offset")?.toFloat() ?: 0f
                    try {
                        val windowToken = window.decorView.windowToken
                        if (windowToken != null) {
                            android.app.WallpaperManager.getInstance(context).setWallpaperOffsets(windowToken, offset, 0f)
                        }
                    } catch (e: Exception) {}
                    result.success(null)
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
                "openAccessibilitySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ACCESSIBILITY_SETTINGS_FAILED", e.message, null)
                    }
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
                                startActivityForResult(roleIntent, 999)
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
                        } catch (e: Throwable) { }
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

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NotificationDotService.mediaListener = { media ->
                        Handler(Looper.getMainLooper()).post {
                            events?.success(media)
                        }
                    }
                    NotificationDotService.mediaListener?.invoke(
                        NotificationDotService.mediaSnapshot
                    )
                    NotificationDotService.refreshCurrentMedia()
                }

                override fun onCancel(arguments: Any?) {
                    NotificationDotService.mediaListener = null
                }
            }
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_WALLPAPER) {
            val pickerResult = pendingWallpaperPickerResult
            pendingWallpaperPickerResult = null
            if (pickerResult == null) return
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pickerResult.success(null)
                return
            }
            try {
                val uri = data.data!!
                val bounds = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                contentResolver.openInputStream(uri)?.use { input ->
                    BitmapFactory.decodeStream(input, null, bounds)
                }
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                    throw IllegalArgumentException("Selected file is not a supported image.")
                }
                var sampleSize = 1
                while (bounds.outWidth / sampleSize > 2400 ||
                    bounds.outHeight / sampleSize > 2400
                ) {
                    sampleSize *= 2
                }
                val bitmap = contentResolver.openInputStream(uri)?.use { input ->
                    BitmapFactory.decodeStream(
                        input,
                        null,
                        BitmapFactory.Options().apply { inSampleSize = sampleSize }
                    )
                } ?: throw IllegalArgumentException("Could not read the selected image.")
                val bytes = ByteArrayOutputStream().use { output ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, output)
                    output.toByteArray()
                }
                pickerResult.success(bytes)
            } catch (e: Exception) {
                pickerResult.error("WALLPAPER_READ_FAILED", e.message, null)
            }
            return
        }
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
            width = Math.max(1, (width * ratio).toInt())
            height = Math.max(1, (height * ratio).toInt())
        }

        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, canvas.width, canvas.height)
        drawable.draw(canvas)
        
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.WEBP, 80, stream)
        bitmap.recycle()
        return stream.toByteArray()
    }
}
