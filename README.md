# Native Cache Video Player

A high-performance Flutter video player plugin with native-level caching for Android and iOS.

[![pub package](https://img.shields.io/pub/v/native_cache_video_player.svg)](https://pub.dev/packages/native_cache_video_player)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

`native_cache_video_player` provides smooth video playback with transparent native caching. It leverages platform-specific technologies (Media3/ExoPlayer on Android and AVFoundation with a custom ResourceLoader on iOS) to ensure videos load instantly, save data, and play without buffering on subsequent views.

---

## 🌟 Features

### ⚡️ Simultaneous Download & Cache
The plugin caches video data to the local disk **while** it streams. Subsequent plays of the same video load instantly from the local filesystem, significantly reducing bandwidth usage and latency.

### 🧹 Automated Cache Management (LRU)
Built-in Least Recently Used (LRU) eviction policy automatically manages disk space. When the cache exceeds the configured limit, the oldest unused videos are removed to free up space.

### 🔌 Drop-in Replacement
designed to be API-compatible with the standard `VideoPlayerController`. It can be used directly with standard Flutter UI widgets or popular libraries like **Chewie** with minimal code changes.

---

## 🏗 Architecture

Unlike other cache solutions that use a local proxy server, this plugin hooks directly into the native player's network stack:
*   **Android**: Uses ExoPlayer's `CacheDataSource`.
*   **iOS**: Implements `AVAssetResourceLoaderDelegate` to intercept and cache data requests.

This approach ensures better performance, stability, and support for complex seeking operations compared to proxy-based solutions.

---

## 📱 Supported Platforms

| Platform | Min Version | Underlying Tech |
| :--- | :--- | :--- |
| **Android** | API 21+ | Media3 / ExoPlayer |
| **iOS** | 13.0+ | AVFoundation |

---

## 📦 Installation

Add `native_cache_video_player` to your `pubspec.yaml`:

```yaml
dependencies:
  native_cache_video_player: ^0.1.0
```

---

## 🛠️ Configuration (Optional)

You can customize the cache behavior by initializing the plugin at startup. This is optional; default settings (500MB cache) are used if `init` is not called.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await NativeCacheVideoPlayer.init(
    NCVPConfig(
      // The maximum size of the cache in bytes.
      // Default: 500 MB (500 * 1024 * 1024)
      maxCacheSize: 1024 * 1024 * 512, 
    ),
  );
  
  runApp(MyApp());
}
```

---

## 📖 Usage

### Basic Playback

Create a player instance and use it with a `VideoPlayer` widget.

```dart
// 1. Create the player
final player = NativeCacheVideoPlayer.networkUrl(
  Uri.parse("https://example.com/video.mp4"),
);

// 2. Initialize
await player.initialize();

// 3. Use the controller in your UI
VideoPlayer(player.controller);
```

### Checking Disposed State

If your app handles backgrounding or has a memory limit, the native platform might evict the video player to save resources. You can check if the underlying native player is still active:

```dart
if (await player.isDisposed()) {
  // The player was evicted from the native cache LRU queue or disposed manually.
  // Re-initialize a new NativeCacheVideoPlayer instance if needed to resume playback.
}
```

### Supported Data Sources

The plugin supports various data sources, maintaining API parity with the standard video player:

#### Network (Cached)
```dart
final player = NativeCacheVideoPlayer.networkUrl(
  Uri.parse("https://example.com/video.mp4"),
);
```

#### Assets
```dart
final player = NativeCacheVideoPlayer.asset("assets/videos/intro.mp4");
```

#### Local Files
```dart
final player = NativeCacheVideoPlayer.file(File("/path/to/video.mp4"));
```

---

## 🛠️ Cache Management API

The plugin exposes static methods for manual cache control:

### Clear All Cache
Removes all cached video files from the device.

```dart
await NativeCacheVideoPlayer.clearAllCache();
```

### Remove Specific Video
Removes a single video from the cache.

```dart
await NativeCacheVideoPlayer.removeFileFromCache(
  Uri.parse("https://example.com/video.mp4"),
);
```

### Enforce Size Limit
Manually triggers the LRU eviction process.

```dart
await NativeCacheVideoPlayer.enforceCacheLimit(
  maxCacheSize: 256 * 1024 * 1024, // 256 MB
);
```

---

## ⚠️ Known Limitations

*   **HLS/DASH Support**: Caching is currently optimized for progressive download (MP4/MOV). HLS (.m3u8) streams may play but are not fully cached offline due to the complexity of multi-segment caching.
*   **Web Support**: This plugin does not support Flutter Web. It creates a standard `VideoPlayerController` on web without caching.

---

## 🤝 Contributing

Contributions are welcome! Please see the [Contributing Guide](https://github.com/danbeyene/native_cache_video_player/blob/main/CONTRIBUTING.md) for details.

1.  **Report Issues**: Submit bugs and feature requests via [GitHub Issues](https://github.com/danbeyene/native_cache_video_player/issues).
2.  **Submit Pull Requests**: Improvements to native implementations or Dart API are appreciated. Feel free to open a [Pull Request](https://github.com/danbeyene/native_cache_video_player/pulls).

---

## ⚖️ License

This project is licensed under the MIT License.
