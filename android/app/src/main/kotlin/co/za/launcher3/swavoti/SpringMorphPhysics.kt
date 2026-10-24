package co.za.launcher3.swavoti

import android.view.Choreographer
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Frame-rate-independent (60Hz / 90Hz / 120Hz / 144Hz) coupled 2D damped spring
 * physics solver driven directly by [Choreographer.FrameCallback].
 *
 * Seeds initial X/Y velocities from the user's [android.view.VelocityTracker]
 * on `ACTION_UP` so fast or angled flicks arc naturally along the finger's
 * momentum vector into the destination icon slot with zero velocity discontinuity.
 */
class SpringMorphPhysics(
    private val onFrameUpdate: (State) -> Unit,
    private val onSettled: (settledToHome: Boolean) -> Unit
) {

    data class State(
        val centerX: Float,
        val centerY: Float,
        val width: Float,
        val height: Float,
        val cornerRadiusRatio: Float,
        /** 0 = full-screen app, 1 = completely morphed into home/icon. */
        val progress: Float,
        val isSettlingToHome: Boolean
    )

    private class Spring1D(
        var value: Float = 0f,
        var velocity: Float = 0f,
        var target: Float = 0f,
        var stiffness: Float = 440f,
        var dampingRatio: Float = 0.94f
    ) {
        fun reset(initial: Float, initialVelocity: Float = 0f) {
            value = initial
            velocity = initialVelocity
            target = initial
        }

        fun step(dtSec: Float) {
            if (dtSec <= 0f) return
            // Sub-step integration (max 4ms per sub-step) guarantees unconditional
            // numerical stability even across dropped frames while remaining exact
            // across 60Hz, 90Hz, 120Hz, and 144Hz VSYNC intervals.
            val steps = max(1, (dtSec / 0.004f).toInt() + 1)
            val h = dtSec / steps
            val damping = 2f * dampingRatio * sqrt(stiffness)

            for (i in 0 until steps) {
                val displacement = value - target
                val accel = -stiffness * displacement - damping * velocity
                velocity += accel * h
                value += velocity * h
            }
        }

        fun isAtRest(posThreshold: Float, velThreshold: Float): Boolean {
            return abs(value - target) <= posThreshold && abs(velocity) <= velThreshold
        }
    }

    private val springX = Spring1D(stiffness = 430f, dampingRatio = 0.92f)
    private val springY = Spring1D(stiffness = 430f, dampingRatio = 0.92f)
    private val springW = Spring1D(stiffness = 470f, dampingRatio = 0.96f)
    private val springH = Spring1D(stiffness = 470f, dampingRatio = 0.96f)
    private val springCorner = Spring1D(stiffness = 500f, dampingRatio = 0.98f)
    private val springProgress = Spring1D(stiffness = 460f, dampingRatio = 0.96f)

    private var screenW = 1080f
    private var screenH = 2400f
    private var running = false
    private var settlingToHome = true
    private var lastFrameNanos = 0L

    val isRunning: Boolean
        get() = running

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!running) return

            val dtSec = if (lastFrameNanos == 0L) {
                1f / 120f
            } else {
                ((frameTimeNanos - lastFrameNanos) * 1e-9f).coerceIn(0.001f, 0.034f)
            }
            lastFrameNanos = frameTimeNanos

            springX.step(dtSec)
            springY.step(dtSec)
            springW.step(dtSec)
            springH.step(dtSec)
            springCorner.step(dtSec)
            springProgress.step(dtSec)

            val currentW = max(16f, springW.value)
            val currentH = max(16f, springH.value)
            val currentProgress = springProgress.value.coerceIn(0f, 1f)

            val done = springX.isAtRest(1.2f, 24f) &&
                springY.isAtRest(1.2f, 24f) &&
                springW.isAtRest(1.2f, 24f) &&
                springH.isAtRest(1.2f, 24f) &&
                springProgress.isAtRest(0.008f, 0.12f)

            if (done) {
                running = false
                onFrameUpdate(
                    State(
                        centerX = springX.target,
                        centerY = springY.target,
                        width = max(16f, springW.target),
                        height = max(16f, springH.target),
                        cornerRadiusRatio = springCorner.target.coerceIn(0f, 0.5f),
                        progress = springProgress.target.coerceIn(0f, 1f),
                        isSettlingToHome = settlingToHome
                    )
                )
                onSettled(settlingToHome)
            } else {
                onFrameUpdate(
                    State(
                        centerX = springX.value,
                        centerY = springY.value,
                        width = currentW,
                        height = currentH,
                        cornerRadiusRatio = springCorner.value.coerceIn(0f, 0.5f),
                        progress = currentProgress,
                        isSettlingToHome = settlingToHome
                    )
                )
                Choreographer.getInstance().postFrameCallback(this)
            }
        }
    }

    /** Initializes direct 1:1 finger tracking state at `ACTION_DOWN`. */
    fun beginDrag(displayWidth: Float, displayHeight: Float) {
        stop()
        screenW = max(1f, displayWidth)
        screenH = max(1f, displayHeight)
        val cx = screenW * 0.5f
        val cy = screenH * 0.5f
        springX.reset(cx)
        springY.reset(cy)
        springW.reset(screenW)
        springH.reset(screenH)
        springCorner.reset(0.03f)
        springProgress.reset(0f)
    }

    /**
     * Computes instantaneous 1:1 finger-tracked card geometry during `ACTION_MOVE`
     * with tactile rubber-banding so the window feels physically attached to the thumb.
     */
    fun updateDrag(deltaX: Float, deltaY: Float): State {
        val upwardPx = max(0f, -deltaY)
        val dragNorm = (upwardPx / (screenH * 0.44f)).coerceIn(0f, 1f)
        // Smooth asymptotic resistance curve: responsive near bottom, gently damped high up
        val easedDrag = 1f - exp(-2.4f * dragNorm)
        val scale = (1f - 0.52f * easedDrag).coerceIn(0.42f, 1f)

        val currentW = screenW * scale
        val currentH = screenH * scale
        val cx = screenW * 0.5f + deltaX * 0.62f
        val cy = screenH * 0.5f + deltaY * 0.58f
        val cornerRatio = (0.04f + 0.08f * easedDrag).coerceIn(0.03f, 0.22f)
        val progress = (dragNorm * 0.52f).coerceIn(0f, 0.55f)

        springX.value = cx
        springY.value = cy
        springW.value = currentW
        springH.value = currentH
        springCorner.value = cornerRatio
        springProgress.value = progress

        return State(
            centerX = cx,
            centerY = cy,
            width = currentW,
            height = currentH,
            cornerRadiusRatio = cornerRatio,
            progress = progress,
            isSettlingToHome = true
        )
    }

    /**
     * Launches the coupled momentum spring morph into [targetCenterX], [targetCenterY],
     * [targetWidth], [targetHeight] with [targetCornerRatio] (matching IconShapeClipper).
     */
    fun animateToHomeTarget(
        velocityX: Float,
        velocityY: Float,
        targetCenterX: Float,
        targetCenterY: Float,
        targetWidth: Float,
        targetHeight: Float,
        targetCornerRatio: Float
    ) {
        settlingToHome = true
        // Preserve real finger momentum while clamping extreme spikes
        springX.velocity = (velocityX * 0.55f).coerceIn(-4200f, 4200f)
        springY.velocity = (velocityY * 0.55f).coerceIn(-5200f, 3200f)
        // Seed shrink velocity proportional to upward flick speed so fast flicks feel snappy
        val flickBoost = (max(0f, -velocityY) / screenH).coerceIn(0f, 3.5f)
        springW.velocity = -screenW * flickBoost * 0.65f
        springH.velocity = -screenH * flickBoost * 0.65f
        springProgress.velocity = min(4.5f, 1.2f + flickBoost * 0.9f)

        springX.target = targetCenterX
        springY.target = targetCenterY
        springW.target = targetWidth
        springH.target = targetHeight
        springCorner.target = targetCornerRatio
        springProgress.target = 1f

        startLoop()
    }

    /** Springs the dragged window cleanly back to full-screen `(0, 0, screenW, screenH)`. */
    fun animateCancelBackToApp(velocityX: Float, velocityY: Float) {
        settlingToHome = false
        springX.velocity = (velocityX * 0.45f).coerceIn(-3000f, 3000f)
        springY.velocity = (velocityY * 0.45f).coerceIn(-3000f, 4000f)
        springW.velocity = 0f
        springH.velocity = 0f
        springProgress.velocity = -1.5f

        springX.target = screenW * 0.5f
        springY.target = screenH * 0.5f
        springW.target = screenW
        springH.target = screenH
        springCorner.target = 0f
        springProgress.target = 0f

        startLoop()
    }

    fun stop() {
        if (running) {
            running = false
            Choreographer.getInstance().removeFrameCallback(frameCallback)
        }
        lastFrameNanos = 0L
    }

    private fun startLoop() {
        lastFrameNanos = 0L
        if (!running) {
            running = true
            Choreographer.getInstance().postFrameCallback(frameCallback)
        }
    }
}

