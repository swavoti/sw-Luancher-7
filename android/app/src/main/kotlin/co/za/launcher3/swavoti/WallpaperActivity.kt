package co.za.launcher3.swavoti

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.os.Bundle

class WallpaperActivity : FlutterActivity() {
    override fun getInitialRoute(): String {
        return "/wallpaper"
    }
}
