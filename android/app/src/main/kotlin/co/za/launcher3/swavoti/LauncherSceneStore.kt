package co.za.launcher3.swavoti

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Shared in-process compositor scene store bridging [MainActivity] and
 * [MyAccessibilityService] with zero IPC serialization overhead.
 *
 * Both components live inside the persistent `co.za.launcher3.swavoti` process,
 * allowing direct sharing of pre-allocated GPU/RAM Bitmaps, exact physical
 * screen icon rectangles, and frame-commit readiness signals.
 */
object LauncherSceneStore {

    data class IconTargetSpec(
        val packageName: String,
        val screenRect: RectF,
        val iconShape: String,
        val isFolderSlot: Boolean = false
    )

    data class AppVisualCache(
        val iconBitmap: Bitmap?,
        val dominantSurfaceColor: Int
    )

    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Visible app icon slots on the active Home workspace page + Dock. */
    val visibleHomeTargets = ConcurrentHashMap<String, IconTargetSpec>()

    /** Pre-decoded 192px app icons & surface colors keyed by package name. */
    private val appVisualCache = android.util.LruCache<String, AppVisualCache>(64)

    @Volatile
    var currentIconShape: String = "Circle"

    @Volatile
    var lastLaunchedPackage: String? = null

    @Volatile
    var lastLaunchedReturnRect: RectF? = null

    @Volatile
    var lastLaunchedReturnIsFolder: Boolean = false

    @Volatile
    var lastLaunchedFromDrawer: Boolean = false

    @Volatile
    var activeForegroundPackage: String? = null

    /** True when HomeScreen is resting cleanly (drawer, folder, overview, sub-routes closed). */
    @Volatile
    var isCleanHomeVisible: Boolean = true

    /** True when a full-screen Flutter route (e.g. Settings / Wallpaper) covers HomeScreen. */
    @Volatile
    var isSubRouteOpen: Boolean = false

    /** Screen-cropped wallpaper ready for 1:1 hardware canvas blitting. */
    @Volatile
    var wallpaperBitmap: Bitmap? = null
        private set

    private var rawWallpaperSource: Bitmap? = null

    @Volatile
    var currentWallpaperOffset: Float = 0f
        private set

    /** Transparent RGBA Flutter UI snapshot (clock, search bar, grid icons, dock). */
    @Volatile
    var homeUiBitmap: Bitmap? = null
        private set

    /** Physical screen location `(x, y)` of the captured `FlutterTextureView`. */
    @Volatile
    var homeUiScreenOriginX: Float = 0f
        private set

    @Volatile
    var homeUiScreenOriginY: Float = 0f
        private set

    /**
     * Set to `false` the moment a Home gesture begins or `MainActivity` loses focus,
     * and flipped to `true` ONLY after `MainActivity` actually receives window focus
     * (`onWindowFocusChanged(true)`) AND has swapped a live post-resume GPU frame.
     */
    val isHomeActivityDrawnAndReady = AtomicBoolean(true)

    /** Incremented each time `MainActivity` enters `onResume` / `onNewIntent`. */
    val homeResumeEpoch = AtomicInteger(0)

    private val homeReadyListeners = java.util.concurrent.CopyOnWriteArrayList<() -> Unit>()

    /** Invoked on MainActivity.startApp or live Home touch so any return overlay aborts immediately. */
    @Volatile
    var onAppLaunchStartedCallback: (() -> Unit)? = null

    /** Invoked on bottom-strip `ACTION_DOWN` to pre-wake Flutter's GPU surface 200ms early. */
    @Volatile
    var onHomeSwipeTouchDownCallback: (() -> Unit)? = null

    /** Invoked if a bottom swipe is aborted back into the foreground app. */
    @Volatile
    var onHomeSwipeCancelledCallback: (() -> Unit)? = null

    fun addHomeReadyListener(listener: () -> Unit) {
        homeReadyListeners.add(listener)
    }

    fun removeHomeReadyListener(listener: () -> Unit) {
        homeReadyListeners.remove(listener)
    }

    fun markHomeTransitionStarting() {
        isHomeActivityDrawnAndReady.set(false)
    }

    fun markHomeDrawnAndReady() {
        isHomeActivityDrawnAndReady.set(true)
        if (Looper.myLooper() == Looper.getMainLooper()) {
            for (listener in homeReadyListeners) listener.invoke()
        } else {
            mainHandler.post {
                for (listener in homeReadyListeners) listener.invoke()
            }
        }
    }

    /**
     * Resolves the best return target on the Home Screen for whichever app is
     * currently closing.
     *
     * Priority:
     * 1. Exact icon slot on the currently visible Home grid or Dock for [pkg].
     * 2. If [pkg] matches [lastLaunchedPackage] and wasn't launched from the
     *    App Drawer (e.g. launched from inside a Home Folder), return to that
     *    Folder's icon slot.
     * 3. Otherwise `null` (compositor performs a centered spring scale-fade).
     */
    fun resolveReturnTarget(pkg: String?): IconTargetSpec? {
        val targetPkg = pkg?.takeIf { it.isNotEmpty() } ?: lastLaunchedPackage
        if (targetPkg != null) {
            visibleHomeTargets[targetPkg]?.let { return it }
            if (targetPkg == lastLaunchedPackage && !lastLaunchedFromDrawer) {
                lastLaunchedReturnRect?.let { rect ->
                    return IconTargetSpec(
                        packageName = targetPkg,
                        screenRect = RectF(rect),
                        iconShape = currentIconShape,
                        isFolderSlot = lastLaunchedReturnIsFolder
                    )
                }
            }
        }
        if (!lastLaunchedFromDrawer) {
            val fallbackPkg = lastLaunchedPackage
            val fallbackRect = lastLaunchedReturnRect
            if (fallbackPkg != null && fallbackRect != null) {
                return IconTargetSpec(
                    packageName = fallbackPkg,
                    screenRect = RectF(fallbackRect),
                    iconShape = currentIconShape,
                    isFolderSlot = lastLaunchedReturnIsFolder
                )
            }
        }
        return null
    }

    fun updateHomeUiSnapshot(
        sourceGetter: (Bitmap?) -> Bitmap?,
        originX: Float,
        originY: Float
    ) {
        val updated = sourceGetter(homeUiBitmap) ?: return
        homeUiBitmap = updated
        homeUiScreenOriginX = originX
        homeUiScreenOriginY = originY
    }

    /**
     * Preloads the active wallpaper from SharedPreferences (`saved_wallpaper_path`),
     * `WallpaperManager`, or the bundled default asset off the UI thread.
     */
    fun preloadWallpaperAsync(context: Context) {
        val appCtx = context.applicationContext
        worker.execute {
            try {
                val metrics = appCtx.resources.displayMetrics
                val screenW = metrics.widthPixels.coerceAtLeast(1)
                val screenH = metrics.heightPixels.coerceAtLeast(1)

                val flutterPrefs = appCtx.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
                )
                val savedPath = flutterPrefs.getString("flutter.saved_wallpaper_path", null)

                var decoded: Bitmap? = null
                if (!savedPath.isNullOrEmpty()) {
                    decoded = if (savedPath.startsWith("assets/")) {
                        decodeFlutterAssetBitmap(appCtx, savedPath, screenW, screenH)
                    } else {
                        val file = File(savedPath)
                        if (file.exists()) {
                            decodeSampledFile(file.absolutePath, screenW, screenH)
                        } else {
                            null
                        }
                    }
                }

                if (decoded == null) {
                    decoded = try {
                        val wm = WallpaperManager.getInstance(appCtx)
                        val drawable = wm.drawable
                        if (drawable is BitmapDrawable && drawable.bitmap != null) {
                            drawable.bitmap
                        } else if (drawable != null) {
                            drawableToBitmap(drawable, screenW, screenH)
                        } else {
                            null
                        }
                    } catch (_: Throwable) {
                        null
                    }
                }

                if (decoded == null) {
                    decoded = decodeFlutterAssetBitmap(
                        appCtx,
                        "assets/wallpapers/default_wallpaper.jpg",
                        screenW,
                        screenH
                    )
                }

                if (decoded != null) {
                    rawWallpaperSource = decoded
                    rebuildCroppedWallpaper(screenW, screenH, currentWallpaperOffset)
                }
            } catch (_: Throwable) {
            }
        }
    }

    fun updateWallpaperSource(context: Context, freshBitmap: Bitmap) {
        val appCtx = context.applicationContext
        val copy = try {
            freshBitmap.copy(Bitmap.Config.ARGB_8888, false)
        } catch (_: Throwable) {
            freshBitmap
        }
        worker.execute {
            rawWallpaperSource = copy
            val metrics = appCtx.resources.displayMetrics
            rebuildCroppedWallpaper(
                metrics.widthPixels.coerceAtLeast(1),
                metrics.heightPixels.coerceAtLeast(1),
                currentWallpaperOffset
            )
        }
    }

    fun updateWallpaperOffset(context: Context, offset: Float) {
        val clamped = offset.coerceIn(0f, 1f)
        if (kotlin.math.abs(clamped - currentWallpaperOffset) < 0.01f && wallpaperBitmap != null) {
            return
        }
        currentWallpaperOffset = clamped
        val raw = rawWallpaperSource ?: return
        val appCtx = context.applicationContext
        worker.execute {
            val metrics = appCtx.resources.displayMetrics
            if (rawWallpaperSource === raw) {
                rebuildCroppedWallpaper(
                    metrics.widthPixels.coerceAtLeast(1),
                    metrics.heightPixels.coerceAtLeast(1),
                    clamped
                )
            }
        }
    }

    private fun rebuildCroppedWallpaper(screenW: Int, screenH: Int, xOffset: Float) {
        val src = rawWallpaperSource ?: return
        if (src.isRecycled || src.width <= 0 || src.height <= 0) return
        try {
            val scale = max(
                screenW.toFloat() / src.width.toFloat(),
                screenH.toFloat() / src.height.toFloat()
            )
            val scaledW = (src.width * scale).roundToInt().coerceAtLeast(screenW)
            val scaledH = (src.height * scale).roundToInt().coerceAtLeast(screenH)
            val panX = ((scaledW - screenW) * xOffset.coerceIn(0f, 1f)).roundToInt()
            val panY = ((scaledH - screenH) * 0.5f).roundToInt()

            val out = Bitmap.createBitmap(screenW, screenH, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
            val dstRect = Rect(-panX, -panY, -panX + scaledW, -panY + scaledH)
            canvas.drawBitmap(src, null, dstRect, paint)
            wallpaperBitmap = out
        } catch (_: Throwable) {
        }
    }

    /**
     * Warms the 192px icon Bitmap & adaptive surface color for [packageName] in
     * the background so it is instantaneously available on `ACTION_DOWN`.
     */
    fun warmAppVisualAsync(context: Context, packageName: String) {
        if (packageName.isEmpty() || packageName == context.packageName) return
        if (appVisualCache.get(packageName) != null) return
        val appCtx = context.applicationContext
        worker.execute {
            if (appVisualCache.get(packageName) != null) return@execute
            val loaded = loadAppVisualSync(appCtx, packageName)
            if (loaded != null) {
                appVisualCache.put(packageName, loaded)
            }
        }
    }

    fun getAppVisualImmediate(context: Context, packageName: String?): AppVisualCache? {
        if (packageName.isNullOrEmpty()) return null
        appVisualCache.get(packageName)?.let { return it }
        val loaded = loadAppVisualSync(context.applicationContext, packageName)
        if (loaded != null) {
            appVisualCache.put(packageName, loaded)
        }
        return loaded
    }

    fun invalidateIconVisualCache() {
        appVisualCache.evictAll()
    }

    private fun loadAppVisualSync(context: Context, packageName: String): AppVisualCache? {
        return try {
            val flutterPrefs = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            val iconPack = flutterPrefs.getString("flutter.icon_pack", null)
            var iconBmp: Bitmap? = null

            if (!iconPack.isNullOrEmpty()) {
                val bytes = IconPackManager(context).getThemedIcon(packageName, iconPack)
                if (bytes != null && bytes.isNotEmpty()) {
                    iconBmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                }
            }

            if (iconBmp == null) {
                val appInfo = context.packageManager.getApplicationInfo(packageName, 0)
                val drawable = context.packageManager.getApplicationIcon(appInfo)
                iconBmp = drawableToBitmap(drawable, 192, 192)
            }

            val isNight = (context.resources.configuration.uiMode and
                android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES
            val surfaceColor = if (isNight) Color.rgb(18, 19, 22) else Color.rgb(245, 246, 248)

            AppVisualCache(iconBitmap = iconBmp, dominantSurfaceColor = surfaceColor)
        } catch (_: Throwable) {
            null
        }
    }

    private fun drawableToBitmap(drawable: Drawable, targetW: Int, targetH: Int): Bitmap {
        val w = targetW.coerceAtLeast(1)
        val h = targetH.coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, w, h)
        drawable.draw(canvas)
        return bmp
    }

    private fun decodeFlutterAssetBitmap(
        context: Context,
        assetPath: String,
        reqW: Int,
        reqH: Int
    ): Bitmap? {
        return try {
            val lookupKey = FlutterInjector.instance()
                .flutterLoader()
                .getLookupKeyForAsset(assetPath)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.assets.open(lookupKey).use { stream ->
                BitmapFactory.decodeStream(stream, null, bounds)
            }
            val sample = computeInSampleSize(bounds.outWidth, bounds.outHeight, reqW, reqH)
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            context.assets.open(lookupKey).use { stream ->
                BitmapFactory.decodeStream(stream, null, opts)
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun decodeSampledFile(path: String, reqW: Int, reqH: Int): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            val sample = computeInSampleSize(bounds.outWidth, bounds.outHeight, reqW, reqH)
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            BitmapFactory.decodeFile(path, opts)
        } catch (_: Throwable) {
            null
        }
    }

    private fun computeInSampleSize(rawW: Int, rawH: Int, reqW: Int, reqH: Int): Int {
        var sample = 1
        if (rawW > reqW * 2 || rawH > reqH * 2) {
            val halfW = rawW / 2
            val halfH = rawH / 2
            while ((halfW / sample) >= reqW && (halfH / sample) >= reqH) {
                sample *= 2
            }
        }
        return sample
    }
}

