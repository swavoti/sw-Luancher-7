package co.za.launcher3.swavoti

import android.accessibilityservice.AccessibilityService
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.os.Build
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent

class MyAccessibilityService : AccessibilityService() {
    private var windowManager: WindowManager? = null
    private var gestureHandle: GestureHandle? = null
    private var suppressHandleUntilAppSwitch = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        (application as GoLauncherApplication).ensureEngineWarmed()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return

        val foregroundPackage = event.packageName?.toString() ?: return
        if (foregroundPackage == packageName) {
            suppressHandleUntilAppSwitch = false
            hideGestureHandle()
        } else if (isSystemNavigationUi(foregroundPackage)) {
            hideGestureHandle()
        } else if (suppressHandleUntilAppSwitch) {
            suppressHandleUntilAppSwitch = false
            showGestureHandle()
        } else if (!suppressHandleUntilAppSwitch) {
            showGestureHandle()
        }
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        hideGestureHandle()
        windowManager = null
        super.onDestroy()
    }

    private fun showGestureHandle() {
        if (gestureHandle != null) return
        val manager = windowManager ?: return
        val handle = GestureHandle()
        val params = WindowManager.LayoutParams(
            dp(220),
            dp(24),
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        }
        handle.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val gestureInset = insets.mandatorySystemGestureInsets.bottom
                if (gestureInset > 0 && params.height != gestureInset) {
                    params.height = gestureInset
                    params.y = -gestureInset
                    try {
                        manager.updateViewLayout(view, params)
                    } catch (e: RuntimeException) {
                        android.util.Log.w(
                            "MyAccessibilityService",
                            "Unable to align gesture handle with system inset",
                            e
                        )
                    }
                }
            }
            insets
        }
        try {
            manager.addView(handle, params)
            gestureHandle = handle
            handle.requestApplyInsets()
        } catch (e: RuntimeException) {
            android.util.Log.w("MyAccessibilityService", "Unable to show gesture handle", e)
        }
    }

    private fun hideGestureHandle() {
        val handle = gestureHandle ?: return
        gestureHandle = null
        try {
            windowManager?.removeView(handle)
        } catch (e: RuntimeException) {
            android.util.Log.w("MyAccessibilityService", "Unable to remove gesture handle", e)
        }
    }

    private fun performCustomGesture(action: Int) {
        val succeeded = performGlobalAction(action)
        if (succeeded) {
            suppressHandleUntilAppSwitch = true
            hideGestureHandle()
        } else {
            android.util.Log.w("MyAccessibilityService", "System gesture action failed: $action")
        }
    }

    private fun isSystemNavigationUi(packageName: String): Boolean =
        packageName == "android" ||
            packageName == "com.android.systemui" ||
            packageName.startsWith("com.android.launcher") ||
            packageName == "com.miui.home" ||
            packageName == "com.google.android.apps.nexuslauncher" ||
            packageName == "com.sec.android.app.launcher" ||
            packageName == "com.oplus.launcher" ||
            packageName == "com.oneplus.launcher" ||
            packageName == "com.huawei.android.launcher" ||
            packageName == "com.coloros.launcher" ||
            packageName == "com.vivo.launcher" ||
            packageName == "com.transsion.hilauncher"

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    private inner class GestureHandle : View(this@MyAccessibilityService) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var downX = 0f
        private var downY = 0f
        private var downTime = 0L

        init {
            contentDescription = getString(R.string.gesture_fallback_handle)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            paint.color = Color.BLACK
            paint.alpha = 75
            canvas.drawRoundRect(
                width * 0.34f,
                height * 0.34f,
                width * 0.66f,
                height * 0.66f,
                dp(6).toFloat(),
                dp(6).toFloat(),
                paint
            )
            paint.color = Color.WHITE
            paint.alpha = 225
            canvas.drawRoundRect(
                width * 0.40f,
                height * 0.44f,
                width * 0.60f,
                height * 0.56f,
                dp(4).toFloat(),
                dp(4).toFloat(),
                paint
            )
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    downTime = SystemClock.uptimeMillis()
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    val deltaX = event.rawX - downX
                    val deltaY = event.rawY - downY
                    val elapsed = SystemClock.uptimeMillis() - downTime
                    if (kotlin.math.abs(deltaX) <= dp(96)) {
                        when {
                            deltaY <= -dp(36) -> {
                                val action = if (elapsed >= 450L) {
                                    GLOBAL_ACTION_RECENTS
                                } else {
                                    GLOBAL_ACTION_HOME
                                }
                                performCustomGesture(action)
                            }
                            kotlin.math.abs(deltaY) <= dp(12) -> {
                                performCustomGesture(GLOBAL_ACTION_HOME)
                            }
                        }
                    }
                    return true
                }
                MotionEvent.ACTION_CANCEL -> return true
            }
            return true
        }
    }
}
