import 'package:flutter/foundation.dart';

/// Internal utility function to log debug messages with a package-specific prefix.
/// 
/// This facilitates easier debugging and log filtering in the terminal.
void ncvpLog(String message, {int? wrapWidth}) {
  if (kDebugMode) {
    debugPrint('native_cache_video_player: $message', wrapWidth: wrapWidth);
  }
}
