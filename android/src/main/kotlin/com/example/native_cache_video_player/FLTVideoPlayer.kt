package com.example.native_cache_video_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry
import java.util.HashMap
import java.util.concurrent.TimeUnit
import androidx.media3.common.C
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl

/**
 * A wrapper around Media3's ExoPlayer with native caching support.
 */
class FLTVideoPlayer(
    private val context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: TextureRegistry.SurfaceProducer,
    private val dataSource: String,
    private val formatHint: String?,
    private val httpHeaders: Map<String, String>
) {
    private var exoPlayer: ExoPlayer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var surface: Surface? = null
    private var isInitialized = false
    private var captionOffset: Long = 0L

    // Retry logic
    private var retryCount = 0
    private val maxRetries = 3
    private val retryHandler = Handler(Looper.getMainLooper())
    private var pendingRetry: Runnable? = null

    private fun logInfo(message: String) {
        println("NCVP: $message")
    }

    init {
        setupEventChannel()
        initializePlayer()
    }

    fun isPlaying(): Boolean {
        return exoPlayer?.isPlaying ?: false
    }

    private fun setupEventChannel() {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun initializePlayer() {
        try {
            // Memory Optimization: Custom LoadControl with lower buffer sizes
            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    2000,      // min buffer ms
                    5000,      // max buffer ms
                    1000,      // buffer for playback start ms
                    1000       // buffer for playback after rebuffer ms
                )
                .setTargetBufferBytes(5 * 1024 * 1024) // 5 MB total buffer
                .build()

            exoPlayer = ExoPlayer.Builder(context)
                .setLoadControl(loadControl)
                .setHandleAudioBecomingNoisy(true)
                .build()

            prepareMediaSource(Uri.parse(dataSource))

            setupListeners()

            textureEntry.setSize(1, 1)
            surface = textureEntry.surface
            exoPlayer?.setVideoSurface(surface)

            exoPlayer?.prepare()

            retryCount = 0

        } catch (e: Exception) {
            handleInitializationError(e)
        }
    }

    private fun handleInitializationError(error: Exception) {
        println("NCVP: Player initialization error: ${error.message}")

        if (retryCount < maxRetries) {
            retryCount++
            val delayMs = (1000 * retryCount).toLong() // Exponential backoff

            logInfo("Player [RETRY] Attempt $retryCount/$maxRetries in ${delayMs}ms")

            pendingRetry = Runnable {
                initializePlayer()
            }
            retryHandler.postDelayed(pendingRetry!!, delayMs)
        } else {
            val errorMessage = "Failed to initialize player after $maxRetries attempts: ${error.message}"
            eventSink?.error("VideoError", errorMessage, dataSource)
        }
    }

    private fun prepareMediaSource(uri: Uri) {
        val isNetwork = dataSource.startsWith("http") || dataSource.startsWith("https")

        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(15000)
            .setDefaultRequestProperties(httpHeaders)
            .setUserAgent("native_cache_video_player")

        val defaultDataSourceFactory = DefaultDataSource.Factory(context, httpDataSourceFactory)

        if (isNetwork) {
            val cacheManager = CacheManager.getInstance(context)

            val cacheDataSourceFactory = CacheDataSource.Factory()
                .setCache(cacheManager.simpleCache)
                .setUpstreamDataSourceFactory(defaultDataSourceFactory)
                .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR or CacheDataSource.FLAG_BLOCK_ON_CACHE)
                .setCacheKeyFactory { dataSpec -> cacheManager.getCacheKey(dataSpec.uri.toString()) }

            val mediaSourceFactory = DefaultMediaSourceFactory(cacheDataSourceFactory)
            exoPlayer?.setMediaSource(mediaSourceFactory.createMediaSource(MediaItem.fromUri(uri)))
        } else {
            val mediaSourceFactory = DefaultMediaSourceFactory(defaultDataSourceFactory)
            exoPlayer?.setMediaSource(mediaSourceFactory.createMediaSource(MediaItem.fromUri(uri)))
        }
    }

    private fun setupListeners() {
        exoPlayer?.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate()
                    }
                    Player.STATE_READY -> {
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                    }
                    Player.STATE_ENDED -> {
                        sendEvent("completed")
                    }
                    Player.STATE_IDLE -> {
                        exoPlayer?.playerError?.let { error ->
                            handlePlayerError(error)
                        }
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                handlePlayerError(error)
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    textureEntry.setSize(videoSize.width, videoSize.height)
                }

                if (isInitialized) {
                    sendPlayingState()
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                sendPlayingState()
            }
        })
    }

    private fun handlePlayerError(error: PlaybackException) {
        val message = error.cause?.message ?: error.message ?: "Unknown player error"
        println("NCVP: Player error: $message")

        val isNetworkError = error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_UNSPECIFIED

        if (isNetworkError) {
            if (retryCount < maxRetries) {
                retryCount++
                val delayMs = TimeUnit.SECONDS.toMillis(retryCount.toLong())

                logInfo("Player [RETRY] Network error, retrying in ${delayMs}ms (Code: ${error.errorCode})")

                pendingRetry = Runnable {
                    dispose(keepTexture = true)
                    initializePlayer()
                }
                retryHandler.postDelayed(pendingRetry!!, delayMs)
                return
            }
        }

        eventSink?.error("VideoError", "Video player error: $message", dataSource)
    }

    private fun sendPlayingState() {
        val event = HashMap<String, Any>()
        event["event"] = "isPlayingStateUpdate"
        event["isPlaying"] = exoPlayer?.isPlaying ?: false
        eventSink?.success(event)
    }

    private fun sendBufferingUpdate() {
        val event = HashMap<String, Any>()
        event["event"] = "bufferingUpdate"

        val ranges = ArrayList<List<Number>>()
        val buffered = exoPlayer?.bufferedPosition ?: 0L
        ranges.add(listOf(0, buffered))
        event["values"] = ranges

        eventSink?.success(event)
    }

    private fun sendInitialized() {
        val event = HashMap<String, Any>()
        event["event"] = "initialized"
        event["duration"] = exoPlayer?.duration ?: 0L

        val size = exoPlayer?.videoSize
        event["width"] = size?.width ?: 0
        event["height"] = size?.height ?: 0

        eventSink?.success(event)
    }

    private fun sendEvent(eventName: String) {
        val event = HashMap<String, Any>()
        event["event"] = eventName
        eventSink?.success(event)
    }

    // Public API methods
    fun play() {
        cancelPendingRetry()
        exoPlayer?.play()
    }

    fun pause() {
        exoPlayer?.pause()
    }

    fun setLooping(looping: Boolean) {
        exoPlayer?.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    fun setVolume(volume: Double) {
        exoPlayer?.volume = volume.toFloat()
    }

    fun setPlaybackSpeed(speed: Double) {
        exoPlayer?.setPlaybackSpeed(speed.toFloat())
    }

    fun setCaptionOffset(offset: Long) {
        captionOffset = offset
    }

    fun seekTo(location: Int) {
        exoPlayer?.seekTo(location.toLong())
    }

    fun getPosition(): Long {
        return exoPlayer?.currentPosition ?: 0L
    }

    fun setAudioAttributes(mixWithOthers: Boolean) {
        exoPlayer?.setAudioAttributes(
            androidx.media3.common.AudioAttributes.Builder()
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .setUsage(C.USAGE_MEDIA)
                .build(),
            !mixWithOthers
        )
    }

    private fun cancelPendingRetry() {
        pendingRetry?.let {
            retryHandler.removeCallbacks(it)
            pendingRetry = null
        }
    }

    fun dispose(keepTexture: Boolean = false) {
        cancelPendingRetry()

        exoPlayer?.let { player ->
            player.stop()
            player.clearVideoSurface()
            player.release()
        }
        exoPlayer = null

        surface?.release()
        surface = null

        if (!keepTexture) {
            try {
                textureEntry.release()
            } catch (e: Exception) {}
        }

        eventSink = null
    }
}
