package co.za.launcher3.swavoti

import android.content.ComponentName
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.io.ByteArrayOutputStream

class NotificationDotService : NotificationListenerService() {
    companion object {
        var notificationCounts: MutableMap<String, Int> = mutableMapOf()
        var listener: ((Map<String, Int>) -> Unit)? = null
        var mediaListener: ((Map<String, Any?>?) -> Unit)? = null
        var mediaSnapshot: Map<String, Any?>? = null
        private var activeService: NotificationDotService? = null

        fun refreshCurrentMedia() {
            activeService?.refreshMedia()
        }

        fun controlMedia(action: String, positionMs: Long? = null): Boolean {
            return try {
                val controller = activeService?.activeMediaController() ?: return false
                val controls = controller.transportControls
                when (action) {
                    "playPause" -> {
                        if (controller.playbackState?.state == PlaybackState.STATE_PLAYING) {
                            controls.pause()
                        } else {
                            controls.play()
                        }
                    }

                    "previous" -> controls.skipToPrevious()
                    "next" -> controls.skipToNext()
                    "seek" -> controls.seekTo(positionMs ?: 0L)
                    else -> return false
                }
                activeService?.refreshMedia()
                true
            } catch (e: Exception) {
                android.util.Log.w("NotificationDotService", "Media action failed", e)
                false
            }
        }

        private fun emitMediaSnapshot() {
            val snapshot = mediaSnapshot
            Handler(Looper.getMainLooper()).post {
                mediaListener?.invoke(snapshot)
            }
        }
    }

    private val mediaHandler = Handler(Looper.getMainLooper())
    private val mediaRefreshTask = object : Runnable {
        override fun run() {
            refreshMedia()
            mediaHandler.postDelayed(this, 1000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeService = this
    }

    override fun onListenerConnected() {
        try {
            super.onListenerConnected()
            updateNotifications()
            mediaHandler.removeCallbacks(mediaRefreshTask)
            mediaHandler.post(mediaRefreshTask)
        } catch (e: Exception) {
            android.util.Log.w("NotificationDotService", "Listener connection failed", e)
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        updateNotifications()
        refreshMedia()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        updateNotifications()
        refreshMedia()
    }

    override fun onListenerDisconnected() {
        mediaHandler.removeCallbacks(mediaRefreshTask)
        mediaSnapshot = null
        emitMediaSnapshot()
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        mediaHandler.removeCallbacks(mediaRefreshTask)
        mediaSnapshot = null
        emitMediaSnapshot()
        if (activeService === this) activeService = null
        super.onDestroy()
    }

    private fun updateNotifications() {
        try {
            val sbns = getActiveNotifications()
            val counts: MutableMap<String, Int> = mutableMapOf()
            if (sbns != null) {
                for (sbn in sbns) {
                    if (sbn == null) continue
                    val pkg: String = sbn?.packageName ?: continue
                    val current: Int = counts.getOrDefault(pkg, 0)
                    counts[pkg] = current + 1
                }
            }
            notificationCounts = counts
            listener?.invoke(counts)
        } catch (e: Exception) {
            android.util.Log.w("NotificationDotService", "Could not read active notifications", e)
        }
    }

    private fun activeMediaController(): MediaController? {
        val manager = getSystemService(MEDIA_SESSION_SERVICE) as MediaSessionManager
        val component = ComponentName(this, NotificationDotService::class.java)
        return manager.getActiveSessions(component)
            .filter { it.metadata != null }
            .sortedByDescending {
                it.playbackState?.state == PlaybackState.STATE_PLAYING
            }
            .firstOrNull()
    }

    fun refreshMedia() {
        val data = try {
            val controller = activeMediaController()
            val metadata = controller?.metadata
            if (controller == null || metadata == null) {
                null
            } else {
                val playback = controller.playbackState
                val state = playback?.state
                val reportedPosition = playback?.position ?: 0L
                val position = if (state == PlaybackState.STATE_PLAYING && playback != null) {
                    val elapsed = (SystemClock.elapsedRealtime() - playback.lastPositionUpdateTime)
                        .coerceAtLeast(0L)
                    reportedPosition + (elapsed * playback.playbackSpeed).toLong()
                } else {
                    reportedPosition
                }
                val packageName = controller.packageName
                val title = metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
                val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST)
                    ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
                    ?: ""
                val previous = mediaSnapshot
                val samePackage = previous?.get("packageName") == packageName
                val sameTrack = samePackage &&
                    previous?.get("title") == title &&
                    previous?.get("artist") == artist
                val appIcon = if (samePackage) {
                    previous?.get("appIcon")
                } else {
                    try {
                        val drawable = packageManager.getApplicationIcon(packageName)
                        val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                        val canvas = android.graphics.Canvas(bitmap)
                        drawable.setBounds(0, 0, canvas.width, canvas.height)
                        drawable.draw(canvas)
                        bitmapToBytes(bitmap, 80)
                    } catch (_: Exception) {
                        null
                    }
                }
                mapOf(
                    "packageName" to packageName,
                    "title" to title,
                    "artist" to artist,
                    "albumArt" to if (sameTrack) {
                        previous?.get("albumArt")
                    } else {
                        bitmapToBytes(
                            metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
                                ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART),
                            82
                        )
                    },
                    "appIcon" to appIcon,
                    "isPlaying" to (state == PlaybackState.STATE_PLAYING),
                    "positionMs" to position,
                    "durationMs" to (metadata.getLong(MediaMetadata.METADATA_KEY_DURATION)),
                )
            }
        } catch (e: Exception) {
            android.util.Log.w("NotificationDotService", "Could not read media session", e)
            null
        }
        val changed = data != mediaSnapshot
        mediaSnapshot = data
        if (changed) mediaListener?.invoke(data)
    }

    private fun bitmapToBytes(source: Bitmap?, maxSize: Int): ByteArray? {
        if (source == null) return null
        val scale = minOf(1f, maxSize.toFloat() / maxOf(source.width, source.height))
        val bitmap = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                source,
                (source.width * scale).toInt().coerceAtLeast(1),
                (source.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        } else {
            source
        }
        return ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output)
            output.toByteArray()
        }
    }
}
