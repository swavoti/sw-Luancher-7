package co.za.launcher3.swavoti

import android.accessibilityservice.AccessibilityService
import android.app.ActivityOptions
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Display
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import kotlin.math.abs
import kotlin.math.hypot

class MyAccessibilityService : AccessibilityService() {

    private var windowManager: WindowManager? = null
    private var compositorView: GestureCompositorView? = null
    private var gestureHandle: GestureSensorStrip? = null
    private var gestureHandleParams: WindowManager.LayoutParams? = null
    private var suppressHandleUntilAppSwitch = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val app = application as GoLauncherApplication
        app.ensureEngineWarmed()
        LauncherSceneStore.preloadWallpaperAsync(this)

        mountCompositorOverlay()
        LauncherSceneStore.onAppLaunchStartedCallback = {
            mainHandler.post {
                compositorView?.abortImmediately()
            }
        }

        // If toggled on while inside Settings or another app, arm the bottom sensor immediately
        val currentPkg = try {
            rootInActiveWindow?.packageName?.toString()
        } catch (_: Throwable) {
            null
        }
        if (!currentPkg.isNullOrEmpty() &&
            currentPkg != packageName &&
            !isSystemOverlayNoise(currentPkg) &&
            !isSystemNavigationUi(currentPkg)
        ) {
            LauncherSceneStore.activeForegroundPackage = currentPkg
            LauncherSceneStore.warmAppVisualAsync(this, currentPkg)
            showGestureHandle()
            updateSensorForKeyboardState()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val type = event?.eventType ?: return

        if (type == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            updateSensorForKeyboardState()
            return
        }

        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val foregroundPackage = event.packageName?.toString() ?: return
        // Ignore our own accessibility overlay window events
        if (foregroundPackage == packageName) {
            // Only treat as launcher foreground if our compositor isn't mid-drag over another app
            if (compositorView?.isSessionActive != true) {
                LauncherSceneStore.activeForegroundPackage = packageName
                suppressHandleUntilAppSwitch = false
                hideGestureHandle()
            }
            return
        }

        if (isSystemOverlayNoise(foregroundPackage)) {
            updateSensorForKeyboardState()
            return
        }

        if (isSystemNavigationUi(foregroundPackage)) {
            hideGestureHandle()
            return
        }

        // Real third-party or system app entered foreground: pre-warm its 192px icon + surface
        // immediately so it's sitting in RAM long before the user touches the bottom edge.
        LauncherSceneStore.activeForegroundPackage = foregroundPackage
        LauncherSceneStore.warmAppVisualAsync(this, foregroundPackage)
        suppressHandleUntilAppSwitch = false
        showGestureHandle()
        updateSensorForKeyboardState()
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        LauncherSceneStore.onAppLaunchStartedCallback = null
        hideGestureHandle()
        unmountCompositorOverlay()
        windowManager = null
        super.onDestroy()
    }

    private fun mountCompositorOverlay() {
        if (compositorView != null) return
        val manager = windowManager ?: return
        val view = GestureCompositorView(
            context = this,
            onCurtainDropped = {
                // Once return-to-home settles, keep sensor hidden while on Home
                if (LauncherSceneStore.activeForegroundPackage == packageName ||
                    suppressHandleUntilAppSwitch
                ) {
                    hideGestureHandle()
                }
            }
        )
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_SHOW_WALLPAPER or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                fitInsetsTypes = 0
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        try {
            manager.addView(view, params)
            compositorView = view
        } catch (e: RuntimeException) {
            android.util.Log.w("MyAccessibilityService", "Unable to mount compositor overlay", e)
        }
    }

    private fun unmountCompositorOverlay() {
        val view = compositorView ?: return
        compositorView = null
        view.destroy()
        try {
            windowManager?.removeView(view)
        } catch (e: RuntimeException) {
            android.util.Log.w("MyAccessibilityService", "Unable to remove compositor overlay", e)
        }
    }

    private fun showGestureHandle() {
        if (gestureHandle != null) return
        val manager = windowManager ?: return
        val (displayW, _) = getRealDisplaySize()
        val sensorWidth = (displayW * 0.86f).toInt().coerceAtLeast(dp(240))
        val handle = GestureSensorStrip()
        val params = WindowManager.LayoutParams(
            sensorWidth,
            dp(22),
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = 0
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                fitInsetsTypes = 0
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        handle.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val gestureInset = insets.mandatorySystemGestureInsets.bottom
                val targetHeight = if (gestureInset > 0) {
                    gestureInset.coerceIn(dp(18), dp(28))
                } else {
                    dp(22)
                }
                if (params.height != targetHeight) {
                    params.height = targetHeight
                    try {
                        manager.updateViewLayout(view, params)
                    } catch (_: RuntimeException) {
                    }
                }
            }
            insets
        }
        handle.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
            if (gestureHandle !== view || view.height <= 0) return@addOnLayoutChangeListener
            val (_, realH) = getRealDisplaySize()
            val loc = IntArray(2)
            view.getLocationOnScreen(loc)
            val actualBottom = loc[1] + view.height
            val gapToBottom = realH - actualBottom
            if (abs(gapToBottom) in 2..dp(64)) {
                params.y -= gapToBottom
                view.post {
                    if (gestureHandle === view) {
                        try {
                            manager.updateViewLayout(view, params)
                        } catch (_: RuntimeException) {
                        }
                    }
                }
            }
        }
        try {
            manager.addView(handle, params)
            gestureHandle = handle
            gestureHandleParams = params
            handle.requestApplyInsets()
        } catch (e: RuntimeException) {
            android.util.Log.w("MyAccessibilityService", "Unable to show gesture sensor", e)
        }
    }

    private fun hideGestureHandle() {
        val handle = gestureHandle ?: return
        gestureHandle = null
        gestureHandleParams = null
        try {
            windowManager?.removeView(handle)
        } catch (e: RuntimeException) {
            android.util.Log.w("MyAccessibilityService", "Unable to remove gesture sensor", e)
        }
    }

    /**
     * When the software keyboard (IME) is open, yield touch focus above the bottom
     * keyboard bar so spacebar / dismissal taps are never intercepted.
     */
    private fun updateSensorForKeyboardState() {
        val handle = gestureHandle ?: return
        val imeOpen = try {
            windows?.any { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD } == true
        } catch (_: Throwable) {
            false
        }
        handle.visibility = if (imeOpen) View.GONE else View.VISIBLE
    }

    private fun requestLiveAppScreenshot() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val hwBuffer = screenshot.hardwareBuffer
                        try {
                            val bmp = Bitmap.wrapHardwareBuffer(hwBuffer, screenshot.colorSpace)
                            compositorView?.attachLiveAppScreenshot(bmp)
                        } catch (_: Throwable) {
                        } finally {
                            // Always close HardwareBuffer after wrapHardwareBuffer to avoid
                            // leaking GraphicBuffer file descriptors across repeated swipes.
                            try {
                                hwBuffer.close()
                            } catch (_: Throwable) {
                            }
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        // Adaptive splash surface card renders automatically on failure/cooldown.
                    }
                }
            )
        } catch (_: Throwable) {
        }
    }

    private fun dispatchHomeNavigation() {
        suppressHandleUntilAppSwitch = true
        hideGestureHandle()

        val epochBefore = LauncherSceneStore.homeResumeEpoch.get()
        var directLaunched = false
        try {
            // Bypass PhoneWindowManager.launchHomeFromHotKey() / MIUI QuickStep's 1.5s freeze
            // by explicitly bringing our own MainActivity task forward with 0ms animation.
            val homeIntent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_HOME)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION
                )
            }
            val noAnimOpts = ActivityOptions.makeCustomAnimation(this, 0, 0).toBundle()
            startActivity(homeIntent, noAnimOpts)
            directLaunched = true
        } catch (e: Exception) {
            android.util.Log.w("MyAccessibilityService", "Direct MainActivity launch blocked, using global home", e)
        }

        if (!directLaunched) {
            performGlobalAction(GLOBAL_ACTION_HOME)
            return
        }

        // Verify within 95ms (while Z-layer 31 is still mid-spring) that MIUI didn't intercept
        // the startActivity call; if MainActivity hasn't resumed yet, trigger GLOBAL_ACTION_HOME.
        mainHandler.postDelayed({
            if (LauncherSceneStore.homeResumeEpoch.get() == epochBefore &&
                LauncherSceneStore.activeForegroundPackage != packageName
            ) {
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
        }, 95L)
    }

    private fun getRealDisplaySize(): Pair<Int, Int> {
        val manager = windowManager
        if (manager != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = manager.currentWindowMetrics.bounds
            if (bounds.width() > 0 && bounds.height() > 0) {
                return bounds.width() to bounds.height()
            }
        }
        val metrics = resources.displayMetrics
        return metrics.widthPixels.coerceAtLeast(1) to metrics.heightPixels.coerceAtLeast(1)
    }

    private fun isSystemOverlayNoise(pkg: String): Boolean =
        pkg == "android" ||
            pkg.contains("inputmethod", ignoreCase = true) ||
            pkg == "com.google.android.inputmethod.latin" ||
            pkg == "com.samsung.android.honeyboard"

    private fun isSystemNavigationUi(pkg: String): Boolean =
        pkg == "com.android.systemui" ||
            pkg.startsWith("com.android.launcher") ||
            pkg == "com.miui.home" ||
            pkg == "com.google.android.apps.nexuslauncher" ||
            pkg == "com.sec.android.app.launcher" ||
            pkg == "com.oplus.launcher" ||
            pkg == "com.oneplus.launcher" ||
            pkg == "com.huawei.android.launcher" ||
            pkg == "com.coloros.launcher" ||
            pkg == "com.vivo.launcher" ||
            pkg == "com.transsion.hilauncher"

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    /**
     * 100% transparent, invisible bottom-bezel touch sensor strip.
     * Relies on Android's native system navigation pill underneath (no double pill)
     * and streams 60/90/120Hz raw pointer coordinates into [GestureCompositorView].
     */
    private inner class GestureSensorStrip : View(this@MyAccessibilityService) {

        private var downX = 0f
        private var downY = 0f
        private var pauseAnchorX = 0f
        private var pauseAnchorY = 0f
        private var draggingStarted = false
        private var recentsTriggered = false
        private var displayW = 1080
        private var displayH = 2400
        private var velocityTracker: VelocityTracker? = null

        private val recentsHoldRunnable = Runnable {
            if (draggingStarted && !recentsTriggered) {
                recentsTriggered = true
                performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                performGlobalAction(GLOBAL_ACTION_RECENTS)
                compositorView?.releaseForRecents()
                hideGestureHandle()
            }
        }

        init {
            contentDescription = getString(R.string.gesture_fallback_handle)
            setBackgroundColor(android.graphics.Color.TRANSPARENT)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    pauseAnchorX = downX
                    pauseAnchorY = downY
                    draggingStarted = false
                    recentsTriggered = false

                    val (w, h) = getRealDisplaySize()
                    displayW = w
                    displayH = h

                    velocityTracker?.recycle()
                    velocityTracker = VelocityTracker.obtain().also {
                        addRawMovement(it, event)
                    }

                    LauncherSceneStore.onHomeSwipeTouchDownCallback?.invoke()
                    compositorView?.prepareSession(
                        foregroundPkg = LauncherSceneStore.activeForegroundPackage,
                        displayW = displayW,
                        displayH = displayH
                    )
                    requestLiveAppScreenshot()
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    velocityTracker?.let { addRawMovement(it, event) }
                    if (recentsTriggered) return true

                    val dx = event.rawX - downX
                    val dy = event.rawY - downY

                    if (!draggingStarted) {
                        val slop = dp(9).toFloat()
                        if (dy <= -slop && abs(dy) >= abs(dx) * 0.65f) {
                            draggingStarted = true
                            pauseAnchorX = event.rawX
                            pauseAnchorY = event.rawY
                            scheduleRecentsHoldCheck(dy)
                        }
                    }

                    if (draggingStarted) {
                        compositorView?.updateFingerDrag(dx, dy)

                        // Reset hold-for-Recents timer whenever finger is still moving
                        val movedFromAnchor = hypot(
                            event.rawX - pauseAnchorX,
                            event.rawY - pauseAnchorY
                        )
                        if (movedFromAnchor > dp(10) || dy > -dp(64)) {
                            pauseAnchorX = event.rawX
                            pauseAnchorY = event.rawY
                            removeCallbacks(recentsHoldRunnable)
                            scheduleRecentsHoldCheck(dy)
                        }
                    }
                    return true
                }

                MotionEvent.ACTION_UP -> {
                    removeCallbacks(recentsHoldRunnable)
                    var vx = 0f
                    var vy = 0f
                    velocityTracker?.let { vt ->
                        addRawMovement(vt, event)
                        vt.computeCurrentVelocity(1000)
                        vx = vt.xVelocity
                        vy = vt.yVelocity
                        vt.recycle()
                    }
                    velocityTracker = null

                    if (recentsTriggered) return true

                    val dx = event.rawX - downX
                    val dy = event.rawY - downY

                    if (!draggingStarted) {
                        // Quick micro-flick check if user flicked faster than a single MOVE sample
                        if (dy <= -dp(18) && vy <= -dp(360) && abs(dx) <= dp(96)) {
                            LauncherSceneStore.markHomeTransitionStarting()
                            compositorView?.updateFingerDrag(dx, dy)
                            compositorView?.commitToHome(vx, vy, displayW, displayH)
                            dispatchHomeNavigation()
                        } else {
                            compositorView?.abortImmediately()
                            LauncherSceneStore.onHomeSwipeCancelledCallback?.invoke()
                        }
                        return true
                    }

                    val shouldCommitHome = vy <= -dp(300) ||
                        (dy <= -dp(48) && vy < dp(360))

                    if (shouldCommitHome) {
                        LauncherSceneStore.markHomeTransitionStarting()
                        compositorView?.commitToHome(vx, vy, displayW, displayH)
                        dispatchHomeNavigation()
                    } else {
                        compositorView?.cancelBackToApp(vx, vy)
                        LauncherSceneStore.onHomeSwipeCancelledCallback?.invoke()
                    }
                    return true
                }

                MotionEvent.ACTION_CANCEL -> {
                    removeCallbacks(recentsHoldRunnable)
                    velocityTracker?.recycle()
                    velocityTracker = null
                    if (draggingStarted && !recentsTriggered) {
                        compositorView?.cancelBackToApp(0f, 0f)
                    } else {
                        compositorView?.abortImmediately()
                    }
                    LauncherSceneStore.onHomeSwipeCancelledCallback?.invoke()
                    return true
                }
            }
            return true
        }

        private fun scheduleRecentsHoldCheck(currentDy: Float) {
            if (currentDy <= -dp(64)) {
                postDelayed(recentsHoldRunnable, 320L)
            }
        }

        private fun addRawMovement(vt: VelocityTracker, event: MotionEvent) {
            val rawEvent = MotionEvent.obtain(event)
            rawEvent.offsetLocation(event.rawX - event.x, event.rawY - event.y)
            vt.addMovement(rawEvent)
            rawEvent.recycle()
        }
    }
}
