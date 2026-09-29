package co.za.launcher3.swavoti

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayOutputStream

class IconPackManager(private val context: Context) {
    private var currentIconPack: String? = null
    private val componentToDrawableMap = mutableMapOf<String, String>()

    fun getAvailableIconPacks(): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent("org.adw.launcher.THEMES")
        val resolveInfos = pm.queryIntentActivities(intent, PackageManager.GET_META_DATA)
        
        val packs = mutableListOf<Map<String, String>>()
        for (resolveInfo in resolveInfos) {
            val packageName = resolveInfo.activityInfo.packageName
            val label = resolveInfo.loadLabel(pm).toString()
            packs.add(mapOf("packageName" to packageName, "label" to label))
        }
        return packs
    }

    private fun loadIconPack(packageName: String) {
        if (currentIconPack == packageName) return
        componentToDrawableMap.clear()
        
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
                        }
                    }
                    eventType = parser.next()
                }
            }
        } catch (e: Throwable) {
            e.printStackTrace()
        }
        currentIconPack = packageName
    }

    fun getThemedIcon(appPackageName: String, iconPackPackageName: String): ByteArray? {
        if (iconPackPackageName.isEmpty()) return null
        
        loadIconPack(iconPackPackageName)
        
        // Find component mapping (usually format is ComponentInfo{pkg/class})
        // We try to match just the package name if exact class is not provided
        var drawableName: String? = null
        for ((comp, drw) in componentToDrawableMap) {
            if (comp.contains(appPackageName)) {
                drawableName = drw
                break
            }
        }
        
        if (drawableName == null) return null
        
        try {
            val pm = context.packageManager
            val res = pm.getResourcesForApplication(iconPackPackageName)
            val resId = res.getIdentifier(drawableName, "drawable", iconPackPackageName)
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
