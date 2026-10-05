package co.za.launcher3.swavoti

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class MyAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        (application as GoLauncherApplication).ensureEngineWarmed()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.packageName?.toString() == packageName) {
            (application as GoLauncherApplication).ensureEngineWarmed()
        }
    }

    override fun onInterrupt() = Unit
}
