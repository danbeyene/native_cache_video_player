## 0.1.1

* **Bug Fix**: Fixed `PlatformException(unknown_player)` crash when calling methods on players that were already disposed by LRU eviction or memory pressure. Operations on disposed players now gracefully return success instead of throwing.

## 0.1.0

* Initial release of `native_cache_video_player`.
* **Core Features**:
    *   Simultaneous video download and caching.
    *   LRU (Least Recently Used) cache management.
    *   Background thread processing for cache operations.
* **Android**: Implementation using Media3/ExoPlayer with `CacheDataSource`.
* **iOS**: Implementation using AVFoundation with `AVAssetResourceLoaderDelegate`.
