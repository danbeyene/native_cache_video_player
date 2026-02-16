package com.example.native_cache_video_player

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Manages the native video cache on Android using Media3's SimpleCache.
 *
 * This class handles file system operations, metadata storage, and cache eviction.
 */
@UnstableApi
class CacheManager private constructor(private val context: Context) {

    companion object {
        @Volatile
        private var INSTANCE: CacheManager? = null
        private const val DEFAULT_MAX_CACHE_SIZE = 500 * 1024 * 1024L // 500 MB default

        fun getInstance(context: Context): CacheManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: CacheManager(context.applicationContext).also { INSTANCE = it }
            }
        }
    }

    private val cacheDir: File = File(context.filesDir, "native_cache_video_player")
    private var evictor: LeastRecentlyUsedCacheEvictor
    private var databaseProvider: StandaloneDatabaseProvider
    val simpleCache: SimpleCache

    // Configuration
    @Volatile
    private var maxCacheSize = DEFAULT_MAX_CACHE_SIZE

    private fun logInfo(message: String) {
        println("NCVP: $message")
    }

    init {
        if (!cacheDir.exists()) {
            cacheDir.mkdirs()
        }
        evictor = LeastRecentlyUsedCacheEvictor(maxCacheSize)
        databaseProvider = StandaloneDatabaseProvider(context)
        simpleCache = SimpleCache(cacheDir, evictor, databaseProvider)
    }

    /**
     * Updates the cache configuration dynamically.
     */
    fun updateConfig(maxSize: Long, concurrent: Int, concurrentWhilePlaying: Int) {
        maxCacheSize = maxSize
        evictor = LeastRecentlyUsedCacheEvictor(maxSize)
    }

    // MARK: - Cache File Management

    /**
     * Returns the cache key for a URL (SHA-256 hash)
     */
    fun getCacheKey(url: String): String {
        val bytes = url.toByteArray()
        val md = MessageDigest.getInstance("SHA-256")
        val digest = md.digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    /**
     * Returns the file path for a cached video.
     * This is used by the Flutter side to check if a video is cached.
     */
    fun getCachePath(url: String): String? {
        val key = getCacheKey(url)

        // Check if any content is cached for this key
        if (!simpleCache.isCached(key, 0, 0)) {
            return null
        }

        // Get the first cached span to determine file location
        val spans = simpleCache.getCachedSpans(key)
        if (spans.isNotEmpty()) {
            val span = spans.first()
            // SimpleCache stores files in: cacheDir / key / [span.file].data
            // We need to reconstruct the path
            val cacheFile = File(cacheDir, key)
            if (cacheFile.exists()) {
                return cacheFile.absolutePath
            }
        }
        return null
    }

    /**
     * Checks if a URL is fully cached.
     */
    fun isFullyCached(url: String): Boolean {
        return try {
            val key = getCacheKey(url)
            val metadata = simpleCache.getContentMetadata(key)
            val contentLength = androidx.media3.datasource.cache.ContentMetadata.getContentLength(metadata)
            if (contentLength <= 0) return false

            val cachedBytes = simpleCache.getCachedBytes(key, 0, contentLength)
            cachedBytes >= contentLength
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Gets the cached size for a URL in bytes.
     */
    fun getCachedSize(url: String): Long {
        val key = getCacheKey(url)
        val metadata = simpleCache.getContentMetadata(key)
        val contentLength = androidx.media3.datasource.cache.ContentMetadata.getContentLength(metadata)
        if (contentLength <= 0) return 0

        return simpleCache.getCachedBytes(key, 0, contentLength)
    }

    // MARK: - File System Operations

    fun clearAllCache(result: MethodChannel.Result? = null) {
        Thread {
            try {
                val keys = simpleCache.keys.toList()
                var deletedCount = 0
                for (key in keys) {
                    simpleCache.removeResource(key)
                    deletedCount++
                }
                Handler(Looper.getMainLooper()).post {
                    result?.success(deletedCount > 0)
                }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result?.error("cache_error", "Failed to clear cache: ${e.message}", null)
                }
            }
        }.start()
    }

    fun removeFile(url: String, result: MethodChannel.Result? = null) {
        Thread {
            try {
                val key = getCacheKey(url)
                val wasPresent = simpleCache.keys.contains(key)
                if (wasPresent) {
                    simpleCache.removeResource(key)
                }
                Handler(Looper.getMainLooper()).post {
                    result?.success(wasPresent)
                }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result?.error("cache_error", "Failed to remove file: ${e.message}", null)
                }
            }
        }.start()
    }

    fun enforceCacheLimit(maxSize: Long, result: MethodChannel.Result? = null) {
        Thread {
            try {
                // Update evictor's max size
                evictor = LeastRecentlyUsedCacheEvictor(maxSize)

                val currentSize = simpleCache.cacheSpace
                if (currentSize <= maxSize) {
                    Handler(Looper.getMainLooper()).post { result?.success(false) }
                    return@Thread
                }

                // Force eviction
                var deletedAny = false
                val keys = simpleCache.keys.toList()

                // Sort keys by last access time (LRU)
                val spansByKey = keys.associateWith { key ->
                    simpleCache.getCachedSpans(key).maxByOrNull { it.lastTouchTimestamp }
                }

                val sortedKeys = keys.sortedBy { key ->
                    spansByKey[key]?.lastTouchTimestamp ?: 0
                }

                for (key in sortedKeys) {
                    if (simpleCache.cacheSpace <= maxSize) break
                    simpleCache.removeResource(key)
                    deletedAny = true
                }

                Handler(Looper.getMainLooper()).post { result?.success(deletedAny) }
            } catch (e: Exception) {
                Handler(Looper.getMainLooper()).post {
                    result?.error("cache_error", "Failed to enforce cache limit: ${e.message}", null)
                }
            }
        }.start()
    }
}
