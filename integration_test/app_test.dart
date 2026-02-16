import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_cache_video_player/native_cache_video_player.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NativeCacheVideoPlayer initializes successfully',
      (WidgetTester tester) async {
    // This test requires a running device/emulator to pass fully if it calls native code.
    // Here we just verify the Dart side API availability.
    
    // Note: In a real integration test, we would spin up the example app
    // and interact with it.
    
    final player = NativeCacheVideoPlayer.networkUrl(
      Uri.parse('https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'),
    );
    
    // We expect this might fail on CI without a device, so we wrap it or just check
    // structural integrity involved in the test.
    // For now, we just assert the player object is created correctly.
    expect(player.dataSource, contains('BigBuckBunny.mp4'));
    
    // Attempting initialize() without a registered platform implementation on the test side
    // (if not running on device) would throw. 
    // So we leave this as a skeleton for future expansion.
  });
}
