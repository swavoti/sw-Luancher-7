package co.za.launcher3.swavoti

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode

/**
 * Dedicated activity for Android Settings -> Gesture Navigation -> "See demo".
 * Launches directly into the Flutter GestureDemoPage route.
 */
class GestureDemoActivity : FlutterActivity() {
    override fun getInitialRoute(): String = "/gesture_demo"

    override fun getRenderMode(): RenderMode = RenderMode.texture
}
