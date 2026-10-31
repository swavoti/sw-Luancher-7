package co.za.launcher3.swavoti

import android.app.Notification
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.view.KeyEvent
import java.io.ByteArrayOutputStream

class NotificationDotService : NotificationListenerService() {
    companion object {
        var notificationCounts: MutableMap<String, Int> = mutableMapOf()
        var listener: ((Map<String, Int>) -> Unit)? = null
        var mediaListener: ((Map<String, Any?>?) -> Unit)? = null
        var mediaSnapshot: Map<String, Any?>? = null

        private val mainHandler = Handler(Looper.getMainLooper())
        private var activeService: NotificationDotService? = null
        private var localPlayerSnapshot: Map<String, Any?>? = null
        private var legacyBaseSnapshot: Map<String, Any?>? = null
        private var legacyBaseElapsedMs: Long = 0L
        private var globalLegacyReceiverRegistered = false
        private var tickerRunning = false

        private val globalLegacyMusicReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent == null) return
                val title = intent.getStringExtra("track")
                    ?: intent.getStringExtra("title")
                    ?: return
                if (title.isBlank()) return
                val artist = intent.getStringExtra("artist") ?: ""
                val album = intent.getStringExtra("album") ?: ""
                val playing = when {
                    intent.hasExtra("playing") -> intent.getBooleanExtra("playing", false)
                    intent.hasExtra("playstate") -> intent.getBooleanExtra("playstate", false)
                    intent.action?.contains("playbackcomplete") == true -> false
                    else -> true
                }
                val duration = intent.getLongExtra("duration", 0L).coerceAtLeast(0L)
                val position = intent.getLongExtra("position", 0L).coerceAtLeast(0L)
                val senderPkg = intent.`package` ?: intent.getStringExtra("package") ?: ""

                legacyBaseElapsedMs = SystemClock.elapsedRealtime()
                legacyBaseSnapshot = mapOf(
                    "packageName" to senderPkg,
                    "title" to title,
                    "artist" to artist,
                    "album" to album,
                    "albumArt" to null,
                    "appIcon" to null,
                    "isPlaying" to playing,
                    "positionMs" to position,
                    "durationMs" to duration,
                    "playbackSpeed" to if (playing) 1.0 else 0.0,
                    "updatedAtMs" to System.currentTimeMillis(),
                    "isLocalPlayer" to false
                )
                refreshCurrentMedia()
            }
        }

        fun ensureGlobalLegacyReceiver(context: Context) {
            if (globalLegacyReceiverRegistered) return
            val appCtx = context.applicationContext
            try {
                val filter = IntentFilter().apply {
                    addAction("com.android.music.metachanged")
                    addAction("com.android.music.playstatechanged")
                    addAction("com.android.music.playbackcomplete")
                    addAction("com.android.music.queuechanged")
                    addAction("com.htc.music.metachanged")
                    addAction("com.sec.android.app.music.metachanged")
                    addAction("com.miui.player.metachanged")
                    addAction("fm.last.android.metachanged")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    appCtx.registerReceiver(
                        globalLegacyMusicReceiver,
                        filter,
                        Context.RECEIVER_EXPORTED
                    )
                } else {
                    appCtx.registerReceiver(globalLegacyMusicReceiver, filter)
                }
                globalLegacyReceiverRegistered = true
            } catch (t: Throwable) {
                android.util.Log.w("NotificationDotService", "Could not register music receiver", t)
            }
        }

        internal fun resolveLegacySnapshot(): Map<String, Any?>? {
            val base = legacyBaseSnapshot ?: return null
            val playing = (base["isPlaying"] as? Boolean) == true
            val basePos = (base["positionMs"] as? Long) ?: 0L
            val dur = (base["durationMs"] as? Long) ?: 0L
            if (!playing) return base
            val elapsed = (SystemClock.elapsedRealtime() - legacyBaseElapsedMs).coerceAtLeast(0L)
            val livePos = if (dur > 0L) {
                (basePos + elapsed).coerceIn(0L, dur)
            } else {
                (basePos + elapsed).coerceAtLeast(0L)
            }
            return base.toMutableMap().apply {
                this["positionMs"] = livePos
                this["updatedAtMs"] = System.currentTimeMillis()
            }
        }

        private val realtimeTicker = object : Runnable {
            override fun run() {
                val service = activeService
                if (service != null) {
                    service.refreshMedia(forceEmitIfPlaying = true)
                } else if (LocalMusicManager.hasActiveTrack) {
                    val snap = LocalMusicManager.currentSnapshot()
                    localPlayerSnapshot = snap
                    mediaSnapshot = snap
                    mediaListener?.invoke(snap)
                } else {
                    val legacy = resolveLegacySnapshot()
                    if (legacy != null) {
                        mediaSnapshot = legacy
                        mediaListener?.invoke(legacy)
                    }
                }
                val stillPlaying = (mediaSnapshot?.get("isPlaying") as? Boolean) == true
                if (stillPlaying) {
                    mainHandler.postDelayed(this, 1000L)
                } else {
                    tickerRunning = false
                }
            }
        }

        private fun updateTickerState() {
            val playing = (mediaSnapshot?.get("isPlaying") as? Boolean) == true
            if (playing && !tickerRunning) {
                tickerRunning = true
                mainHandler.removeCallbacks(realtimeTicker)
                mainHandler.postDelayed(realtimeTicker, 1000L)
            } else if (!playing && tickerRunning) {
                tickerRunning = false
                mainHandler.removeCallbacks(realtimeTicker)
            }
        }

        fun onLocalPlayerUpdated(snapshot: Map<String, Any?>?) {
            localPlayerSnapshot = snapshot
            val service = activeService
            if (service != null) {
                service.refreshMedia(forceEmitIfPlaying = true)
            } else {
                mediaSnapshot = snapshot
                mainHandler.post {
                    mediaListener?.invoke(snapshot)
                    updateTickerState()
                }
            }
        }

        fun refreshCurrentMedia() {
            val service = activeService
            if (service != null) {
                service.refreshMedia(forceEmitIfPlaying = true)
            } else if (LocalMusicManager.hasActiveTrack) {
                val snap = LocalMusicManager.currentSnapshot()
                localPlayerSnapshot = snap
                mediaSnapshot = snap
                mainHandler.post {
                    mediaListener?.invoke(snap)
                    updateTickerState()
                }
            } else {
                val legacy = resolveLegacySnapshot()
                if (legacy != null) {
                    mediaSnapshot = legacy
                    mainHandler.post {
                        mediaListener?.invoke(legacy)
                        updateTickerState()
                    }
                }
            }
        }

        fun controlMedia(
            action: String,
            positionMs: Long? = null,
            context: Context? = null
        ): Boolean {
            val isCurrentLocal = (mediaSnapshot?.get("isLocalPlayer") as? Boolean) == true
            if (LocalMusicManager.isCurrentlyPlaying ||
                (isCurrentLocal && LocalMusicManager.hasActiveTrack)
            ) {
                val ctx = context ?: activeService
                if (ctx != null && LocalMusicManager.control(ctx, action, positionMs)) {
                    return true
                }
            }

            val service = activeService
            if (service != null) {
                val handled = service.controlExternalMedia(action, positionMs)
                if (handled) return true
            }

            if (LocalMusicManager.hasActiveTrack) {
                val ctx = context ?: activeService
                if (ctx != null && LocalMusicManager.control(ctx, action, positionMs)) {
                    return true
                }
            }

            // Fallback hardware media key dispatch for legacy local music players
            val ctx = context ?: activeService
            if (ctx != null) {
                val audioManager =
                    ctx.getSystemService(Context.AUDIO_SERVICE) as? android.media.AudioManager
                if (audioManager != null) {
                    val keyCode = when (action) {
                        "playPause" -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                        "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
                        "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        else -> null
                    }
                    if (keyCode != null) {
                        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
                        audioManager.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, keyCode))
                        mainHandler.postDelayed({ refreshCurrentMedia() }, 180L)
                        return true
                    }
                }
            }
            return false
        }

        private fun emitMediaSnapshot() {
            val snapshot = mediaSnapshot
            mainHandler.post {
                mediaListener?.invoke(snapshot)
                updateTickerState()
            }
        }
    }

    private var sessionsChangedListener: MediaSessionManager.OnActiveSessionsChangedListener? = null
    private val registeredControllers = mutableMapOf<MediaSession.Token, MediaController>()
    private var fallbackTrackKey: String? = null
    private var fallbackTrackStartElapsedMs: Long = 0L
    private var fallbackTrackBasePosMs: Long = 0L

    private val mediaControllerCallback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            refreshMedia(forceEmitIfPlaying = true)
        }

        override fun onMetadataChanged(metadata: MediaMetadata?) {
            refreshMedia(forceEmitIfPlaying = true)
        }

        override fun onSessionDestroyed() {
            refreshMedia(forceEmitIfPlaying = true)
        }

        override fun onAudioInfoChanged(info: MediaController.PlaybackInfo?) {
            refreshMedia()
        }
    }

    override fun onCreate() {
        super.onCreate()
        activeService = this
        ensureGlobalLegacyReceiver(this)
    }

    override fun onListenerConnected() {
        try {
            super.onListenerConnected()
            activeService = this
            registerActiveSessionsObserver()
            ensureGlobalLegacyReceiver(this)
            updateNotifications()
            refreshMedia(forceEmitIfPlaying = true)
        } catch (e: Exception) {
            android.util.Log.w("NotificationDotService", "Listener connection failed", e)
        }
    }

    private fun registerActiveSessionsObserver() {
        try {
            val manager = getSystemService(MEDIA_SESSION_SERVICE) as? MediaSessionManager ?: return
            val component = ComponentName(this, NotificationDotService::class.java)
            sessionsChangedListener?.let {
                try {
                    manager.removeOnActiveSessionsChangedListener(it)
                } catch (_: Throwable) {}
            }
            val listenerObj = MediaSessionManager.OnActiveSessionsChangedListener { controllers ->
                syncControllerCallbacks(controllers.orEmpty())
                refreshMedia(forceEmitIfPlaying = true)
            }
            sessionsChangedListener = listenerObj
            manager.addOnActiveSessionsChangedListener(
                listenerObj,
                component,
                mainHandler
            )
            syncControllerCallbacks(manager.getActiveSessions(component))
        } catch (t: Throwable) {
            android.util.Log.w("NotificationDotService", "ActiveSessions listener failed", t)
        }
    }

    private fun unregisterObservers() {
        try {
            val manager = getSystemService(MEDIA_SESSION_SERVICE) as? MediaSessionManager
            sessionsChangedListener?.let { manager?.removeOnActiveSessionsChangedListener(it) }
        } catch (_: Throwable) {}
        sessionsChangedListener = null

        for (controller in registeredControllers.values) {
            try {
                controller.unregisterCallback(mediaControllerCallback)
            } catch (_: Throwable) {}
        }
        registeredControllers.clear()
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
        unregisterObservers()
        mediaSnapshot = localPlayerSnapshot
        emitMediaSnapshot()
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        unregisterObservers()
        if (activeService === this) activeService = null
        mediaSnapshot = localPlayerSnapshot
        emitMediaSnapshot()
        super.onDestroy()
    }

    fun controlExternalMedia(action: String, positionMs: Long? = null): Boolean {
        return try {
            val controller = activeExternalMediaController() ?: return false
            val controls = controller.transportControls
            when (action) {
                "playPause" -> {
                    val state = controller.playbackState?.state
                    if (state == PlaybackState.STATE_PLAYING ||
                        state == PlaybackState.STATE_BUFFERING
                    ) {
                        controls.pause()
                    } else {
                        controls.play()
                    }
                }
                "play" -> controls.play()
                "pause" -> controls.pause()
                "previous" -> controls.skipToPrevious()
                "next" -> controls.skipToNext()
                "seek" -> controls.seekTo(positionMs ?: 0L)
                else -> return false
            }
            mainHandler.postDelayed({ refreshMedia(forceEmitIfPlaying = true) }, 120L)
            true
        } catch (e: Exception) {
            android.util.Log.w("NotificationDotService", "Media action failed", e)
            false
        }
    }

    private fun updateNotifications() {
        try {
            val sbns = getActiveNotifications()
            val counts: MutableMap<String, Int> = mutableMapOf()
            if (sbns != null) {
                for (sbn in sbns) {
                    if (sbn == null) continue
                    val pkg: String = sbn.packageName ?: continue
                    counts[pkg] = counts.getOrDefault(pkg, 0) + 1
                }
            }
            notificationCounts = counts
            listener?.invoke(counts)
        } catch (e: Exception) {
            android.util.Log.w("NotificationDotService", "Could not read active notifications", e)
        }
    }

    private fun collectAllControllers(): List<MediaController> {
        val controllers = mutableListOf<MediaController>()
        try {
            val manager = getSystemService(MEDIA_SESSION_SERVICE) as? MediaSessionManager
            if (manager != null) {
                val component = ComponentName(this, NotificationDotService::class.java)
                controllers.addAll(manager.getActiveSessions(component))
            }
        } catch (_: Throwable) {}

        try {
            getActiveNotifications().orEmpty().forEach { sbn ->
                val token = mediaSessionToken(sbn.notification)
                if (token != null && controllers.none { it.sessionToken == token }) {
                    controllers.add(MediaController(this, token))
                }
            }
        } catch (_: Throwable) {}

        syncControllerCallbacks(controllers)
        return controllers
    }

    private fun syncControllerCallbacks(controllers: List<MediaController>) {
        val activeTokens = controllers.map { it.sessionToken }.toSet()
        val iterator = registeredControllers.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            if (entry.key !in activeTokens) {
                try {
                    entry.value.unregisterCallback(mediaControllerCallback)
                } catch (_: Throwable) {}
                iterator.remove()
            }
        }
        for (controller in controllers) {
            if (!registeredControllers.containsKey(controller.sessionToken)) {
                try {
                    controller.registerCallback(mediaControllerCallback, mainHandler)
                    registeredControllers[controller.sessionToken] = controller
                } catch (_: Throwable) {}
            }
        }
    }

    private fun activeExternalMediaController(): MediaController? {
        val selfPkg = packageName
        val controllers = collectAllControllers().filter { it.packageName != selfPkg }
        return controllers
            .filter { controller ->
                val state = controller.playbackState?.state
                controller.metadata != null ||
                    state == PlaybackState.STATE_PLAYING ||
                    state == PlaybackState.STATE_BUFFERING ||
                    state == PlaybackState.STATE_PAUSED ||
                    activeMediaNotification(controller) != null
            }
            .sortedWith(
                compareByDescending<MediaController> {
                    val s = it.playbackState?.state
                    s == PlaybackState.STATE_PLAYING || s == PlaybackState.STATE_BUFFERING
                }.thenByDescending {
                    it.playbackState?.lastPositionUpdateTime ?: 0L
                }
            )
            .firstOrNull()
    }

    fun refreshMedia(forceEmitIfPlaying: Boolean = false) {
        val data: Map<String, Any?>? = try {
            // 1. If our built-in LocalMusicManager is actively playing, prioritize it immediately
            if (LocalMusicManager.isCurrentlyPlaying) {
                val localSnap = LocalMusicManager.currentSnapshot(this)
                localPlayerSnapshot = localSnap
                localSnap
            } else {
                val controller = activeExternalMediaController()
                val externalPlaying = controller?.playbackState?.let {
                    it.state == PlaybackState.STATE_PLAYING ||
                        it.state == PlaybackState.STATE_BUFFERING
                } == true
                val legacySnap = resolveLegacySnapshot()
                val legacyPlaying = (legacySnap?.get("isPlaying") as? Boolean) == true

                when {
                    externalPlaying && controller != null -> buildControllerSnapshot(controller)
                    legacyPlaying && legacySnap != null -> legacySnap
                    LocalMusicManager.hasActiveTrack -> {
                        val localSnap = LocalMusicManager.currentSnapshot(this)
                        localPlayerSnapshot = localSnap
                        localSnap
                    }
                    controller != null -> buildControllerSnapshot(controller)
                    legacySnap != null -> legacySnap
                    else -> null
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("NotificationDotService", "Could not read media session", e)
            localPlayerSnapshot ?: resolveLegacySnapshot()
        }

        val previous = mediaSnapshot
        val changed = forceEmitIfPlaying || !snapshotsEquivalent(previous, data)
        mediaSnapshot = data
        if (changed) {
            mainHandler.post {
                mediaListener?.invoke(data)
            }
        }
        updateTickerState()
    }

    private fun snapshotsEquivalent(a: Map<String, Any?>?, b: Map<String, Any?>?): Boolean {
        if (a === b) return true
        if (a == null || b == null) return false
        return a["packageName"] == b["packageName"] &&
            a["title"] == b["title"] &&
            a["artist"] == b["artist"] &&
            a["isPlaying"] == b["isPlaying"] &&
            a["positionMs"] == b["positionMs"] &&
            a["durationMs"] == b["durationMs"] &&
            a["albumArt"] === b["albumArt"]
    }

    private fun buildControllerSnapshot(controller: MediaController): Map<String, Any?> {
        val metadata = controller.metadata
        val playback = controller.playbackState
        val state = playback?.state
        val isPlaying = state == PlaybackState.STATE_PLAYING ||
            state == PlaybackState.STATE_BUFFERING
        val pkgName = controller.packageName
        val notification = activeMediaNotification(controller)
        val notificationExtras = notification?.extras
        val description = metadata?.description

        val title = listOf(
            metadata?.getText(MediaMetadata.METADATA_KEY_TITLE)?.toString(),
            metadata?.getText(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)?.toString(),
            description?.title?.toString(),
            notificationExtras?.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            metadata?.getText(MediaMetadata.METADATA_KEY_ALBUM)?.toString(),
            notificationExtras?.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            notificationExtras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
        ).firstOrNull { !it.isNullOrBlank() }
            ?: try {
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(pkgName, 0)
                ).toString()
            } catch (_: Exception) {
                pkgName
            }

        val artist = listOf(
            metadata?.getText(MediaMetadata.METADATA_KEY_ARTIST)?.toString(),
            metadata?.getText(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)?.toString(),
            metadata?.getText(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)?.toString(),
            description?.subtitle?.toString(),
            notificationExtras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()
                ?.takeIf { it != title },
            notificationExtras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
        ).firstOrNull { !it.isNullOrBlank() } ?: ""

        val duration = (metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L)
            .coerceAtLeast(0L)

        val nowElapsed = SystemClock.elapsedRealtime()
        val rawReported = playback?.position ?: -1L
        val safeReported = if (rawReported >= 0L) rawReported else 0L
        val speed = if (isPlaying) {
            val s = playback?.playbackSpeed ?: 1.0f
            if (s > 0f) s else 1.0f
        } else {
            0f
        }

        val trackKey = "$pkgName|$title|$artist|$duration"
        if (trackKey != fallbackTrackKey) {
            fallbackTrackKey = trackKey
            fallbackTrackStartElapsedMs = nowElapsed
            fallbackTrackBasePosMs = safeReported
        } else if (!isPlaying) {
            fallbackTrackStartElapsedMs = nowElapsed
            fallbackTrackBasePosMs = safeReported
        }

        val hasValidUpdateTime = playback != null &&
            playback.lastPositionUpdateTime > 0L &&
            playback.lastPositionUpdateTime <= nowElapsed + 2000L

        val rawPosition = if (isPlaying) {
            if (hasValidUpdateTime && playback != null) {
                val elapsed = (nowElapsed - playback.lastPositionUpdateTime).coerceAtLeast(0L)
                safeReported + (elapsed * speed).toLong()
            } else {
                val elapsed = (nowElapsed - fallbackTrackStartElapsedMs).coerceAtLeast(0L)
                fallbackTrackBasePosMs + (elapsed * speed).toLong()
            }
        } else {
            safeReported
        }

        val position = if (duration > 0L) {
            rawPosition.coerceIn(0L, duration)
        } else {
            rawPosition.coerceAtLeast(0L)
        }

        val previous = mediaSnapshot
        val samePackage = previous?.get("packageName") == pkgName
        val sameTrack = samePackage &&
            previous?.get("title") == title &&
            previous?.get("artist") == artist

        val appIcon = if (samePackage && previous?.get("appIcon") != null) {
            previous.get("appIcon")
        } else {
            try {
                val drawable = packageManager.getApplicationIcon(pkgName)
                val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, canvas.width, canvas.height)
                drawable.draw(canvas)
                val bytes = bitmapToBytes(bitmap, 80)
                bitmap.recycle()
                bytes
            } catch (_: Exception) {
                null
            }
        }

        val albumArt = previous?.get("albumArt").takeIf { sameTrack && it != null }
            ?: bitmapToBytes(
                metadata?.getBitmap(MediaMetadata.METADATA_KEY_ART)
                    ?: metadata?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
                    ?: description?.iconBitmap
                    ?: notificationArtwork(notification),
                220
            )

        return mapOf(
            "packageName" to pkgName,
            "title" to title,
            "artist" to artist,
            "albumArt" to albumArt,
            "appIcon" to appIcon,
            "isPlaying" to isPlaying,
            "positionMs" to position,
            "durationMs" to duration,
            "playbackSpeed" to speed.toDouble(),
            "updatedAtMs" to System.currentTimeMillis(),
            "isLocalPlayer" to false
        )
    }

    private fun activeMediaNotification(controller: MediaController): Notification? {
        return try {
            getActiveNotifications()
                .orEmpty()
                .asSequence()
                .filter { it.packageName == controller.packageName }
                .map { it.notification }
                .firstOrNull { notification ->
                    val token = mediaSessionToken(notification)
                    val template = notification.extras?.getString(Notification.EXTRA_TEMPLATE)
                    token == controller.sessionToken ||
                        token != null ||
                        notification.category == Notification.CATEGORY_TRANSPORT ||
                        template?.contains("MediaStyle", ignoreCase = true) == true
                }
        } catch (_: Throwable) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun mediaSessionToken(notification: Notification): MediaSession.Token? {
        return notification.extras
            ?.getParcelable(Notification.EXTRA_MEDIA_SESSION) as? MediaSession.Token
    }

    @Suppress("DEPRECATION")
    private fun notificationArtwork(notification: Notification?): Bitmap? {
        val extras = notification?.extras ?: return null
        return extras.getParcelable(Notification.EXTRA_LARGE_ICON) as? Bitmap
            ?: extras.getParcelable(Notification.EXTRA_LARGE_ICON_BIG) as? Bitmap
    }

    private fun bitmapToBytes(source: Bitmap?, maxSize: Int): ByteArray? {
        if (source == null || source.isRecycled || source.width <= 0 || source.height <= 0) {
            return null
        }
        return try {
            val scale = minOf(1f, maxSize.toFloat() / maxOf(source.width, source.height).toFloat())
            val bitmap = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    source,
                    (source.width * scale).toInt().coerceAtLeast(1),
                    (source.height * scale).toInt().coerceAtLeast(1),
                    true
                )
            } else {
                source
            }
            val bytes = ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 82, output)
                output.toByteArray()
            }
            if (bitmap !== source) bitmap.recycle()
            bytes
        } catch (_: Throwable) {
            null
        }
    }
}
