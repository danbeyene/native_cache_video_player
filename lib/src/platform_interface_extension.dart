
/// Interface for platform-specific cache management operations.
/// 
/// Implementations of [VideoPlayerPlatform] should mix in or implement this
/// interface to support native cache features.
abstract class NativeCachePlatformExtension {
  /// Clears all cached video files.
  Future<bool> clearAllCache();

  /// Removes a specific file from the cache by its [url].
  Future<bool> removeFile(String url);

  /// Enforces the cache size limit by evicting LRU items.
  Future<bool> enforceCacheLimit(int maxCacheSize);

  /// Checks if the native player for the given [textureId] has been disposed (e.g., evicted).
  Future<bool> isPlayerDisposed(int textureId);
}
