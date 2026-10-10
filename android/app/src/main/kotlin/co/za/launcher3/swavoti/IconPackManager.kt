package co.za.launcher3.swavoti

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayOutputStream

class IconPackManager(private val context: Context) {
    private var currentIconPack: String? = null
    private val componentToDrawableMap = mutableMapOf<String, String>()
    private val packageToDrawableMap = HashMap<String, String>()

    fun getAvailableIconPacks(): List<Map<String, Any>> {
        val pm = context.packageManager
        val themeActions = listOf(
            "org.adw.launcher.THEMES",
            "com.novalauncher.THEME",
            "com.anddoes.launcher.THEME",
            "com.teslacoilsw.launcher.THEME",
            "com.gau.go.launcherex.theme"
        )
        val packsByPackage = linkedMapOf<String, Map<String, Any>>()
        for (action in themeActions) {
            val intent = Intent(action)
            val resolveInfos = pm.queryIntentActivities(intent, PackageManager.GET_META_DATA)
            for (resolveInfo in resolveInfos) {
                val packageName = resolveInfo.activityInfo.packageName
                packsByPackage.putIfAbsent(
                    packageName,
                    mapOf(
                        "packageName" to packageName,
                        "label" to resolveInfo.loadLabel(pm).toString(),
                        "icon" to drawableToByteArray(resolveInfo.loadIcon(pm))
                    )
                )
            }
        }
        return packsByPackage.values.toList()
    }

    @Synchronized
    private fun loadIconPack(packageName: String) {
        if (currentIconPack == packageName) return
        componentToDrawableMap.clear()
        packageToDrawableMap.clear()
        currentIconPack = null
        
        try {
            val pm = context.packageManager
            val res = pm.getResourcesForApplication(packageName)
            val resId = res.getIdentifier("appfilter", "xml", packageName)
            if (resId != 0) {
                val parser = res.getXml(resId)
                var eventType = parser.eventType
                while (eventType != XmlPullParser.END_DOCUMENT) {
                    if (eventType == XmlPullParser.START_TAG && parser.name == "item") {
                        val component = parser.getAttributeValue(null, "component")
                        val drawable = parser.getAttributeValue(null, "drawable")
                        if (component != null && drawable != null) {
                            componentToDrawableMap[component] = drawable
                            val flattened = component
                                .removePrefix("ComponentInfo{")
                                .removeSuffix("}")
                            val pkg = flattened.substringBefore('/')
                            if (pkg.isNotEmpty() && !packageToDrawableMap.containsKey(pkg)) {
                                packageToDrawableMap[pkg] = drawable
                            }
                        }
                    }
                    eventType = parser.next()
                }
                parser.close()
            }
            currentIconPack = packageName
        } catch (e: Throwable) {
            componentToDrawableMap.clear()
            packageToDrawableMap.clear()
            android.util.Log.w("IconPackManager", "Unable to load icon pack $packageName", e)
        }
    }

    fun getThemedIcon(appPackageName: String, iconPackPackageName: String): ByteArray? {
        if (iconPackPackageName.isEmpty()) return null
        
        loadIconPack(iconPackPackageName)
        
        val drawableName = packageToDrawableMap[appPackageName]
            ?: componentToDrawableMap.entries.firstOrNull { (component, _) ->
                val flattenedComponent = component
                    .removePrefix("ComponentInfo{")
                    .removeSuffix("}")
                flattenedComponent.substringBefore('/') == appPackageName
            }?.value

        if (drawableName == null) return null
        
        try {
            val pm = context.packageManager
            val res = pm.getResourcesForApplication(iconPackPackageName)
            val resId = res.getIdentifier(drawableName, "drawable", iconPackPackageName)
                .takeIf { it != 0 }
                ?: res.getIdentifier(drawableName, "mipmap", iconPackPackageName)
            if (resId != 0) {
                val drawable = res.getDrawable(resId, null) ?: return null
                return drawableToByteArray(drawable)
            }
        } catch (e: Throwable) {
            e.printStackTrace()
        }
        return null
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        var width = Math.max(1, drawable.intrinsicWidth)
        var height = Math.max(1, drawable.intrinsicHeight)
        
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
