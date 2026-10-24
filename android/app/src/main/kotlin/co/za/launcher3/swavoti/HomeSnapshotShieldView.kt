package co.za.launcher3.swavoti

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.View

/**
 * Synchronous Frame-0 anti-flicker backing view hosted directly inside [MainActivity].
 *
 * When [MainActivity] goes to `onStop()` while another app is open, Flutter's
 * `FlutterTextureView` pauses/releases its surface and takes 2–6 VSYNC frames after
 * `onStart()`/`onResume()` to rasterize its first live frame — causing the bare
 * wallpaper flash seen on third-party launchers.
 *
 * Because [HomeSnapshotShieldView] is a pure native Android [View] drawing the
 * in-RAM [LauncherSceneStore.homeUiBitmap] over `MainActivity`'s wallpaper-backed
 * window, Android's `RenderThread` composites it synchronously on **Traversal Frame 0**
 * before WindowManager ever reveals the window. Once Flutter commits its live
 * post-resume frame, [MainActivity] hides this shield on a VSYNC boundary.
 */
class HomeSnapshotShieldView(context: Context) : View(context) {

    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        visibility = GONE
    }

    fun armIfSnapshotAvailable() {
        val bmp = LauncherSceneStore.homeUiBitmap
        if (bmp != null && !bmp.isRecycled && !LauncherSceneStore.isSubRouteOpen) {
            if (visibility != VISIBLE) {
                visibility = VISIBLE
            }
            invalidate()
        }
    }

    fun releaseShield() {
        if (visibility != GONE) {
            visibility = GONE
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val bmp = LauncherSceneStore.homeUiBitmap ?: return
        if (bmp.isRecycled) return

        val loc = IntArray(2)
        getLocationOnScreen(loc)
        val drawX = LauncherSceneStore.homeUiScreenOriginX - loc[0]
        val drawY = LauncherSceneStore.homeUiScreenOriginY - loc[1]
        canvas.drawBitmap(bmp, drawX, drawY, bitmapPaint)
    }
}

