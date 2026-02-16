/// Global configuration settings for the [NativeCacheVideoPlayer] plugin.
class NCVPConfig {
  /// The maximum size of the cache in bytes.
  ///
  /// Defaults to 500 MB (500 * 1024 * 1024).
  final int maxCacheSize;

  const NCVPConfig({
    this.maxCacheSize = 500 * 1024 * 1024,
  });

  /// Converts the configuration settings into a map for platform channel communication.
  Map<String, dynamic> toMap() {
    return {
      'maxCacheSize': maxCacheSize,
    };
  }

  @override
  String toString() {
    return 'NCVPConfig(maxCacheSize: $maxCacheSize)';
  }
}
