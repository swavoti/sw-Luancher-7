package co.za.launcher3.swavoti

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Base class for standalone launcher sub-activities (Weather, Home Settings, Edit Icons).
 *
 * Each sub-activity intentionally uses its own isolated FlutterEngine rather than
 * MainActivity's cached engine (`GoLauncherApplication.ENGINE_ID`). This guarantees that
 * MainActivity's FlutterView and GPU surface are never detached or destroyed while a
 * sub-activity is open, and pressing Back finishes ONLY this activity and returns
 * immediately to the live, intact MainActivity underneath.
 */
abstract class SubLauncherActivity : FlutterActivity() {

    private val systemChannelName = "co.za.launcher3.swavoti/system"
    private val bgExecutor = Executors.newFixedThreadPool(2)
    private lateinit var iconPackManager: IconPackManager

    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        iconPackManager = IconPackManager(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openWeatherActivity" -> {
                        startActivity(Intent(this, WeatherActivity::class.java))
                        result.success(true)
                    }
                    "openHomeSettingsActivity" -> {
                        startActivity(Intent(this, HomeSettingsActivity::class.java))
                        result.success(true)
                    }
                    "openEditIconsActivity" -> {
                        startActivity(Intent(this, EditIconsActivity::class.java))
                        result.success(true)
                    }
                    "isDefaultLauncher" -> {
                        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                        }
                        val resolveInfo = packageManager.resolveActivity(homeIntent, 0)
                        result.success(resolveInfo?.activityInfo?.packageName == packageName)
                    }
                    "openDefaultLauncherSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
                        } catch (_: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_SETTINGS))
                            } catch (_: Exception) {}
                        }
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        } catch (_: Exception) {}
                        result.success(null)
                    }
                    "getAvailableIconPacks" -> {
                        bgExecutor.execute {
                            val packs = try {
                                iconPackManager.getAvailableIconPacks()
                            } catch (_: Throwable) {
                                emptyList()
                            }
                            runOnUiThread { result.success(packs) }
                        }
                    }
                    "getThemedIcon" -> {
                        val appPkg = call.argument<String>("packageName") ?: ""
                        val packPkg = call.argument<String>("iconPack") ?: ""
                        bgExecutor.execute {
                            val bytes = try {
                                iconPackManager.getThemedIcon(appPkg, packPkg)
                            } catch (_: Throwable) {
                                null
                            }
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                    "getMonochromeIcon" -> {
                        val pkg = call.argument<String>("packageName") ?: ""
                        bgExecutor.execute {
                            val bytes = loadMonochromeIconBytes(pkg)
                            runOnUiThread { result.success(bytes) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        bgExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun loadMonochromeIconBytes(pkg: String): ByteArray? {
        if (pkg.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return null
        return try {
            val launcherApps = getSystemService(Context.LAUNCHER_APPS_SERVICE) as? android.content.pm.LauncherApps
            val activities = launcherApps?.getActivityList(pkg, android.os.Process.myUserHandle())
            val rawDrawable: Drawable? = if (!activities.isNullOrEmpty()) {
                activities[0].getIcon(resources.displayMetrics.densityDpi)
            } else {
                val appInfo = packageManager.getApplicationInfo(pkg, 0)
                packageManager.getApplicationIcon(appInfo)
            }
            val mono = (rawDrawable as? AdaptiveIconDrawable)?.monochrome ?: return null
            val size = 96
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            mono.setBounds(0, 0, size, size)
            mono.draw(canvas)
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (_: Throwable) {
            null
        }
    }
}

class WeatherActivity : SubLauncherActivity() {
    override fun getInitialRoute(): String = "/weather"
}

class HomeSettingsActivity : SubLauncherActivity() {
    override fun getInitialRoute(): String = "/settings"
}

class EditIconsActivity : SubLauncherActivity() {
    override fun getInitialRoute(): String = "/edit_icons"
}
