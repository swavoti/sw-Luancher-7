package co.za.launcher3.swavoti

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * Passive foreground-package tracker for return-to-icon gesture coordination.
 *
 * Does NOT mount any `TYPE_ACCESSIBILITY_OVERLAY` window or intercept bottom-edge
 * touch events, ensuring Android's native SystemUI / Quickstep gesture handler
 * receives 100% of the swipe from pixel 0 without window collisions or app snap-back.
 */
class MyAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        val app = application as? GoLauncherApplication
        app?.ensureEngineWarmed()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val foregroundPackage = event.packageName?.toString() ?: return
        if (foregroundPackage.isEmpty() ||
            foregroundPackage == "android" ||
            foregroundPackage == "com.android.systemui" ||
            foregroundPackage.contains("inputmethod", ignoreCase = true)
        ) {
            return
        }
        LauncherSceneStore.activeForegroundPackage = foregroundPackage
    }

    override fun onInterrupt() = Unit
}
