package co.za.launcher3.swavoti

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.util.LruCache
import android.util.Size
import java.io.ByteArrayOutputStream

object LocalMusicManager {

    data class LocalTrack(
        val id: Long,
        val title: String,
        val artist: String,
        val album: String,
        val durationMs: Long,
        val sizeBytes: Long,
        val format: String,
        val contentUri: String,
        val albumId: Long,
        val dateAdded: Long
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id,
            "title" to title,
            "artist" to artist,
            "album" to album,
            "durationMs" to durationMs,
            "sizeBytes" to sizeBytes,
            "format" to format,
            "contentUri" to contentUri,
            "albumId" to albumId,
            "dateAdded" to dateAdded
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val artCache = object : LruCache<Long, ByteArray>(2400 * 1024) {
        override fun sizeOf(key: Long, value: ByteArray): Int = value.size
    }

    @Volatile
    private var cachedTracks: MutableList<LocalTrack> = mutableListOf()

    private var mediaPlayer: MediaPlayer? = null
    private var mediaSession: MediaSession? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var appContext: Context? = null

    private var queue: MutableList<LocalTrack> = mutableListOf()
    private var currentIndex: Int = -1
    private var isPrepared: Boolean = false

    val hasActiveTrack: Boolean
        get() = currentIndex in queue.indices && mediaPlayer != null

    val isCurrentlyPlaying: Boolean
        get() = try {
            isPrepared && mediaPlayer?.isPlaying == true
        } catch (_: Throwable) {
            false
        }

    fun requiredPermission(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    fun hasAudioPermission(context: Context): Boolean {
        val perm = requiredPermission()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    fun queryLocalTracks(context: Context): List<Map<String, Any?>> {
        appContext = context.applicationContext
        if (!hasAudioPermission(context)) {
            return emptyList()
        }
        val list = mutableListOf<LocalTrack>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DATE_ADDED
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.DATE_ADDED} DESC"

        try {
            context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                null,
                sortOrder
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val durCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
                val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val duration = cursor.getLong(durCol)
                    if (duration in 1..2500) continue

                    val displayName = cursor.getString(nameCol) ?: ""
                    val rawTitle = cursor.getString(titleCol)?.trim()
                    val title = if (!rawTitle.isNullOrEmpty() && rawTitle != "<unknown>") {
                        rawTitle
                    } else {
                        displayName.substringBeforeLast('.').ifBlank { "Track $id" }
                    }

                    val rawArtist = cursor.getString(artistCol)?.trim()
                    val artist = if (!rawArtist.isNullOrEmpty() && rawArtist != "<unknown>") {
                        rawArtist
                    } else {
                        "Local Audio"
                    }

                    val rawAlbum = cursor.getString(albumCol)?.trim()
                    val album = if (!rawAlbum.isNullOrEmpty() && rawAlbum != "<unknown>") {
                        rawAlbum
                    } else {
                        ""
                    }

                    val sizeBytes = cursor.getLong(sizeCol)
                    val mime = cursor.getString(mimeCol) ?: ""
                    val ext = displayName.substringAfterLast('.', "").uppercase()
                    val format = when {
                        ext.isNotEmpty() && ext.length <= 5 -> ext
                        mime.contains("flac", ignoreCase = true) -> "FLAC"
                        mime.contains("wav", ignoreCase = true) -> "WAV"
                        mime.contains("mp4", ignoreCase = true) ||
                            mime.contains("m4a", ignoreCase = true) -> "M4A"
                        mime.contains("ogg", ignoreCase = true) -> "OGG"
                        else -> "MP3"
                    }

                    val contentUri = ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        id
                    ).toString()

                    val albumId = cursor.getLong(albumIdCol)
                    val dateAdded = cursor.getLong(dateCol)

                    list.add(
                        LocalTrack(
                            id = id,
                            title = title,
                            artist = artist,
                            album = album,
                            durationMs = duration.coerceAtLeast(0L),
                            sizeBytes = sizeBytes.coerceAtLeast(0L),
                            format = format,
                            contentUri = contentUri,
                            albumId = albumId,
                            dateAdded = dateAdded
                        )
                    )
                }
            }
        } catch (t: Throwable) {
            android.util.Log.w("LocalMusicManager", "Failed to query MediaStore audio", t)
        }

        cachedTracks = list
        return list.map { it.toMap() }
    }

    fun loadAlbumArtBytes(context: Context, albumId: Long, trackId: Long): ByteArray? {
        val cacheKey = if (albumId > 0L) albumId else -trackId
        if (cacheKey != 0L) {
            artCache.get(cacheKey)?.let { return it }
        }

        var bitmap: Bitmap? = null
        val resolver = context.contentResolver

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (albumId > 0L) {
                try {
                    val albumUri = ContentUris.withAppendedId(
                        MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI,
                        albumId
                    )
                    bitmap = resolver.loadThumbnail(albumUri, Size(160, 160), null)
                } catch (_: Throwable) {}
            }
            if (bitmap == null && trackId > 0L) {
                try {
                    val trackUri = ContentUris.withAppendedId(
                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        trackId
                    )
                    bitmap = resolver.loadThumbnail(trackUri, Size(160, 160), null)
                } catch (_: Throwable) {}
            }
        }

        if (bitmap == null && albumId > 0L) {
            try {
                val artUri = ContentUris.withAppendedId(
                    Uri.parse("content://media/external/audio/albumart"),
                    albumId
                )
                resolver.openInputStream(artUri)?.use { stream ->
                    bitmap = BitmapFactory.decodeStream(stream)
                }
            } catch (_: Throwable) {}
        }

        if (bitmap == null && trackId > 0L) {
            val retriever = MediaMetadataRetriever()
            try {
                val trackUri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    trackId
                )
                retriever.setDataSource(context, trackUri)
                val embedded = retriever.embeddedPicture
                if (embedded != null) {
                    bitmap = BitmapFactory.decodeByteArray(embedded, 0, embedded.size)
                }
            } catch (_: Throwable) {
            } finally {
                try {
                    retriever.release()
                } catch (_: Throwable) {}
            }
        }

        val bmp = bitmap ?: return null
        return try {
            val maxSide = 160
            val scale = minOf(1f, maxSide.toFloat() / maxOf(bmp.width, bmp.height).toFloat())
            val scaled = if (scale < 1f) {
                Bitmap.createScaledBitmap(
                    bmp,
                    (bmp.width * scale).toInt().coerceAtLeast(1),
                    (bmp.height * scale).toInt().coerceAtLeast(1),
                    true
                )
            } else {
                bmp
            }
            val bytes = ByteArrayOutputStream().use { out ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 82, out)
                out.toByteArray()
            }
            if (scaled !== bmp) scaled.recycle()
            if (cacheKey != 0L) {
                artCache.put(cacheKey, bytes)
            }
            bytes
        } catch (_: Throwable) {
            null
        }
    }

    private fun ensureSession(context: Context): MediaSession {
        mediaSession?.let { return it }
        val appCtx = context.applicationContext
        appContext = appCtx
        val session = MediaSession(appCtx, "SwavotiLocalPlayer")
        session.setCallback(object : MediaSession.Callback() {
            override fun onPlay() {
                control(appCtx, "play", null)
            }

            override fun onPause() {
                control(appCtx, "pause", null)
            }

            override fun onSkipToNext() {
                control(appCtx, "next", null)
            }

            override fun onSkipToPrevious() {
                control(appCtx, "previous", null)
            }

            override fun onSeekTo(pos: Long) {
                control(appCtx, "seek", pos)
            }
        })
        session.isActive = true
        mediaSession = session
        return session
    }

    private fun requestAudioFocus(context: Context) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val listener = AudioManager.OnAudioFocusChangeListener { change ->
            when (change) {
                AudioManager.AUDIOFOCUS_LOSS,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                    if (isCurrentlyPlaying) {
                        control(context, "pause", null)
                    }
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener(listener)
                .build()
            audioFocusRequest = req
            audioManager.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                listener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN
            )
        }
    }

    fun playTrack(context: Context, trackId: Long, queueIds: List<Long>? = null): Boolean {
        val appCtx = context.applicationContext
        appContext = appCtx
        if (cachedTracks.isEmpty()) {
            queryLocalTracks(appCtx)
        }
        val tracksById = cachedTracks.associateBy { it.id }
        val desiredQueue = if (!queueIds.isNullOrEmpty()) {
            queueIds.mapNotNull { tracksById[it] }.toMutableList()
        } else {
            cachedTracks.toMutableList()
        }
        if (desiredQueue.isEmpty()) return false

        val idx = desiredQueue.indexOfFirst { it.id == trackId }
        if (idx == -1) return false

        queue = desiredQueue
        currentIndex = idx
        return startCurrentTrack(appCtx)
    }

    fun queueTrackNext(trackId: Long): Boolean {
        val track = cachedTracks.firstOrNull { it.id == trackId } ?: return false
        if (queue.isEmpty() || currentIndex !in queue.indices) {
            val ctx = appContext ?: return false
            return playTrack(ctx, trackId, null)
        }
        val existingIdx = queue.indexOfFirst { it.id == trackId }
        if (existingIdx != -1 && existingIdx != currentIndex) {
            queue.removeAt(existingIdx)
            if (existingIdx < currentIndex) {
                currentIndex--
            }
        }
        val insertIndex = (currentIndex + 1).coerceIn(0, queue.size)
        queue.add(insertIndex, track)
        return true
    }

    private fun startCurrentTrack(context: Context): Boolean {
        val track = queue.getOrNull(currentIndex) ?: return false
        ensureSession(context)
        requestAudioFocus(context)

        try {
            mediaPlayer?.reset()
            mediaPlayer?.release()
        } catch (_: Throwable) {}
        isPrepared = false

        return try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            mp.setDataSource(context, Uri.parse(track.contentUri))
            mp.setOnPreparedListener { player ->
                isPrepared = true
                player.start()
                syncSessionAndEmit(context)
            }
            mp.setOnCompletionListener {
                if (queue.isNotEmpty()) {
                    currentIndex = (currentIndex + 1) % queue.size
                    startCurrentTrack(context)
                } else {
                    isPrepared = false
                    syncSessionAndEmit(context)
                }
            }
            mp.setOnErrorListener { _, _, _ ->
                isPrepared = false
                syncSessionAndEmit(context)
                true
            }
            mediaPlayer = mp
            mp.prepareAsync()
            syncSessionAndEmit(context, forcePlaying = true)
            true
        } catch (t: Throwable) {
            android.util.Log.w("LocalMusicManager", "Failed to play local track", t)
            false
        }
    }

    fun control(context: Context, action: String, positionMs: Long?): Boolean {
        val player = mediaPlayer ?: return false
        val appCtx = context.applicationContext
        return try {
            when (action) {
                "playPause" -> {
                    if (isPrepared) {
                        if (player.isPlaying) {
                            player.pause()
                        } else {
                            requestAudioFocus(appCtx)
                            player.start()
                        }
                    }
                }
                "play" -> {
                    if (isPrepared && !player.isPlaying) {
                        requestAudioFocus(appCtx)
                        player.start()
                    }
                }
                "pause" -> {
                    if (isPrepared && player.isPlaying) {
                        player.pause()
                    }
                }
                "next" -> {
                    if (queue.isNotEmpty()) {
                        currentIndex = (currentIndex + 1) % queue.size
                        return startCurrentTrack(appCtx)
                    }
                }
                "previous" -> {
                    if (queue.isNotEmpty()) {
                        val pos = if (isPrepared) player.currentPosition else 0
                        if (pos > 3500) {
                            player.seekTo(0)
                        } else {
                            currentIndex = if (currentIndex - 1 < 0) queue.lastIndex else currentIndex - 1
                            return startCurrentTrack(appCtx)
                        }
                    }
                }
                "seek" -> {
                    if (isPrepared && positionMs != null) {
                        player.seekTo(positionMs.toInt().coerceAtLeast(0))
                    }
                }
                else -> return false
            }
            syncSessionAndEmit(appCtx)
            true
        } catch (t: Throwable) {
            android.util.Log.w("LocalMusicManager", "Local control failed: $action", t)
            false
        }
    }

    fun currentSnapshot(context: Context? = appContext): Map<String, Any?>? {
        val track = queue.getOrNull(currentIndex) ?: return null
        val player = mediaPlayer ?: return null
        val playing = try {
            isPrepared && player.isPlaying
        } catch (_: Throwable) {
            false
        }
        val pos = try {
            if (isPrepared) player.currentPosition.toLong().coerceAtLeast(0L) else 0L
        } catch (_: Throwable) {
            0L
        }
        val dur = try {
            val mpDur = if (isPrepared) player.duration.toLong() else 0L
            if (mpDur > 0L) mpDur else track.durationMs
        } catch (_: Throwable) {
            track.durationMs
        }
        val art = if (context != null) {
            artCache.get(if (track.albumId > 0L) track.albumId else -track.id)
                ?: loadAlbumArtBytes(context, track.albumId, track.id)
        } else {
            artCache.get(if (track.albumId > 0L) track.albumId else -track.id)
        }

        return mapOf(
            "packageName" to (context?.packageName ?: "co.za.launcher3.swavoti"),
            "title" to track.title,
            "artist" to track.artist,
            "album" to track.album,
            "albumArt" to art,
            "appIcon" to null,
            "isPlaying" to playing,
            "positionMs" to pos,
            "durationMs" to dur,
            "playbackSpeed" to if (playing) 1.0 else 0.0,
            "updatedAtMs" to System.currentTimeMillis(),
            "isLocalPlayer" to true,
            "localTrackId" to track.id
        )
    }

    private fun syncSessionAndEmit(context: Context, forcePlaying: Boolean = false) {
        val track = queue.getOrNull(currentIndex) ?: return
        val session = ensureSession(context)
        val snap = currentSnapshot(context) ?: return
        val playing = forcePlaying || (snap["isPlaying"] as? Boolean == true)
        val pos = (snap["positionMs"] as? Long) ?: 0L
        val dur = (snap["durationMs"] as? Long) ?: track.durationMs

        try {
            val metaBuilder = MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, track.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, track.artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, track.album)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, dur)

            val artBytes = snap["albumArt"] as? ByteArray
            if (artBytes != null) {
                BitmapFactory.decodeByteArray(artBytes, 0, artBytes.size)?.let { bmp ->
                    metaBuilder.putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, bmp)
                }
            }
            session.setMetadata(metaBuilder.build())

            val stateBuilder = PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or
                        PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or
                        PlaybackState.ACTION_SKIP_TO_NEXT or
                        PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                        PlaybackState.ACTION_SEEK_TO
                )
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    pos,
                    if (playing) 1.0f else 0.0f,
                    SystemClock.elapsedRealtime()
                )
            session.setPlaybackState(stateBuilder.build())
        } catch (_: Throwable) {}

        val emitted = snap.toMutableMap().apply {
            this["isPlaying"] = playing
            this["playbackSpeed"] = if (playing) 1.0 else 0.0
        }
        mainHandler.post {
            NotificationDotService.onLocalPlayerUpdated(emitted)
        }
    }

    fun onTrackDeletedFromDevice(trackId: Long) {
        cachedTracks.removeAll { it.id == trackId }
        val idx = queue.indexOfFirst { it.id == trackId }
        if (idx != -1) {
            val wasCurrent = idx == currentIndex
            queue.removeAt(idx)
            if (wasCurrent) {
                val ctx = appContext
                if (queue.isEmpty() || ctx == null) {
                    try {
                        mediaPlayer?.stop()
                        mediaPlayer?.release()
                    } catch (_: Throwable) {}
                    mediaPlayer = null
                    isPrepared = false
                    currentIndex = -1
                    mainHandler.post {
                        NotificationDotService.onLocalPlayerUpdated(null)
                    }
                } else {
                    currentIndex = idx % queue.size
                    startCurrentTrack(ctx)
                }
            } else if (idx < currentIndex) {
                currentIndex--
            }
        }
    }

    fun shareTrack(activity: Activity, contentUriString: String, title: String): Boolean {
        return try {
            val uri = Uri.parse(contentUriString)
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = "audio/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, title)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(sendIntent, "Share $title").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(chooser)
            true
        } catch (t: Throwable) {
            android.util.Log.w("LocalMusicManager", "Failed to share track", t)
            false
        }
    }
}

