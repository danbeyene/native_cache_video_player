package com.example.native_cache_video_player

import android.content.Context
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import io.flutter.plugin.common.BinaryMessenger
import android.net.Uri
import java.util.concurrent.ConcurrentHashMap
import io.flutter.FlutterInjector
import android.os.Handler
import android.os.Looper

/**
 * The main entry point for the Native Cache Video Player Android implementation.
 *
 * This class implements the [FlutterPlugin] interface to register with the engine
 * and handles all MethodChannel communication from the Dart layer.
 */
class NativeCacheVideoPlayerPlugin: FlutterPlugin, MethodCallHandler {
    private lateinit var channel : MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private lateinit var context: Context
    private lateinit var binaryMessenger: BinaryMessenger

    private val players = LinkedHashMap<Long, FLTVideoPlayer>(16, 0.75f, true) // access-order LRU
    private var mixWithOthers = false
    private val MAX_PLAYERS = 4

    private val componentCallbacks = object : android.content.ComponentCallbacks2 {
        override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {}
        override fun onLowMemory() {
            purgeInactivePlayers("onLowMemory")
        }
        override fun onTrimMemory(level: Int) {
            if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL ||
                level >= android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE) {
                purgeInactivePlayers("onTrimMemory($level)")
            }
        }
    }

    private fun purgeInactivePlayers(reason: String) {
        println("NCVP: [MEMORY] $reason. Purging inactive players.")
        val toRemove = mutableListOf<Long>()
        synchronized(players) {
            for ((textureId, player) in players) {
                if (!player.isPlaying()) {
                    toRemove.add(textureId)
                }
            }
            for (textureId in toRemove) {
                println("NCVP: [MEMORY] Evicting idle player $textureId")
                players.remove(textureId)?.dispose()
            }
        }
    }

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "native_cache_video_player")
        channel.setMethodCallHandler(this)
        textureRegistry = flutterPluginBinding.textureRegistry
        context = flutterPluginBinding.applicationContext
        binaryMessenger = flutterPluginBinding.binaryMessenger

        context.registerComponentCallbacks(componentCallbacks)

        // Initialize CacheManager on a background thread to avoid blocking UI
        Thread {
            CacheManager.getInstance(context)
        }.start()
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "init" -> {
                result.success(null)
            }
            "updateConfig" -> {
                val args = call.arguments as? Map<String, Any?>
                val max = (args?.get("maxCacheSize") as? Number)?.toLong() ?: (500 * 1024 * 1024L)
                // Concurrent parameters are ignored – kept only for API compatibility
                val concurrent = (args?.get("concurrentPrecache") as? Number)?.toInt() ?: 3
                val concurrentDuringPlaybackDownload = (args?.get("concPrecacheDuringPlaybackDownload") as? Number)?.toInt() ?: 3

                Thread {
                    CacheManager.getInstance(context).updateConfig(max, concurrent, concurrentDuringPlaybackDownload)
                    Handler(Looper.getMainLooper()).post {
                        result.success(null)
                    }
                }.start()
            }
            "create" -> {
                val args = call.arguments as? Map<String, Any?>
                val uri = args?.get("uri") as? String
                val formatHint = args?.get("formatHint") as? String
                val httpHeaders = args?.get("httpHeaders") as? Map<String, String> ?: emptyMap()

                if (uri == null) {
                    result.error("invalid_args", "uri is null", null)
                    return
                }

                val asset = args?.get("asset") as? String
                val packageName = args?.get("package") as? String

                val producer = textureRegistry.createSurfaceProducer()
                val textureId = producer.id()

                // Limit concurrent players
                synchronized(players) {
                    if (players.size >= MAX_PLAYERS) {
                        val eldestKey = players.keys.iterator().next()
                        println("NCVP: [CONCURRENCY] Evicting oldest player $eldestKey due to limit ($MAX_PLAYERS)")
                        players.remove(eldestKey)?.dispose()
                    }
                }

                val finalUri = if (asset != null) {
                    val loader = FlutterInjector.instance().flutterLoader()
                    val assetLookupKey = if (packageName != null) loader.getLookupKeyForAsset(asset, packageName) else loader.getLookupKeyForAsset(asset)
                    "asset:///$assetLookupKey"
                } else {
                    uri
                }

                val eventChannel = EventChannel(binaryMessenger, "native_cache_video_player/videoEvents$textureId")

                val player = FLTVideoPlayer(context, eventChannel, producer, finalUri, formatHint, httpHeaders)
                player.setAudioAttributes(mixWithOthers)
                synchronized(players) {
                    players[textureId] = player
                }

                val reply = HashMap<String, Any>()
                reply["textureId"] = textureId
                result.success(reply)
            }
            "setMixWithOthers" -> {
                mixWithOthers = call.argument<Boolean>("mixWithOthers") ?: false
                result.success(null)
            }
            "clearAllCache" -> {
                Thread {
                    CacheManager.getInstance(context).clearAllCache(result)
                }.start()
            }
            "removeFile" -> {
                val args = call.arguments as? Map<String, Any?>
                val url = args?.get("url") as? String
                if (url != null) {
                    Thread {
                        CacheManager.getInstance(context).removeFile(url, result)
                    }.start()
                } else {
                    result.error("invalid_args", "url is null", null)
                }
            }
            "enforceCacheLimit" -> {
                val args = call.arguments as? Map<String, Any?>
                val max = (args?.get("maxCacheSize") as? Number)?.toLong()
                if (max != null) {
                    Thread {
                        CacheManager.getInstance(context).enforceCacheLimit(max, result)
                    }.start()
                } else {
                    result.error("invalid_args", "maxCacheSize is missing", null)
                }
            }
            else -> {
                val args = call.arguments as? Map<String, Any?>
                val textureId = (args?.get("textureId") as? Number)?.toLong()

                if (textureId != null) {
                    if (call.method == "dispose") {
                        val pTextureId = textureId
                        val player = synchronized(players) { players.remove(pTextureId) }
                        player?.dispose()
                        result.success(null)
                        return
                    }

                    val player = synchronized(players) { players[textureId] } // LinkedHashMap.get updates access order if configured as such
                    if (player != null) {
                        when (call.method) {
                            "play" -> { player.play(); result.success(null) }
                            "pause" -> { player.pause(); result.success(null) }
                            "setLooping" -> {
                                val looping = args?.get("looping") as? Boolean ?: false
                                player.setLooping(looping)
                                result.success(null)
                            }
                            "setVolume" -> {
                                val volume = (args?.get("volume") as? Number)?.toDouble() ?: 0.0
                                player.setVolume(volume)
                                result.success(null)
                            }
                            "setPlaybackSpeed" -> {
                                val speed = (args?.get("speed") as? Number)?.toDouble() ?: 1.0
                                player.setPlaybackSpeed(speed)
                                result.success(null)
                            }
                            "setCaptionOffset" -> {
                                val offset = (args?.get("offset") as? Number)?.toLong() ?: 0L
                                player.setCaptionOffset(offset)
                                result.success(null)
                            }
                            "seekTo" -> {
                                val pos = (args?.get("position") as? Number)?.toInt() ?: 0
                                player.seekTo(pos)
                                result.success(null)
                            }
                            "position" -> {
                                result.success(player.getPosition())
                            }
                            else -> result.notImplemented()
                        }
                    } else {
                        result.error("unknown_player", "No player found for textureId $textureId", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        context.unregisterComponentCallbacks(componentCallbacks)
        synchronized(players) {
            for (player in players.values) {
                player.dispose()
            }
            players.clear()
        }
    }
}
