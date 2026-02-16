import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:native_cache_video_player/native_cache_video_player.dart';
import 'package:native_cache_video_player/src/platform_interface_extension.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:flutter/rendering.dart';

class MockNativeCacheVideoPlayerPlatform extends VideoPlayerPlatform
    implements NativeCachePlatformExtension {
  final Map<String, dynamic> methodCalls = {};

  @override
  Future<int?> create(DataSource dataSource) async {
    methodCalls['create'] = dataSource.uri;
    return 123;
  }

  @override
  Future<void> init() async {
    methodCalls['init'] = true;
  }
  
  @override
  Future<void> setLooping(int textureId, bool looping) async {}
  
  @override
  Future<void> play(int textureId) async {}
  
  @override
  Future<void> pause(int textureId) async {}
  
  @override
  Future<void> setVolume(int textureId, double volume) async {}
  
  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {}
  
  @override
  Future<void> seekTo(int textureId, Duration position) async {}
  
  @override
  Future<Duration> getPosition(int textureId) async {
    return Duration.zero;
  }
  
  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return Stream.value(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(1920, 1080),
    ));
  }

  @override
  Future<bool> clearAllCache() async {
    methodCalls['clearAllCache'] = true;
    return true;
  }

  @override
  Future<bool> enforceCacheLimit(int maxCacheSize) async {
    methodCalls['enforceCacheLimit'] = maxCacheSize;
    return true;
  }

  @override
  Future<bool> removeFile(String url) async {
    methodCalls['removeFile'] = url;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockNativeCacheVideoPlayerPlatform mockPlatform;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    mockPlatform = MockNativeCacheVideoPlayerPlatform();
    VideoPlayerPlatform.instance = mockPlatform;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('NativeCacheVideoPlayer', () {
    test('initialize() registers platform and creates controller', () async {
      final player = NativeCacheVideoPlayer.networkUrl(
        Uri.parse('https://example.com/video.mp4'),
      );

      await player.initialize();

      expect(mockPlatform.methodCalls['create'], contains('https://example.com/video.mp4'));
      expect(player.isInitialized, isTrue);
    });

    test('clearAllCache() calls platform method', () async {
      await NativeCacheVideoPlayer.clearAllCache();
      expect(mockPlatform.methodCalls['clearAllCache'], isTrue);
    });

    test('removeFileFromCache() calls platform method with URL', () async {
      final url = Uri.parse('https://example.com/video.mp4');
      await NativeCacheVideoPlayer.removeFileFromCache(url);
      expect(mockPlatform.methodCalls['removeFile'], url.toString());
    });

    test('enforceCacheLimit() calls platform method with size', () async {
      await NativeCacheVideoPlayer.enforceCacheLimit(maxCacheSize: 100);
      expect(mockPlatform.methodCalls['enforceCacheLimit'], 100);
    });
  });
}
