## 0.1.6

* **Chore**: Bumped `video_player` dependency to `^2.11.1`.

## 0.1.5

* **Fix**: Resolved issue where `setMixWithOthers` was not propagated to existing player instances on Android and iOS. This ensures that audio focus settings are applied immediately to all active players.

## 0.1.4


* **Fix**: Resolved `java.lang.OutOfMemoryError` on Android by properly unregistering the `EventChannel` stream handler when `FLTVideoPlayer` is disposed, allowing native `ExoPlayer` instances to be garbage collected.

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
