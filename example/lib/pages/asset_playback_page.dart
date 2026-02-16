import 'package:native_cache_video_player/native_cache_video_player.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A page demonstrating video playback from application assets.
/// 
/// This example shows how to use the `asset` constructor of [NativeCacheVideoPlayer] 
/// to play local media bundled with the application.
class AssetPlaybackPage extends StatefulWidget {
  const AssetPlaybackPage({super.key});

  @override
  State<AssetPlaybackPage> createState() => _AssetPlaybackPageState();
}

class _AssetPlaybackPageState extends State<AssetPlaybackPage> {
  late final NativeCacheVideoPlayer _player;

  DataSourceType? _dataSourceType;

  double _volume = 1;

  @override
  void initState() {
    super.initState();

    _player = NativeCacheVideoPlayer.asset('assets/sample.mp4');
    
    final stopwatch = Stopwatch()..start();
    debugPrint('Benchmark: Starting player initialization...');

    _initializePlayer(stopwatch);
  }

  Future<void> _initializePlayer(Stopwatch stopwatch) async {
    try {
      debugPrint('EXAMPLE: Initializing asset playback for assets/sample.mp4');
      await _player.initialize();
      stopwatch.stop();
      debugPrint('Benchmark: Player initialization took: ${stopwatch.elapsedMilliseconds}ms');

      if (!mounted) return;

      setState(() {
        _dataSourceType = _controller.dataSourceType;
      });

      _controller.addListener(() {
        if (mounted) setState(() {});
      });
      _controller.play();
      debugPrint('EXAMPLE: Player initialized and playing.');
    } catch (e) {
      debugPrint('EXAMPLE Error: Initialization failed: $e');
      if (!mounted) return;
       
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load asset video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  VideoPlayerController get _controller => _player.controller;

  void _seekBy(Duration offset) {
    _controller.seekTo(_controller.value.position + offset);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Playback'),
      ),
      body: _player.isInitialized
          ? Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Video Source: ${_dataSourceType!.name}\n'
                      '(Demonstrating local asset playback)',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                  const SizedBox(height: 16),
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.first_page),
                        onPressed: () {
                          _controller.seekTo(Duration.zero);
                        },
                        tooltip: 'Back to the beginning',
                      ),
                      IconButton(
                        icon: const Icon(Icons.replay_10),
                        onPressed: () {
                          _seekBy(const Duration(seconds: -10));
                        },
                        tooltip: 'Rewind 10 seconds',
                      ),
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        onPressed: () {
                          if (_controller.value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                        },
                        tooltip: _controller.value.isPlaying
                            ? 'Pause'
                            : 'Play',
                      ),
                      IconButton(
                        icon: const Icon(Icons.forward_10),
                        onPressed: () {
                          _seekBy(const Duration(seconds: 10));
                        },
                        tooltip:
                            'Forward 10 seconds',
                      ),
                      IconButton(
                        icon: const Icon(Icons.last_page),
                        onPressed: () {
                          _controller.seekTo(_controller.value.duration);
                        },
                        tooltip: 'To the end',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          _controller.value.isLooping
                              ? Icons.repeat_one
                              : Icons.loop,
                        ),
                        onPressed: () {
                          _controller.setLooping(!_controller.value.isLooping);
                        },
                        tooltip: _controller.value.isLooping
                            ? 'Looping: ON'
                            : 'Looping: OFF',
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _controller.value.volume > 0
                                  ? Icons.volume_up
                                  : Icons.volume_off,
                            ),
                            onPressed: () {
                              if (_controller.value.volume > 0) {
                                _controller.setVolume(0);
                              } else {
                                _controller.setVolume(_volume);
                              }
                            },
                            tooltip: _controller.value.volume > 0
                                ? 'Mute'
                                : 'Unmute',
                          ),
                          Slider(
                            value: _controller.value.volume,
                            onChanged: (value) {
                              _controller.setVolume(value);
                              _volume = value;
                            },
                            divisions: 10,
                            label:
                                'Volume: ${(_controller.value.volume * 100).round()}%',
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            )
          : Center(child: const CircularProgressIndicator()),
    );
  }
}
