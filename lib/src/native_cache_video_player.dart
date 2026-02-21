import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'ncvp_logger.dart';
import 'ios_platform_interface.dart';
import 'android_platform_interface.dart';
import 'ncvp_config.dart';
import 'platform_interface_extension.dart';

export 'ncvp_config.dart';

/// A video player that wraps [VideoPlayerController] to provide high-performance
/// native caching capabilities.
///
/// This class acts as a seamless wrapper around the standard Flutter video player,
/// automatically handling network video caching using native platform APIs (ExoPlayer on Android
/// and AVPlayer with a custom resource loader on iOS).
class NativeCacheVideoPlayer {
  /// Constructs a [NativeCacheVideoPlayer] playing a video from an asset.
  NativeCacheVideoPlayer.asset(
    this.dataSource, {
    this.package,
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.viewType = VideoViewType.textureView,
  })  : dataSourceType = DataSourceType.asset,
        formatHint = null,
        httpHeaders = const <String, String>{},
        skipCache = true;

  /// Constructs a [NativeCacheVideoPlayer] playing a video from a network URL.
  NativeCacheVideoPlayer.networkUrl(
    Uri url, {
    this.formatHint,
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.httpHeaders = const <String, String>{},
    Map<String, String>? downloadHeaders,
    this.viewType = VideoViewType.textureView,
    this.skipCache = false,
    String? cacheKey,
  })  : dataSource = url.toString(),
        dataSourceType = DataSourceType.network,
        package = null;

  /// Constructs a [NativeCacheVideoPlayer] for playing high-definition or local 
  /// videos from a file on the device.
  NativeCacheVideoPlayer.file(
    File file, {
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.httpHeaders = const <String, String>{},
    this.viewType = VideoViewType.textureView,
  })  : dataSource = file.absolute.path,
        dataSourceType = DataSourceType.file,
        package = null,
        formatHint = null,
        skipCache = true;

  /// Constructs a [NativeCacheVideoPlayer] playing a video from a contentUri.
  NativeCacheVideoPlayer.contentUri(
    Uri contentUri, {
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.viewType = VideoViewType.textureView,
  })  : assert(
          defaultTargetPlatform == TargetPlatform.android,
          'NativeCacheVideoPlayer.contentUri is only supported on Android.',
        ),
        dataSource = contentUri.toString(),
        dataSourceType = DataSourceType.contentUri,
        package = null,
        formatHint = null,
        httpHeaders = const <String, String>{},
        skipCache = true;

  final String dataSource;
  final Map<String, String> httpHeaders;
  final VideoFormat? formatHint;
  final DataSourceType dataSourceType;
  final VideoPlayerOptions? videoPlayerOptions;
  final String? package;
  final Future<ClosedCaptionFile>? closedCaptionFile;
  final VideoViewType viewType;
  final bool skipCache;

  VideoPlayerController? _videoPlayerController;

  /// Provides access to the underlying [VideoPlayerController].
  /// 
  /// Ensure [initialize] has been called and completed before accessing this property.
  VideoPlayerController get controller {
    if (_videoPlayerController == null) {
      throw StateError(
        'NativeCacheVideoPlayer has not been initialized. '
        'Please call initialize() and await its completion before accessing the controller.',
      );
    }
    return _videoPlayerController!;
  }

  static NCVPConfig _config = const NCVPConfig();

  /// Initializes the plugin with a custom configuration.
  ///
  /// This should be called before any [NativeCacheVideoPlayer] is initialized
  /// to ensure the global settings are applied.
  static Future<void> init(NCVPConfig config) async {
    _config = config;
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
        await const MethodChannel('native_cache_video_player').invokeMethod('updateConfig', config.toMap());
    }
    ncvpLog('Plugin initialized with config: $config');
  }

  static bool _platformRegistered = false;
  bool _isInitialized = false;
  bool _isDisposed = false;

  bool get isInitialized => _isInitialized;

  /// Checks if the underlying native player has been disposed natively (e.g., due to memory eviction
  /// or when [dispose] was called).
  Future<bool> isDisposed() async {
    if (_isDisposed) return true;
    if (!_isInitialized || _videoPlayerController == null) return false;
    
    final platform = VideoPlayerPlatform.instance;
    if (platform is NativeCachePlatformExtension) {
      // ignore: invalid_use_of_visible_for_testing_member
      return await (platform as NativeCachePlatformExtension).isPlayerDisposed(_videoPlayerController!.playerId);
    }
    return false;
  }

  bool get _shouldUseCache {
    return dataSourceType == DataSourceType.network && !kIsWeb && !skipCache;
  }

  /// Prepares the video player for playback and configures native caching.
  /// 
  /// This method sets up the platform-specific interfaces, prepares the data source 
  /// (applying the 'cache' scheme on iOS where necessary), and initializes the 
  /// underlying [VideoPlayerController].
  Future<void> initialize() async {
    if (_isInitialized) {
      ncvpLog('NativeCacheVideoPlayer is already initialized.');
      return;
    }

    // Register iOS/Android platform interface if needed once
    if (!NativeCacheVideoPlayer._platformRegistered) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        NativeCacheVideoPlayerPlatformWithEvents.registerWith();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        NativeCacheVideoPlayerPlatformAndroid.registerWith();
      }
      NativeCacheVideoPlayer._platformRegistered = true;
    }

    String realDataSource = dataSource;
    final Map<String, String> controllerHeaders = Map.from(httpHeaders);

    // Prepare the data source with native caching if applicable
    if (_shouldUseCache) {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS Native Caching Logic
        final sourceUrl = Uri.parse(dataSource);
        if (sourceUrl.scheme == 'http' || sourceUrl.scheme == 'https') {
          // Use 'cache' scheme to trigger native ResourceLoader
          realDataSource = sourceUrl.replace(scheme: 'cache').toString();
          ncvpLog('Using iOS native cache: $realDataSource');
        }
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        // Android Native Caching Logic (ExoPlayer CacheDataSource)
        ncvpLog('Using Android native cache (ExoPlayer): $realDataSource');
      }
    }

    _videoPlayerController = switch (dataSourceType) {
      DataSourceType.asset => VideoPlayerController.asset(
          dataSource,
          package: package,
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          viewType: viewType,
        ),
      DataSourceType.network => VideoPlayerController.networkUrl(
          Uri.parse(realDataSource),
          formatHint: formatHint,
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          httpHeaders: controllerHeaders,
          viewType: viewType,
        ),
      DataSourceType.contentUri => VideoPlayerController.contentUri(
          Uri.parse(dataSource),
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          viewType: viewType,
        ),
      _ => VideoPlayerController.file(
          File(dataSource),
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          httpHeaders: httpHeaders,
          viewType: viewType,
        ),
    };

    await _videoPlayerController!.initialize();
    
    if (_isDisposed) {
       // Was disposed during initialization
       await _videoPlayerController!.dispose();
       return;
    }
    _isInitialized = true;
    unawaited(enforceCacheLimit(maxCacheSize: _config.maxCacheSize));
  }

  /// Releases all resources held by the player and the underlying controller.
  Future<void> dispose() async {
    if (_isDisposed) return Future.value();
    _isDisposed = true;
    _isInitialized = false; // Mark as not initialized to prevent usage
    
    // Dispose resources even if not fully initialized (race condition fix)
    await _videoPlayerController?.dispose();
  }

  /// Removes the current video's data from the native cache.
  Future<bool> removeFromCache() async {
    if (_shouldUseCache) {
      final platform = VideoPlayerPlatform.instance;
      if (platform is NativeCachePlatformExtension) {
        return (platform as NativeCachePlatformExtension).removeFile(dataSource);
      }
    }
    return false;
  }

  /// Deletes a specific video file from the cache using its [url].
  static Future<bool> removeFileFromCache(Uri url) async {
     final platform = VideoPlayerPlatform.instance;
     if (platform is NativeCachePlatformExtension) {
       return (platform as NativeCachePlatformExtension).removeFile(url.toString());
     }
     return false;
  }

  /// Deletes a specific video file from the cache using its [cacheKey].
  static Future<bool> removeFileFromCacheByKey(String cacheKey) async {
    // Current implementation assumes key == url for removal if not using headers.
     final platform = VideoPlayerPlatform.instance;
     if (platform is NativeCachePlatformExtension) {
       return (platform as NativeCachePlatformExtension).removeFile(cacheKey);
     }
     return false;
  }

  /// Clears all cached video files from the device.
  static Future<bool> clearAllCache() async {
    final platform = VideoPlayerPlatform.instance;
    if (platform is NativeCachePlatformExtension) {
        final cleared = await (platform as NativeCachePlatformExtension).clearAllCache();
        ncvpLog(cleared ? 'Cache cleared with data removed.' : 'Cache clear requested (was empty or no change).');
        return cleared;
    }
    return false;
  }

  /// Enforces a maximum cache size by deleting oldest inactive cache files.
  ///
  /// [maxCacheSize] is the maximum allowed cache size in bytes.
  /// Default is 500MB. Files are sorted by last access time, oldest deleted first.
  static Future<bool> enforceCacheLimit({int maxCacheSize = 500 * 1024 * 1024}) async {
    final platform = VideoPlayerPlatform.instance;
    if (platform is NativeCachePlatformExtension) {
        final removed = await (platform as NativeCachePlatformExtension).enforceCacheLimit(maxCacheSize);
        if (removed) ncvpLog('Cache limit enforced: some files removed.');
        return removed;
    }
    return false;
  }
}
