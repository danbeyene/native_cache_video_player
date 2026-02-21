## 0.1.2

* **New Feature**: Added `isDisposed()` method to `NativeCacheVideoPlayer` to allow checking if the underlying native player has been evicted due to memory pressure or LRU cache limits.
* **Fix**: Suppress `position` warnings when a player is already natively disposed.

## 0.1.1

## 0.1.0

* Initial release of `native_cache_video_player`.
* **Core Features**:
    *   Simultaneous video download and caching.
    *   LRU (Least Recently Used) cache management.
    *   Background thread processing for cache operations.
* **Android**: Implementation using Media3/ExoPlayer with `CacheDataSource`.
* **iOS**: Implementation using AVFoundation with `AVAssetResourceLoaderDelegate`.
