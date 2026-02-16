/// The [video_player] plugin that went to therapy, worked on its commitment
/// issues, and now actually remembers your videos!
///
/// ## Basic Usage

/// final player = NativeCacheVideoPlayer.networkUrl(
///   Uri.parse('https://example.com/video.mp4'),
///   invalidateCacheIfOlderThan: const Duration(days: 42),
/// );
///
/// await player.initialize();
/// // Use player.controller for video operations
/// ```
///
/// [video_player]: https://pub.dev/packages/video_player
library;

export 'src/native_cache_video_player.dart';
export 'src/ncvp_logger.dart';