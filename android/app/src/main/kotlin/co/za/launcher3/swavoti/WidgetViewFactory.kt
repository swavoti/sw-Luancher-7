package co.za.launcher3.swavoti

import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.FrameLayout
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap

class WidgetViewFactory(
    private val appWidgetHost: AppWidgetHost
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        private val activeHostViews = ConcurrentHashMap<Int, WeakReference<AppWidgetHostView>>()

        fun registerHostView(appWidgetId: Int, hostView: AppWidgetHostView) {
            if (appWidgetId != -1) {
                activeHostViews[appWidgetId] = WeakReference(hostView)
            }
        }

        fun unregisterHostView(appWidgetId: Int, hostView: AppWidgetHostView?) {
            if (appWidgetId == -1) return
            val current = activeHostViews[appWidgetId]?.get()
            if (current == null || current === hostView) {
                activeHostViews.remove(appWidgetId)
            }
        }

        fun updateWidgetSize(
            context: Context,
            appWidgetId: Int,
            minWidthDp: Int,
            minHeightDp: Int,
            maxWidthDp: Int,
            maxHeightDp: Int
        ): Boolean {
            if (appWidgetId == -1) return false
            return try {
                val manager = AppWidgetManager.getInstance(context)
                val safeMinW = minWidthDp.coerceAtLeast(16)
                val safeMinH = minHeightDp.coerceAtLeast(16)
                val safeMaxW = maxWidthDp.coerceAtLeast(safeMinW)
                val safeMaxH = maxHeightDp.coerceAtLeast(safeMinH)

                val existing = manager.getAppWidgetOptions(appWidgetId)
                val options = if (existing != null) Bundle(existing) else Bundle()
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, safeMinW)
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, safeMinH)
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, safeMaxW)
                options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, safeMaxH)

                val sizes = arrayListOf<SizeF>()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    sizes.add(SizeF(safeMinW.toFloat(), safeMinH.toFloat()))
                    if (safeMaxW != safeMinW || safeMaxH != safeMinH) {
                        sizes.add(SizeF(safeMaxW.toFloat(), safeMaxH.toFloat()))
                    }
                    options.putParcelableArrayList(
                        AppWidgetManager.OPTION_APPWIDGET_SIZES,
                        sizes
                    )
                }

                manager.updateAppWidgetOptions(appWidgetId, options)

                val hostView = activeHostViews[appWidgetId]?.get()
                if (hostView != null) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        hostView.updateAppWidgetSize(options, sizes)
                    } else {
                        @Suppress("DEPRECATION")
                        hostView.updateAppWidgetSize(
                            options,
                            safeMinW,
                            safeMinH,
                            safeMaxW,
                            safeMaxH
                        )
                    }
                    hostView.requestLayout()
                }
                true
            } catch (t: Throwable) {
                android.util.Log.w("WidgetViewFactory", "Failed to update widget size", t)
                false
            }
        }

        fun captureSnapshotBytes(appWidgetId: Int, maxSidePx: Int = 360): ByteArray? {
            val hostView = activeHostViews[appWidgetId]?.get() ?: return null
            val rawW = hostView.width
            val rawH = hostView.height
            if (rawW <= 4 || rawH <= 4) return null
            return try {
                val scale = minOf(1f, maxSidePx.toFloat() / maxOf(rawW, rawH).toFloat())
                val outW = (rawW * scale).toInt().coerceAtLeast(1)
                val outH = (rawH * scale).toInt().coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                canvas.scale(scale, scale)
                hostView.draw(canvas)
                val bytes = ByteArrayOutputStream().use { out ->
                    @Suppress("DEPRECATION")
                    val format = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        Bitmap.CompressFormat.WEBP_LOSSY
                    } else {
                        Bitmap.CompressFormat.WEBP
                    }
                    bitmap.compress(format, 80, out)
                    out.toByteArray()
                }
                bitmap.recycle()
                bytes
            } catch (_: Throwable) {
                null
            }
        }
    }

    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val appWidgetId = (params?.get("appWidgetId") as? Number)?.toInt() ?: -1
        val widthDp = (params?.get("widthDp") as? Number)?.toInt()
        val heightDp = (params?.get("heightDp") as? Number)?.toInt()
        return WidgetPlatformView(context, appWidgetHost, appWidgetId, widthDp, heightDp)
    }
}

class WidgetPlatformView(
    private val context: Context,
    private val appWidgetHost: AppWidgetHost,
    private val appWidgetId: Int,
    initialWidthDp: Int?,
    initialHeightDp: Int?
) : PlatformView {

    private var view: View? = null
    private var hostView: AppWidgetHostView? = null

    init {
        try {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val appWidgetInfo = appWidgetManager.getAppWidgetInfo(appWidgetId)
            if (appWidgetInfo != null) {
                val created = appWidgetHost.createView(context, appWidgetId, appWidgetInfo)
                created.setPadding(0, 0, 0, 0)
                hostView = created
                view = created
                WidgetViewFactory.registerHostView(appWidgetId, created)
                if (initialWidthDp != null && initialHeightDp != null &&
                    initialWidthDp > 0 && initialHeightDp > 0
                ) {
                    WidgetViewFactory.updateWidgetSize(
                        context,
                        appWidgetId,
                        initialWidthDp,
                        initialHeightDp,
                        initialWidthDp,
                        initialHeightDp
                    )
                }
            } else {
                view = FrameLayout(context)
            }
        } catch (t: Throwable) {
            view = FrameLayout(context)
        }
    }

    override fun getView(): View? = view

    override fun dispose() {
        WidgetViewFactory.unregisterHostView(appWidgetId, hostView)
        hostView = null
    }
}
