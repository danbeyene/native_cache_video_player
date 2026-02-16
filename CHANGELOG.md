## 0.1.0

* Initial release of `native_cache_video_player`.
* **Core Features**:
    *   Simultaneous video download and caching.
    *   LRU (Least Recently Used) cache management.
    *   Background thread processing for cache operations.
* **Android**: Implementation using Media3/ExoPlayer with `CacheDataSource`.
* **iOS**: Implementation using AVFoundation with `AVAssetResourceLoaderDelegate`.
