package co.za.launcher3.swavoti

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Region
import android.os.Build
import android.view.Choreographer
import android.view.View
import kotlin.math.max
import kotlin.math.min

/**
 * 60/90/120Hz hardware-accelerated Sub-Mini Compositor surface rendered inside
 * `TYPE_ACCESSIBILITY_OVERLAY` (SurfaceFlinger Z-layer 31).
 *
 * Completely occludes broken OEM/AOSP QuickStep third-party launcher animations
 * while compositing three synchronized layers every VSYNC:
 *  1. Wallpaper backdrop with subtle depth settle (`1.03x -> 1.00x`) + dynamic scrim.
 *  2. Cached transparent Flutter Home UI (`1.0` alpha, `0.96x -> 1.00x` scale) with
 *     the destination app icon slot cleanly punched out while the card is in flight.
 *  3. Live foreground app GPU `HardwareBuffer` card tracking the user's thumb 1:1
 *     and spring-morphing with momentum + icon crossfade directly into the exact
 *     Home/Dock icon slot.
 */
class GestureCompositorView(
    context: Context,
    private val onCurtainDropped: () -> Unit
) : View(context) {

    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val iconPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val surfacePaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val scrimPaint = Paint()
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private val cardRect = RectF()
    private val punchRect = RectF()
    private val clipPath = Path()
    private val drawMatrix = Matrix()
    private val overlayScreenLoc = IntArray(2)

    private var appScreenshotBitmap: Bitmap? = null
    private var softwareFallbackScreenshot: Bitmap? = null
    private var appIconBitmap: Bitmap? = null
    private var appFallbackSurfaceColor: Int = Color.rgb(18, 19, 22)

    private var activeTarget: LauncherSceneStore.IconTargetSpec? = null
    private var currentState: SpringMorphPhysics.State? = null
    private var springSettledToHome = false
    private var isAwaitingHomeReady = false
    private var sessionActive = false

    private val safetyReleaseRunnable = Runnable {
        if (sessionActive && isAwaitingHomeReady) {
            dropCurtainNow()
        }
    }

    private val homeReadyListener: () -> Unit = {
        if (sessionActive && isAwaitingHomeReady && springSettledToHome) {
            // Wait 1 Choreographer VSYNC so MainActivity's newly committed frame
            // is guaranteed latched by SurfaceFlinger before hiding Z-layer 31.
            Choreographer.getInstance().postFrameCallback {
                if (sessionActive && isAwaitingHomeReady) {
                    dropCurtainNow()
                }
            }
        }
    }

    private val physics = SpringMorphPhysics(
        onFrameUpdate = { state ->
            currentState = state
            invalidate()
        },
        onSettled = { settledToHome ->
            if (!settledToHome) {
                // User cancelled swipe back into foreground app — release immediately.
                dropCurtainNow()
            } else {
                springSettledToHome = true
                if (LauncherSceneStore.isHomeActivityDrawnAndReady.get()) {
                    Choreographer.getInstance().postFrameCallback {
                        if (sessionActive) dropCurtainNow()
                    }
                } else {
                    isAwaitingHomeReady = true
                    removeCallbacks(safetyReleaseRunnable)
                    postDelayed(safetyReleaseRunnable, 260L)
                }
            }
        }
    )

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        visibility = GONE
        LauncherSceneStore.addHomeReadyListener(homeReadyListener)
    }

    fun destroy() {
        LauncherSceneStore.removeHomeReadyListener(homeReadyListener)
        abortImmediately()
    }

    val isSessionActive: Boolean
        get() = sessionActive

    /**
     * Prepares a new gesture session on `ACTION_DOWN` without revealing the
     * compositor surface yet (revealed once upward drag crosses touch slop).
     */
    fun prepareSession(
        foregroundPkg: String?,
        displayW: Int,
        displayH: Int
    ) {
        removeCallbacks(safetyReleaseRunnable)
        physics.beginDrag(displayW.toFloat(), displayH.toFloat())

        sessionActive = true
        springSettledToHome = false
        isAwaitingHomeReady = false
        appScreenshotBitmap = null
        softwareFallbackScreenshot = null

        val visual = LauncherSceneStore.getAppVisualImmediate(context, foregroundPkg)
        appIconBitmap = visual?.iconBitmap
        appFallbackSurfaceColor = visual?.dominantSurfaceColor ?: Color.rgb(18, 19, 22)
        activeTarget = LauncherSceneStore.resolveReturnTarget(foregroundPkg)
        currentState = null
    }

    /** Attaches the zero-copy GPU `HardwareBuffer` screenshot when `takeScreenshot` completes. */
    fun attachLiveAppScreenshot(bitmap: Bitmap?) {
        if (!sessionActive || bitmap == null) return
        appScreenshotBitmap = bitmap
        softwareFallbackScreenshot = null
        if (visibility == VISIBLE) {
            invalidate()
        }
    }

    /** Updates 1:1 finger tracking on `ACTION_MOVE` and ensures surface is visible. */
    fun updateFingerDrag(deltaX: Float, deltaY: Float) {
        if (!sessionActive) return
        currentState = physics.updateDrag(deltaX, deltaY)
        if (visibility != VISIBLE) {
            visibility = VISIBLE
        }
        invalidate()
    }

    /** Commits to spring-morphing the window into its Home icon (or center fade). */
    fun commitToHome(velocityX: Float, velocityY: Float, displayW: Int, displayH: Int) {
        if (!sessionActive) return
        if (visibility != VISIBLE) {
            visibility = VISIBLE
        }

        getLocationOnScreen(overlayScreenLoc)
        val target = activeTarget
        if (target != null && target.screenRect.width() > 4f && target.screenRect.height() > 4f) {
            val localLeft = target.screenRect.left - overlayScreenLoc[0]
            val localTop = target.screenRect.top - overlayScreenLoc[1]
            val targetW = target.screenRect.width()
            val targetH = target.screenRect.height()
            val cornerRatio = if (target.isFolderSlot) {
                0.285f // Matches Home Folder 16dp / 56dp rounded container
            } else {
                shapeToCornerRatio(target.iconShape)
            }

            physics.animateToHomeTarget(
                velocityX = velocityX,
                velocityY = velocityY,
                targetCenterX = localLeft + targetW * 0.5f,
                targetCenterY = localTop + targetH * 0.5f,
                targetWidth = targetW,
                targetHeight = targetH,
                targetCornerRatio = cornerRatio
            )
        } else {
            // App was launched from Drawer with no Home/Dock shortcut: smooth center scale-fade.
            physics.animateToHomeTarget(
                velocityX = velocityX,
                velocityY = velocityY,
                targetCenterX = displayW * 0.5f,
                targetCenterY = displayH * 0.46f,
                targetWidth = displayW * 0.42f,
                targetHeight = displayH * 0.42f,
                targetCornerRatio = 0.14f
            )
        }
    }

    /** Springs the dragged app window back to full-screen when user reverses downward. */
    fun cancelBackToApp(velocityX: Float, velocityY: Float) {
        if (!sessionActive) return
        if (visibility != VISIBLE) {
            dropCurtainNow()
            return
        }
        physics.animateCancelBackToApp(velocityX, velocityY)
    }

    /** Releases overlay gracefully when transitioning into system Recents (`GLOBAL_ACTION_RECENTS`). */
    fun releaseForRecents() {
        dropCurtainNow()
    }

    fun abortImmediately() {
        if (!sessionActive && visibility == GONE) return
        dropCurtainNow()
    }

    private fun dropCurtainNow() {
        removeCallbacks(safetyReleaseRunnable)
        physics.stop()
        sessionActive = false
        springSettledToHome = false
        isAwaitingHomeReady = false
        currentState = null
        appScreenshotBitmap = null
        softwareFallbackScreenshot = null
        if (visibility != GONE) {
            visibility = GONE
        }
        onCurtainDropped()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val state = currentState ?: return
        val viewW = width.toFloat().coerceAtLeast(1f)
        val viewH = height.toFloat().coerceAtLeast(1f)

        getLocationOnScreen(overlayScreenLoc)
        val progress = state.progress.coerceIn(0f, 1f)

        // ── Layer 1: Wallpaper Backdrop + Depth Settle + Dynamic Scrim ──────────
        val wp = LauncherSceneStore.wallpaperBitmap
        if (wp != null && !wp.isRecycled) {
            val wpScale = 1f + 0.032f * (1f - progress)
            drawMatrix.reset()
            val sx = (viewW / wp.width.toFloat()) * wpScale
            val sy = (viewH / wp.height.toFloat()) * wpScale
            drawMatrix.postScale(sx, sy)
            drawMatrix.postTranslate(
                (viewW - wp.width * sx) * 0.5f,
                (viewH - wp.height * sy) * 0.5f
            )
            bitmapPaint.alpha = 255
            canvas.drawBitmap(wp, drawMatrix, bitmapPaint)
        } else {
            canvas.drawColor(Color.BLACK)
        }

        val scrimAlpha = ((1f - progress) * 58f).toInt().coerceIn(0, 90)
        if (scrimAlpha > 0) {
            scrimPaint.color = Color.argb(scrimAlpha, 0, 0, 0)
            canvas.drawRect(0f, 0f, viewW, viewH, scrimPaint)
        }

        // ── Layer 2: Cached Transparent Flutter Home UI (Target Slot Masked) ────
        val homeUi = LauncherSceneStore.homeUiBitmap
        val target = activeTarget
        val hasValidIconTarget =
            target != null && target.screenRect.width() > 4f && target.screenRect.height() > 4f

        if (homeUi != null && !homeUi.isRecycled) {
            val saveCount = canvas.save()
            val homeScale = 0.965f + 0.035f * progress
            canvas.scale(homeScale, homeScale, viewW * 0.5f, viewH * 0.5f)

            // Punch out the target icon rectangle while the morphing window is still in flight
            // so the user never sees a static icon underneath the incoming morphing icon.
            // (For Folder slots, keep the 2x2 Folder preview underneath so the card dissolves smoothly into it.)
            if (hasValidIconTarget && target != null && !target.isFolderSlot && progress < 0.995f) {
                punchRect.set(
                    target.screenRect.left - overlayScreenLoc[0] - 2f,
                    target.screenRect.top - overlayScreenLoc[1] - 2f,
                    target.screenRect.right - overlayScreenLoc[0] + 2f,
                    target.screenRect.bottom - overlayScreenLoc[1] + 2f
                )
                clipOutCompat(canvas, punchRect)
            }

            val uiX = LauncherSceneStore.homeUiScreenOriginX - overlayScreenLoc[0]
            val uiY = LauncherSceneStore.homeUiScreenOriginY - overlayScreenLoc[1]
            bitmapPaint.alpha = (155 + (100 * progress).toInt()).coerceIn(0, 255)
            canvas.drawBitmap(homeUi, uiX, uiY, bitmapPaint)
            canvas.restoreToCount(saveCount)
        }

        // ── Layer 3: Morphing Live App Window -> Target Icon ────────────────────
        val halfW = state.width * 0.5f
        val halfH = state.height * 0.5f
        cardRect.set(
            state.centerX - halfW,
            state.centerY - halfH,
            state.centerX + halfW,
            state.centerY + halfH
        )

        val isFolderTarget = hasValidIconTarget && target?.isFolderSlot == true
        val overallCardAlpha = when {
            !state.isSettlingToHome -> 1f
            isFolderTarget -> (1f - smoothStep(0.68f, 0.98f, progress)).coerceIn(0f, 1f)
            hasValidIconTarget -> 1f
            else -> (1f - smoothStep(0.32f, 0.96f, progress)).coerceIn(0f, 1f)
        }
        if (overallCardAlpha <= 0.005f) return

        val minSide = min(cardRect.width(), cardRect.height())
        val radiusPx = (minSide * state.cornerRadiusRatio).coerceAtLeast(0f)

        // Subtle elevation shadow behind floating card while mid-air
        val shadowStrength = (1f - progress) * overallCardAlpha
        if (shadowStrength > 0.04f && progress > 0.02f) {
            shadowPaint.color = Color.argb((shadowStrength * 48f).toInt().coerceIn(0, 64), 0, 0, 0)
            canvas.drawRoundRect(
                cardRect.left,
                cardRect.top + 6f,
                cardRect.right,
                cardRect.bottom + 10f,
                radiusPx,
                radiusPx,
                shadowPaint
            )
        }

        val cardSave = canvas.save()
        buildMorphClipPath(
            outPath = clipPath,
            rect = cardRect,
            radiusPx = radiusPx,
            shape = if (isFolderTarget) "Rounded Rectangle" else (target?.iconShape ?: LauncherSceneStore.currentIconShape),
            morphProgress = progress
        )
        canvas.clipPath(clipPath)

        // Crossfade schedule:
        //  0.00 .. 0.45 -> 100% live app texture
        //  0.45 .. 0.90 -> smooth crossfade into crisp target app icon
        //  0.90 .. 1.00 -> 100% crisp target app icon
        val iconReveal = if (hasValidIconTarget && appIconBitmap != null) {
            smoothStep(0.42f, 0.88f, progress)
        } else {
            0f
        }
        val appContentAlpha = ((1f - iconReveal) * overallCardAlpha * 255f).toInt().coerceIn(0, 255)
        val iconOverlayAlpha = (iconReveal * overallCardAlpha * 255f).toInt().coerceIn(0, 255)

        if (appContentAlpha > 0) {
            val liveBmp = resolveDrawableScreenshot(canvas)
            if (liveBmp != null && !liveBmp.isRecycled) {
                // Scale uniformly from top-center of app window so header doesn't squash
                val scale = max(
                    cardRect.width() / liveBmp.width.toFloat(),
                    cardRect.height() / liveBmp.height.toFloat()
                )
                drawMatrix.reset()
                drawMatrix.postScale(scale, scale)
                drawMatrix.postTranslate(
                    cardRect.centerX() - (liveBmp.width * scale) * 0.5f,
                    cardRect.top
                )
                bitmapPaint.alpha = appContentAlpha
                canvas.drawBitmap(liveBmp, drawMatrix, bitmapPaint)
            } else {
                // Instant adaptive splash card fallback (API < 30, FLAG_SECURE, or <333ms cooldown)
                surfacePaint.color = appFallbackSurfaceColor
                surfacePaint.alpha = appContentAlpha
                canvas.drawRect(cardRect, surfacePaint)

                val fallbackIcon = appIconBitmap
                if (fallbackIcon != null && !fallbackIcon.isRecycled) {
                    val iconSide = min(cardRect.width(), cardRect.height()) *
                        (0.28f + 0.72f * smoothStep(0.2f, 0.85f, progress))
                    val halfIcon = iconSide * 0.5f
                    val dst = RectF(
                        cardRect.centerX() - halfIcon,
                        cardRect.centerY() - halfIcon,
                        cardRect.centerX() + halfIcon,
                        cardRect.centerY() + halfIcon
                    )
                    iconPaint.alpha = appContentAlpha
                    canvas.drawBitmap(fallbackIcon, null, dst, iconPaint)
                }
            }
        }

        val iconBmp = appIconBitmap
        if (iconOverlayAlpha > 0 && iconBmp != null && !iconBmp.isRecycled) {
            iconPaint.alpha = iconOverlayAlpha
            canvas.drawBitmap(iconBmp, null, cardRect, iconPaint)
        }

        canvas.restoreToCount(cardSave)
    }

    private fun resolveDrawableScreenshot(canvas: Canvas): Bitmap? {
        val raw = appScreenshotBitmap ?: return null
        if (raw.isRecycled) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            raw.config == Bitmap.Config.HARDWARE &&
            !canvas.isHardwareAccelerated
        ) {
            if (softwareFallbackScreenshot == null) {
                softwareFallbackScreenshot = try {
                    raw.copy(Bitmap.Config.ARGB_8888, false)
                } catch (_: Throwable) {
                    null
                }
            }
            return softwareFallbackScreenshot
        }
        return raw
    }

    private fun clipOutCompat(canvas: Canvas, rect: RectF) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            canvas.clipOutRect(rect)
        } else {
            @Suppress("DEPRECATION")
            canvas.clipRect(rect, Region.Op.DIFFERENCE)
        }
    }

    private fun buildMorphClipPath(
        outPath: Path,
        rect: RectF,
        radiusPx: Float,
        shape: String,
        morphProgress: Float
    ) {
        outPath.reset()
        if (shape == "Teardrop" && morphProgress > 0.35f) {
            val t = smoothStep(0.35f, 1.0f, morphProgress)
            val minSide = min(rect.width(), rect.height())
            val roundCorner = radiusPx
            val sharpCorner = radiusPx * (1f - 0.78f * t) + (minSide * 0.08f) * t
            val radii = floatArrayOf(
                roundCorner, roundCorner, // top-left
                sharpCorner, sharpCorner, // top-right (matches _TeardropClipper)
                roundCorner, roundCorner, // bottom-right
                roundCorner, roundCorner  // bottom-left
            )
            outPath.addRoundRect(rect, radii, Path.Direction.CW)
        } else {
            outPath.addRoundRect(rect, radiusPx, radiusPx, Path.Direction.CW)
        }
    }

    private fun shapeToCornerRatio(shape: String): Float = when (shape) {
        "Circle" -> 0.50f
        "Squircle" -> 0.28f
        "Rounded Rectangle" -> 0.20f
        "Teardrop" -> 0.45f
        else -> 0.24f
    }

    private fun smoothStep(edge0: Float, edge1: Float, x: Float): Float {
        if (edge1 <= edge0) return if (x >= edge1) 1f else 0f
        val t = ((x - edge0) / (edge1 - edge0)).coerceIn(0f, 1f)
        return t * t * (3f - 2f * t)
    }
}

