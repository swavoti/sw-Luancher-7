package co.za.launcher3.swavoti

import android.app.Activity
import android.app.ActivityOptions
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
import android.view.Choreographer
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
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
    private val REQUEST_AUDIO_PERMISSION = 104
    private val REQUEST_DELETE_AUDIO = 105

    private var pendingWidgetIdToBind: Int = -1
    private var pendingWidgetMethodResult: MethodChannel.Result? = null
    private var pendingWallpaperPickerResult: MethodChannel.Result? = null
    private var pendingAudioPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteAudioResult: MethodChannel.Result? = null
    private var pendingDeleteAudioTrackId: Long = -1L
    // lastLaunchedAppRect lives in GoLauncherApplication.Companion so that
    // MyAccessibilityService (same process, different class) can also read it.
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    // Icon work is a mix of PackageManager I/O (cold APK resource reads) and
    // CPU (rasterise + WEBP encode). 2–4 workers throttled a 200-app batch to
    // several seconds, so allow up to 8 and keep a decoded-bytes LRU so a
    // re-request never re-rasterises an icon we already produced.
    private val iconExecutor = Executors.newFixedThreadPool(
        Runtime.getRuntime().availableProcessors().coerceIn(4, 8)
    )
    private val iconBytesCache = android.util.LruCache<String, ByteArray>(384)
    private lateinit var iconPackManager: IconPackManager
    private var homeSnapshotShield: HomeSnapshotShieldView? = null
    private val mainUiHandler = Handler(Looper.getMainLooper())
    private var pendingResumeShieldRelease: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        iconPackManager = IconPackManager(this)
        NotificationDotService.ensureGlobalLegacyReceiver(this)

        val shield = HomeSnapshotShieldView(this)
        addContentView(
            shield,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        homeSnapshotShield = shield

        // Pre-wake Flutter's GPU surface the instant the user touches the bottom gesture strip
        // (~200ms before finger-up) so the Home frame is already hot in VRAM.
        LauncherSceneStore.onHomeSwipeTouchDownCallback = {
            mainUiHandler.post {
                keepFlutterSurfaceAliveAndHot(resumeLifecycle = true)
            }
        }
        LauncherSceneStore.onHomeSwipeCancelledCallback = {
            mainUiHandler.post {
                if (!hasWindowFocus()) {
                    flutterEngine?.lifecycleChannel?.appIsInactive()
                }
            }
        }

        fulfillGestureNavContract(intent)
    }

    override fun shouldDispatchAppLifecycleState(): Boolean = false

    private fun keepFlutterSurfaceAliveAndHot(resumeLifecycle: Boolean) {
        findViewById<View>(FLUTTER_VIEW_ID)?.let { fv ->
            if (fv.visibility != View.VISIBLE) {
                fv.visibility = View.VISIBLE
            }
        }
        flutterEngine?.renderer?.restoreSurfaceProducers()
        if (resumeLifecycle) {
            flutterEngine?.lifecycleChannel?.appIsResumed()
        }
    }

    override fun onPause() {
        if (LauncherSceneStore.isCleanHomeVisible) {
            captureHomeUiSnapshotIfReady()
        }
        if (!LauncherSceneStore.isSubRouteOpen) {
            homeSnapshotShield?.armIfSnapshotAvailable()
        }
        LauncherSceneStore.markHomeTransitionStarting()
        super.onPause()
        flutterEngine?.lifecycleChannel?.appIsInactive()
    }

    override fun onStop() {
        super.onStop()
        // CRITICAL LAUNCHER FIX: FlutterActivity.onStop() sets FlutterView to View.GONE and
        // calls onTrimMemory(TRIM_MEMORY_BACKGROUND), which destroys FlutterTextureView's
        // SurfaceTexture and forces a 1-2s cold GPU texture rebuild when swiping home.
        // Restoring View.VISIBLE synchronously before the next traversal keeps the Home
        // GPU surface permanently resident in RAM/VRAM like a native stock launcher.
        keepFlutterSurfaceAliveAndHot(resumeLifecycle = false)
    }

    override fun onResume() {
        super.onResume()
        keepFlutterSurfaceAliveAndHot(resumeLifecycle = true)
        LauncherSceneStore.homeResumeEpoch.incrementAndGet()
        LauncherSceneStore.activeForegroundPackage = packageName
        NotificationDotService.refreshCurrentMedia()
        homeEventSink?.success("onHomeResumed")
        if (hasWindowFocus()) {
            schedulePostResumeFrameCommit()
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            keepFlutterSurfaceAliveAndHot(resumeLifecycle = true)
            schedulePostResumeFrameCommit()
        } else {
            if (LauncherSceneStore.isCleanHomeVisible) {
                captureHomeUiSnapshotIfReady()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        // Reply to the home-gesture contract immediately so QuickStep can
        // finish the recents animation smoothly instead of timing out.
        fulfillGestureNavContract(intent)
        setIntent(intent)
        super.onNewIntent(intent)
        keepFlutterSurfaceAliveAndHot(resumeLifecycle = true)
        LauncherSceneStore.homeResumeEpoch.incrementAndGet()
        homeEventSink?.success("onHomeGesture")
        if (hasWindowFocus()) {
            schedulePostResumeFrameCommit()
        }
    }

    /**
     * Releases [HomeSnapshotShieldView] and signals [LauncherSceneStore.markHomeDrawnAndReady]
     * ONLY after `MainActivity` actually holds window focus (`hasWindowFocus() == true`, meaning
     * Xiaomi HyperOS's 1.5s QuickStep dead-zone has ended and the window is visible on screen)
     * AND Flutter's `FlutterTextureView` has latched a live GPU frame.
     */
    private fun schedulePostResumeFrameCommit() {
        if (!hasWindowFocus()) return
        pendingResumeShieldRelease?.let { mainUiHandler.removeCallbacks(it) }
        var released = false

        fun finishCommit() {
            if (released) return
            released = true
            pendingResumeShieldRelease?.let { mainUiHandler.removeCallbacks(it) }
            pendingResumeShieldRelease = null
            // Wait 2 VSYNCs after window focus + UI display so SurfaceFlinger has composited
            // MainActivity's live buffer before Z-layer 31 drops its curtain.
            Choreographer.getInstance().postFrameCallback {
                Choreographer.getInstance().postFrameCallback {
                    homeSnapshotShield?.releaseShield()
                    if (LauncherSceneStore.isCleanHomeVisible) {
                        captureHomeUiSnapshotIfReady()
                    }
                    if (hasWindowFocus()) {
                        LauncherSceneStore.markHomeDrawnAndReady()
                    }
                }
            }
        }

        val renderer = flutterEngine?.renderer
        if (renderer != null && !renderer.isDisplayingFlutterUi) {
            val listener = object : FlutterUiDisplayListener {
                override fun onFlutterUiDisplayed() {
                    renderer.removeIsDisplayingFlutterUiListener(this)
                    finishCommit()
                }

                override fun onFlutterUiNoLongerDisplayed() = Unit
            }
            renderer.addIsDisplayingFlutterUiListener(listener)
            val fallback = Runnable {
                renderer.removeIsDisplayingFlutterUiListener(listener)
                finishCommit()
            }
            pendingResumeShieldRelease = fallback
            mainUiHandler.postDelayed(fallback, 450L)
        } else {
            finishCommit()
        }
    }

    /**
     * Captures the live transparent RGBA Flutter UI layer directly from
     * `FlutterTextureView` into a reusable pre-allocated Bitmap (~1ms on GPU).
     */
    private fun captureHomeUiSnapshotIfReady() {
        if (!LauncherSceneStore.isCleanHomeVisible) return
        val tex = findFlutterTextureView(window?.decorView) ?: return
        if (!tex.isAvailable || tex.width <= 0 || tex.height <= 0) return

        val loc = IntArray(2)
        tex.getLocationOnScreen(loc)
        LauncherSceneStore.updateHomeUiSnapshot(
            sourceGetter = { existing ->
                try {
                    if (existing != null &&
                        !existing.isRecycled &&
                        existing.width == tex.width &&
                        existing.height == tex.height
                    ) {
                        tex.getBitmap(existing)
                    } else {
                        tex.getBitmap()
                    }
                } catch (_: Throwable) {
                    null
                }
            },
            originX = loc[0].toFloat(),
            originY = loc[1].toFloat()
        )
    }

    private fun findFlutterTextureView(root: View?): TextureView? {
        if (root == null) return null
        if (root is TextureView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findFlutterTextureView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
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
            val resolvedTarget = LauncherSceneStore
                .resolveReturnTarget(LauncherSceneStore.activeForegroundPackage)
                ?.screenRect
            // Use the resolved icon bounds when available for fluid return animations,
            // or safely fall back to lastLaunchedAppRect or central bounds.
            val iconPosition = resolvedTarget ?: GoLauncherApplication.lastLaunchedAppRect ?: RectF(
                location[0].toFloat() + width * 0.35f,
                location[1].toFloat() + height * 0.45f,
                location[0].toFloat() + width * 0.65f,
                location[1].toFloat() + height * 0.55f
            )
            val result = Bundle().apply {
                putParcelable("gesture_nav_contract_surface_control", null)
                putParcelable("gesture_nav_contract_icon_position", iconPosition)
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
        LauncherSceneStore.onHomeSwipeTouchDownCallback = null
        LauncherSceneStore.onHomeSwipeCancelledCallback = null
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
                            val density = resources.displayMetrics.density.coerceAtLeast(1f)
                            val providers = appWidgetManager.installedProviders
                            if (providers != null) {
                                for (info in providers) {
                                    val map = mutableMapOf<String, Any>()
                                    map["providerPackage"] = info.provider.packageName
                                    map["providerClass"] = info.provider.className
                                    map["label"] = info.loadLabel(packageManager)?.toString() ?: "Widget"

                                    val minWidthDp = kotlin.math.round(info.minWidth / density).toInt().coerceAtLeast(40)
                                    val minHeightDp = kotlin.math.round(info.minHeight / density).toInt().coerceAtLeast(40)
                                    val minResizeWidthDp = kotlin.math.round(info.minResizeWidth / density).toInt().coerceAtLeast(0)
                                    val minResizeHeightDp = kotlin.math.round(info.minResizeHeight / density).toInt().coerceAtLeast(0)

                                    val targetW = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                        info.targetCellWidth
                                    } else {
                                        0
                                    }
                                    val targetH = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                        info.targetCellHeight
                                    } else {
                                        0
                                    }

                                    val defaultSpanX = if (targetW > 0) {
                                        targetW.coerceIn(1, 4)
                                    } else {
                                        ((minWidthDp + 30) / 70).coerceIn(1, 4)
                                    }
                                    val defaultSpanY = if (targetH > 0) {
                                        targetH.coerceIn(1, 5)
                                    } else {
                                        ((minHeightDp + 30) / 70).coerceIn(1, 5)
                                    }

                                    val resizeMode = info.resizeMode
                                    map["defaultSpanX"] = defaultSpanX
                                    map["defaultSpanY"] = defaultSpanY
                                    map["minWidthDp"] = minWidthDp
                                    map["minHeightDp"] = minHeightDp
                                    map["minResizeWidthDp"] = minResizeWidthDp
                                    map["minResizeHeightDp"] = minResizeHeightDp
                                    map["configurable"] = (info.configure != null)
                                    map["resizeHorizontal"] =
                                        (resizeMode and android.appwidget.AppWidgetProviderInfo.RESIZE_HORIZONTAL) != 0
                                    map["resizeVertical"] =
                                        (resizeMode and android.appwidget.AppWidgetProviderInfo.RESIZE_VERTICAL) != 0

                                    val previewImage = try { info.loadPreviewImage(context, 0) } catch (_: Throwable) { null }
                                    val iconImage = try { info.loadIcon(context, 0) } catch (_: Throwable) { null }

                                    val drawableToConvert = previewImage ?: iconImage
                                    if (drawableToConvert != null) {
                                        try {
                                            val bytes = drawableToByteArray(drawableToConvert, maxSize = 260)
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
                    val density = resources.displayMetrics.density.coerceAtLeast(1f)
                    val resizeMode = info?.resizeMode ?: 0
                    val minWidthDp = if (info != null) {
                        kotlin.math.round(info.minWidth / density).toInt().coerceAtLeast(40)
                    } else {
                        40
                    }
                    val minHeightDp = if (info != null) {
                        kotlin.math.round(info.minHeight / density).toInt().coerceAtLeast(40)
                    } else {
                        40
                    }
                    val minResizeWidthDp = if (info != null) {
                        kotlin.math.round(info.minResizeWidth / density).toInt().coerceAtLeast(0)
                    } else {
                        0
                    }
                    val minResizeHeightDp = if (info != null) {
                        kotlin.math.round(info.minResizeHeight / density).toInt().coerceAtLeast(0)
                    } else {
                        0
                    }
                    val maxResizeWidthDp = if (info != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && info.maxResizeWidth > 0) {
                        kotlin.math.round(info.maxResizeWidth / density).toInt()
                    } else {
                        0
                    }
                    val maxResizeHeightDp = if (info != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && info.maxResizeHeight > 0) {
                        kotlin.math.round(info.maxResizeHeight / density).toInt()
                    } else {
                        0
                    }
                    val targetW = if (info != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        info.targetCellWidth
                    } else {
                        0
                    }
                    val targetH = if (info != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        info.targetCellHeight
                    } else {
                        0
                    }
                    val defaultSpanX = if (targetW > 0) targetW.coerceIn(1, 4) else ((minWidthDp + 30) / 70).coerceIn(1, 4)
                    val defaultSpanY = if (targetH > 0) targetH.coerceIn(1, 5) else ((minHeightDp + 30) / 70).coerceIn(1, 5)

                    result.success(
                        mapOf(
                            "configurable" to (info?.configure != null),
                            "resizeHorizontal" to (
                                (resizeMode and android.appwidget.AppWidgetProviderInfo.RESIZE_HORIZONTAL) != 0
                            ),
                            "resizeVertical" to (
                                (resizeMode and android.appwidget.AppWidgetProviderInfo.RESIZE_VERTICAL) != 0
                            ),
                            "minWidthDp" to minWidthDp,
                            "minHeightDp" to minHeightDp,
                            "minResizeWidthDp" to minResizeWidthDp,
                            "minResizeHeightDp" to minResizeHeightDp,
                            "maxResizeWidthDp" to maxResizeWidthDp,
                            "maxResizeHeightDp" to maxResizeHeightDp,
                            "defaultSpanX" to defaultSpanX,
                            "defaultSpanY" to defaultSpanY
                        )
                    )
                }
                "updateWidgetSize" -> {
                    val appWidgetId = call.argument<Number>("appWidgetId")?.toInt() ?: -1
                    val minWidthDp = call.argument<Number>("minWidthDp")?.toInt() ?: 80
                    val minHeightDp = call.argument<Number>("minHeightDp")?.toInt() ?: 80
                    val maxWidthDp = call.argument<Number>("maxWidthDp")?.toInt() ?: minWidthDp
                    val maxHeightDp = call.argument<Number>("maxHeightDp")?.toInt() ?: minHeightDp
                    val updated = WidgetViewFactory.updateWidgetSize(
                        this,
                        appWidgetId,
                        minWidthDp,
                        minHeightDp,
                        maxWidthDp,
                        maxHeightDp
                    )
                    result.success(updated)
                }
                "captureWidgetSnapshot" -> {
                    val appWidgetId = call.argument<Number>("appWidgetId")?.toInt() ?: -1
                    val maxSidePx = call.argument<Number>("maxSidePx")?.toInt() ?: 320
                    val bytes = WidgetViewFactory.captureSnapshotBytes(appWidgetId, maxSidePx)
                    result.success(bytes)
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
                "isBiometricAvailable" -> {
                    result.success(isBiometricAvailable())
                }
                "authenticateBiometric" -> {
                    val title = call.argument<String>("title") ?: "Unlock"
                    val subtitle = call.argument<String>("subtitle")
                    val negative = call.argument<String>("negativeText") ?: "Use PIN"
                    authenticateBiometric(title, subtitle, negative, result)
                }
                "getDeviceTotalMemoryBytes" -> {
                    val activityManager =
                        getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                    val memoryInfo = android.app.ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memoryInfo)
                    result.success(memoryInfo.totalMem)
                }
                "getDeviceMemoryInfo" -> {
                    val activityManager =
                        getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager
                    val memoryInfo = android.app.ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memoryInfo)
                    result.success(
                        mapOf(
                            "totalRamBytes" to memoryInfo.totalMem,
                            "isLowRamDevice" to activityManager.isLowRamDevice
                        )
                    )
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
                    iconExecutor.execute {
                        try {
                            val bytes = iconPackManager.getThemedIcon(appPackage, iconPackPackage)
                            Handler(Looper.getMainLooper()).post { result.success(bytes) }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        }
                    }
                }
                "getOsIcon" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    iconExecutor.execute {
                        try {
                            val appInfo = packageManager.getApplicationInfo(packageName, 0)
                            val drawable = packageManager.getApplicationIcon(appInfo)
                            val bytes = drawableToByteArray(drawable)
                            Handler(Looper.getMainLooper()).post { result.success(bytes) }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        }
                    }
                }
                "getMonochromeIcon" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    iconExecutor.execute {
                        try {
                            var monoDrawable: Drawable? = null
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                val launcherApps = getSystemService(Context.LAUNCHER_APPS_SERVICE) as? android.content.pm.LauncherApps
                                val activities = launcherApps?.getActivityList(packageName, android.os.Process.myUserHandle())
                                val rawDrawable = if (!activities.isNullOrEmpty()) {
                                    activities[0].getIcon(resources.displayMetrics.densityDpi)
                                } else {
                                    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                                    val activityComponent = launchIntent?.component
                                    if (activityComponent != null) {
                                        try {
                                            packageManager.getActivityIcon(activityComponent)
                                        } catch (e: Throwable) {
                                            val appInfo = packageManager.getApplicationInfo(packageName, 0)
                                            packageManager.getApplicationIcon(appInfo)
                                        }
                                    } else {
                                        val appInfo = packageManager.getApplicationInfo(packageName, 0)
                                        packageManager.getApplicationIcon(appInfo)
                                    }
                                }

                                if (rawDrawable is android.graphics.drawable.AdaptiveIconDrawable) {
                                    monoDrawable = rawDrawable.monochrome
                                }
                            }

                            if (monoDrawable != null) {
                                val bytes = drawableToByteArray(monoDrawable)
                                Handler(Looper.getMainLooper()).post { result.success(bytes) }
                            } else {
                                Handler(Looper.getMainLooper()).post { result.success(null) }
                            }
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
                "syncHomeScene" -> {
                    val isCleanHome = call.argument<Boolean>("isCleanHome") ?: true
                    val isSubRouteOpen = call.argument<Boolean>("isSubRouteOpen") ?: false
                    val iconShape = call.argument<String>("iconShape") ?: "Circle"
                    val rawTargets = call.argument<List<*>>("targets")

                    LauncherSceneStore.isCleanHomeVisible = isCleanHome
                    LauncherSceneStore.isSubRouteOpen = isSubRouteOpen
                    LauncherSceneStore.currentIconShape = iconShape

                    if (rawTargets != null) {
                        val density = resources.displayMetrics.density
                        val decorLoc = IntArray(2)
                        window.decorView.getLocationOnScreen(decorLoc)
                        val updatedMap = HashMap<String, LauncherSceneStore.IconTargetSpec>()

                        for (entry in rawTargets) {
                            val map = entry as? Map<*, *> ?: continue
                            val pkg = map["packageName"] as? String ?: continue
                            if (pkg.isEmpty()) continue
                            val left = (map["left"] as? Number)?.toFloat() ?: continue
                            val top = (map["top"] as? Number)?.toFloat() ?: continue
                            val w = (map["width"] as? Number)?.toFloat() ?: continue
                            val h = (map["height"] as? Number)?.toFloat() ?: continue
                            if (w <= 0f || h <= 0f) continue

                            val isFolderSlot = map["isFolderSlot"] as? Boolean ?: false
                            val sx = decorLoc[0] + left * density
                            val sy = decorLoc[1] + top * density
                            val sw = w * density
                            val sh = h * density
                            updatedMap[pkg] = LauncherSceneStore.IconTargetSpec(
                                packageName = pkg,
                                screenRect = RectF(sx, sy, sx + sw, sy + sh),
                                iconShape = iconShape,
                                isFolderSlot = isFolderSlot
                            )
                            LauncherSceneStore.warmAppVisualAsync(this, pkg)
                        }

                        LauncherSceneStore.visibleHomeTargets.clear()
                        LauncherSceneStore.visibleHomeTargets.putAll(updatedMap)
                    }

                    if (isCleanHome) {
                        Choreographer.getInstance().postFrameCallback {
                            captureHomeUiSnapshotIfReady()
                        }
                        mainUiHandler.postDelayed({
                            if (LauncherSceneStore.isCleanHomeVisible) {
                                captureHomeUiSnapshotIfReady()
                            }
                        }, 220L)
                    }
                    result.success(null)
                }
                "invalidateCompositorIcons" -> {
                    LauncherSceneStore.invalidateIconVisualCache()
                    result.success(null)
                }
                "startApp" -> {
                    val packageName = call.argument<String>("packageName")
                    val splitScreen = call.argument<Boolean>("splitScreen") ?: false
                    val fromDrawer = call.argument<Boolean>("fromDrawer") ?: false
                    val sourceLeft = (call.argument<Number>("sourceLeft") ?: call.argument<Number>("sourceX"))?.toFloat()
                    val sourceTop = (call.argument<Number>("sourceTop") ?: call.argument<Number>("sourceY"))?.toFloat()
                    val sourceWidth = call.argument<Number>("sourceWidth")?.toFloat()
                    val sourceHeight = call.argument<Number>("sourceHeight")?.toFloat()

                    val returnLeft = call.argument<Number>("returnLeft")?.toFloat()
                    val returnTop = call.argument<Number>("returnTop")?.toFloat()
                    val returnWidth = call.argument<Number>("returnWidth")?.toFloat()
                    val returnHeight = call.argument<Number>("returnHeight")?.toFloat()

                    if (packageName != null) {
                        try {
                            val intent = packageManager.getLaunchIntentForPackage(packageName)
                            if (intent != null) {
                                // Abort any lingering return overlay immediately for instant tap chaining
                                LauncherSceneStore.onAppLaunchStartedCallback?.invoke()

                                if (LauncherSceneStore.isCleanHomeVisible && !fromDrawer) {
                                    captureHomeUiSnapshotIfReady()
                                }
                                LauncherSceneStore.warmAppVisualAsync(this, packageName)

                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                                if (splitScreen && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    intent.addFlags(Intent.FLAG_ACTIVITY_LAUNCH_ADJACENT)
                                    intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                                }

                                val density = resources.displayMetrics.density
                                val decorLoc = IntArray(2)
                                window.decorView.getLocationOnScreen(decorLoc)

                                val options = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                                    sourceLeft != null && sourceTop != null &&
                                    sourceWidth != null && sourceHeight != null &&
                                    sourceWidth > 0f && sourceHeight > 0f
                                ) {
                                    val relX = kotlin.math.round(sourceLeft * density).toInt()
                                    val relY = kotlin.math.round(sourceTop * density).toInt()
                                    val pxW = kotlin.math.round(sourceWidth * density).toInt().coerceAtLeast(1)
                                    val pxH = kotlin.math.round(sourceHeight * density).toInt().coerceAtLeast(1)
                                    val absX = decorLoc[0] + relX
                                    val absY = decorLoc[1] + relY

                                    intent.sourceBounds = android.graphics.Rect(
                                        absX,
                                        absY,
                                        absX + pxW,
                                        absY + pxH
                                    )

                                    val hasExplicitReturnRect =
                                        returnLeft != null && returnTop != null &&
                                        returnWidth != null && returnHeight != null &&
                                        returnWidth > 0f && returnHeight > 0f
                                    val returnRect = if (hasExplicitReturnRect) {
                                        val rX = decorLoc[0] + returnLeft!! * density
                                        val rY = decorLoc[1] + returnTop!! * density
                                        val rW = returnWidth!! * density
                                        val rH = returnHeight!! * density
                                        RectF(rX, rY, rX + rW, rY + rH)
                                    } else {
                                        RectF(
                                            absX.toFloat(),
                                            absY.toFloat(),
                                            (absX + pxW).toFloat(),
                                            (absY + pxH).toFloat()
                                        )
                                    }

                                    LauncherSceneStore.lastLaunchedPackage = packageName
                                    LauncherSceneStore.lastLaunchedFromDrawer = fromDrawer
                                    LauncherSceneStore.lastLaunchedReturnIsFolder = hasExplicitReturnRect
                                    LauncherSceneStore.lastLaunchedReturnRect = if (fromDrawer) null else returnRect
                                    GoLauncherApplication.lastLaunchedAppRect = returnRect

                                    ActivityOptions.makeClipRevealAnimation(
                                        window.decorView,
                                        relX,
                                        relY,
                                        pxW,
                                        pxH
                                    )
                                } else {
                                    LauncherSceneStore.lastLaunchedPackage = packageName
                                    LauncherSceneStore.lastLaunchedFromDrawer = fromDrawer
                                    LauncherSceneStore.lastLaunchedReturnRect = null
                                    GoLauncherApplication.lastLaunchedAppRect = null
                                    ActivityOptions.makeBasic()
                                }

                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    try {
                                        options.setSplashScreenStyle(android.window.SplashScreen.SPLASH_SCREEN_STYLE_ICON)
                                    } catch (_: Throwable) {
                                        try {
                                            val method = options.javaClass.getMethod(
                                                "setSplashScreenStyle",
                                                Int::class.javaPrimitiveType
                                            )
                                            method.invoke(options, 1)
                                        } catch (_: Throwable) {}
                                    }
                                }

                                LauncherSceneStore.activeForegroundPackage = packageName
                                LauncherSceneStore.markHomeTransitionStarting()
                                startActivity(intent, options.toBundle())
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
                            if (type == 1 || type == 3) {
                                flags = flags or android.app.WallpaperManager.FLAG_SYSTEM
                                if (bitmap != null) {
                                    LauncherSceneStore.updateWallpaperSource(this, bitmap)
                                }
                            }
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
                    result.success(NotificationDotService.controlMedia(action, position, this))
                }
                "hasAudioPermission" -> {
                    result.success(LocalMusicManager.hasAudioPermission(this))
                }
                "requestAudioPermission" -> {
                    if (LocalMusicManager.hasAudioPermission(this)) {
                        result.success(true)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        pendingAudioPermissionResult = result
                        requestPermissions(
                            arrayOf(LocalMusicManager.requiredPermission()),
                            REQUEST_AUDIO_PERMISSION
                        )
                    } else {
                        result.success(true)
                    }
                }
                "getLocalMusicTracks" -> {
                    backgroundExecutor.execute {
                        val tracks = LocalMusicManager.queryLocalTracks(this)
                        Handler(Looper.getMainLooper()).post {
                            result.success(tracks)
                        }
                    }
                }
                "getLocalAlbumArt" -> {
                    val albumId = call.argument<Number>("albumId")?.toLong() ?: 0L
                    val trackId = call.argument<Number>("trackId")?.toLong() ?: 0L
                    iconExecutor.execute {
                        val bytes = LocalMusicManager.loadAlbumArtBytes(this, albumId, trackId)
                        Handler(Looper.getMainLooper()).post {
                            result.success(bytes)
                        }
                    }
                }
                "playLocalTrack" -> {
                    val trackId = call.argument<Number>("trackId")?.toLong() ?: -1L
                    val rawQueue = call.argument<List<*>>("queueIds")
                    val queueIds = rawQueue?.mapNotNull { (it as? Number)?.toLong() }
                    if (trackId <= 0L) {
                        result.success(false)
                    } else {
                        val started = LocalMusicManager.playTrack(this, trackId, queueIds)
                        result.success(started)
                    }
                }
                "queueLocalTrackNext" -> {
                    val trackId = call.argument<Number>("trackId")?.toLong() ?: -1L
                    result.success(
                        if (trackId > 0L) LocalMusicManager.queueTrackNext(trackId) else false
                    )
                }
                "shareLocalTrack" -> {
                    val contentUri = call.argument<String>("contentUri") ?: ""
                    val title = call.argument<String>("title") ?: "Audio"
                    result.success(
                        if (contentUri.isNotEmpty()) {
                            LocalMusicManager.shareTrack(this, contentUri, title)
                        } else {
                            false
                        }
                    )
                }
                "deleteLocalTrack" -> {
                    val trackId = call.argument<Number>("trackId")?.toLong() ?: -1L
                    val contentUri = call.argument<String>("contentUri") ?: ""
                    if (trackId <= 0L || contentUri.isEmpty()) {
                        result.success(false)
                    } else {
                        try {
                            val uri = Uri.parse(contentUri)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val pendingIntent = android.provider.MediaStore.createDeleteRequest(
                                    contentResolver,
                                    listOf(uri)
                                )
                                pendingDeleteAudioResult = result
                                pendingDeleteAudioTrackId = trackId
                                startIntentSenderForResult(
                                    pendingIntent.intentSender,
                                    REQUEST_DELETE_AUDIO,
                                    null,
                                    0,
                                    0,
                                    0,
                                    null
                                )
                            } else {
                                val rows = contentResolver.delete(uri, null, null)
                                if (rows > 0) {
                                    LocalMusicManager.onTrackDeletedFromDevice(trackId)
                                }
                                result.success(rows > 0)
                            }
                        } catch (e: Exception) {
                            pendingDeleteAudioResult = null
                            pendingDeleteAudioTrackId = -1L
                            result.success(false)
                        }
                    }
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
                        LauncherSceneStore.updateWallpaperOffset(this, offset)
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
                "openGoogleAiMode" -> {
                    try {
                        val geminiIntent = packageManager.getLaunchIntentForPackage("com.google.android.apps.bard")
                        if (geminiIntent != null) {
                            geminiIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(geminiIntent)
                        } else {
                            try {
                                val assistIntent = Intent(Intent.ACTION_ASSIST).apply {
                                    setPackage("com.google.android.googlequicksearchbox")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(assistIntent)
                            } catch (_: Exception) {
                                val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/search?udm=24")).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(webIntent)
                            }
                        }
                    } catch (_: Exception) {
                        try {
                            val intent = Intent(Intent.ACTION_WEB_SEARCH).apply {
                                setPackage("com.google.android.googlequicksearchbox")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
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
            return
        }
        if (requestCode == REQUEST_DELETE_AUDIO) {
            val delResult = pendingDeleteAudioResult
            val trackId = pendingDeleteAudioTrackId
            pendingDeleteAudioResult = null
            pendingDeleteAudioTrackId = -1L
            if (resultCode == Activity.RESULT_OK) {
                if (trackId > 0L) {
                    LocalMusicManager.onTrackDeletedFromDevice(trackId)
                }
                delResult?.success(true)
            } else {
                delResult?.success(false)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_AUDIO_PERMISSION) {
            val permResult = pendingAudioPermissionResult
            pendingAudioPermissionResult = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            permResult?.success(granted)
        }
    }

    private var biometricCancellation: android.os.CancellationSignal? = null

    /** True when the device has enrolled biometrics the platform prompt can use. */
    @android.annotation.SuppressLint("NewApi")
    private fun isBiometricAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val manager = getSystemService(android.hardware.biometrics.BiometricManager::class.java)
                    ?: return false
                val status = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    manager.canAuthenticate(
                        android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG
                    )
                } else {
                    @Suppress("DEPRECATION")
                    manager.canAuthenticate()
                }
                status == android.hardware.biometrics.BiometricManager.BIOMETRIC_SUCCESS
            } else {
                packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_FINGERPRINT)
            }
        } catch (_: Exception) {
            false
        }
    }

    /** Shows the system biometric prompt. Replies true on success, false otherwise. */
    @android.annotation.SuppressLint("NewApi")
    private fun authenticateBiometric(
        title: String,
        subtitle: String?,
        negativeText: String,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || !isBiometricAvailable()) {
            result.success(false)
            return
        }
        biometricCancellation?.cancel()
        val cancellation = android.os.CancellationSignal()
        biometricCancellation = cancellation
        var replied = false
        fun reply(success: Boolean) {
            if (replied) return
            replied = true
            if (biometricCancellation === cancellation) biometricCancellation = null
            result.success(success)
        }
        try {
            val builder = android.hardware.biometrics.BiometricPrompt.Builder(this)
                .setTitle(title)
                .setNegativeButton(negativeText, mainExecutor) { _, _ -> reply(false) }
            if (!subtitle.isNullOrEmpty()) builder.setSubtitle(subtitle)
            builder.build().authenticate(
                cancellation,
                mainExecutor,
                object : android.hardware.biometrics.BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        authResult: android.hardware.biometrics.BiometricPrompt.AuthenticationResult?
                    ) = reply(true)

                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) =
                        reply(false)
                }
            )
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "Biometric prompt failed", e)
            reply(false)
        }
    }

    private fun drawableToByteArray(drawable: Drawable, maxSize: Int = 150): ByteArray {
        var width = Math.max(1, drawable.intrinsicWidth)
        var height = Math.max(1, drawable.intrinsicHeight)

        // Scale down large drawables to prevent OOM / TransactionTooLargeException
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
