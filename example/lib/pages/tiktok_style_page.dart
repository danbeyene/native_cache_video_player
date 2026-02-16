import 'dart:async';

import 'package:flutter/material.dart';
import 'package:native_cache_video_player/native_cache_video_player.dart';
import 'package:native_cache_video_player_example/utils/mock_data.dart';
import 'package:video_player/video_player.dart';

class TikTokStylePage extends StatefulWidget {
  const TikTokStylePage({super.key});

  @override
  State<TikTokStylePage> createState() => _TikTokStylePageState();
}

class _TikTokStylePageState extends State<TikTokStylePage> {
  final PageController _pageController = PageController();
  final List<String> _videoUrls = MockData.videoUrls.map((v) => v.url).toList();

  final Map<int, NativeCacheVideoPlayer> _players = {};
  int _currentIndex = 0;
  double _volume = 1.0;
  bool _isLooping = true;

  // Benchmarking stats
  final Map<int, DateTime> _initStartTimes = {};
  final Map<int, Duration> _initTimes = {};
  final Map<int, Duration> _firstFrameTimes = {};
  final Map<int, Duration> _scrollToRenderTimes = {};
  DateTime? _scrollStartTime;

  @override
  void initState() {
    super.initState();
    // Initialize first few players
    _managePlayers(0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var player in _players.values) {
      player.dispose();
    }
    super.dispose();
  }

  Future<void> _managePlayers(int index) async {
    // Determine which indices should be initialized
    final indicesToKeep = {index - 1, index, index + 1};

    // Dispose players that are no longer needed
    final indicesToRemove = _players.keys.where((i) => !indicesToKeep.contains(i)).toList();
    for (final i in indicesToRemove) {
      _players[i]?.dispose();
      _players.remove(i);
    }


    // Initialize needed players
    for (final i in indicesToKeep) {
      if (i >= 0 && i < _videoUrls.length) {


        if (!_players.containsKey(i)) {
          final player = NativeCacheVideoPlayer.networkUrl(Uri.parse(_videoUrls[i]));
          _players[i] = player;
          _initializePlayer(i);
        }
      }
    }

    // Play current, pause others
    _players.forEach((i, player) {
      if (player.isInitialized) {
        if (i == index) {
          player.controller.play();
          player.controller.setLooping(_isLooping);
          player.controller.setVolume(_volume);
        } else {
          player.controller.pause();
        }
      }
    });
  }

  Future<void> _initializePlayer(int index) async {
    final player = _players[index];
    try {
      if (player == null) return;
      
      _initStartTimes[index] = DateTime.now();
      
      await player.initialize();
      if (!mounted) {
        player.dispose();
        return;
      }
      
      // Double check if this index is still relevant
      if (!_players.containsKey(index)) {
         player.dispose();
         return;
      }

      final initDuration = DateTime.now().difference(_initStartTimes[index]!);
      _initTimes[index] = initDuration;
      debugPrint('TikTokStylePage: Video $index initialized in ${initDuration.inMilliseconds}ms (URL: ${_videoUrls[index]})');

      // Listen for first frame
      player.controller.addListener(() {
        if (!mounted) return;
        if (!_firstFrameTimes.containsKey(index) && 
            player.controller.value.position > Duration.zero) {
          final frameDuration = DateTime.now().difference(_initStartTimes[index]!);
          _firstFrameTimes[index] = frameDuration;
          if (_scrollStartTime != null) {
            _scrollToRenderTimes[index] = DateTime.now().difference(_scrollStartTime!);
          }
          debugPrint('TikTokStylePage: Video $index first frame rendered in ${frameDuration.inMilliseconds}ms (URL: ${_videoUrls[index]})');
          setState(() {});
        }
      });

      setState(() {});

      if (index == _currentIndex) {
        player.controller.play();
        player.controller.setLooping(_isLooping);
        player.controller.setVolume(_volume);
      }
    } catch (e) {
      debugPrint('Error initializing player $index: $e');
      player?.dispose();
    }
  }



  void _seekBy(int index, Duration offset) {
    final controller = _players[index]?.controller;
    if (controller != null) {
      controller.seekTo(controller.value.position + offset);
      setState(() {}); // Ensure UI updates if manually seeking
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text('TikTok-style Feed', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          controller: _pageController,
          itemCount: _videoUrls.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
              _scrollStartTime = DateTime.now();
            });
            _managePlayers(index);
          },
          itemBuilder: (context, index) {
            final player = _players[index];
            final isInitialized = player?.isInitialized ?? false;
            final isPlaying = isInitialized && player!.controller.value.isPlaying;
        
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onTap: () {
                    if (isInitialized) {
                      if (player!.controller.value.isPlaying) {
                        player.controller.pause();
                      } else {
                        player.controller.play();
                      }
                      setState(() {});
                    }
                  },
                  child: Container(
                    color: Colors.transparent, // Ensures the detector catches taps
                    child: isInitialized
                        ? Center(
                            child: AspectRatio(
                              aspectRatio: player!.controller.value.aspectRatio,
                              child: VideoPlayer(player.controller),
                            ),
                          )
                        : const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                  ),
                ),
                // Play Icon Overlay
                if (isInitialized && !isPlaying)
                  IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.play_arrow,
                        size: 80,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                // Progress Indicator at Top (Draggable)
                if (isInitialized)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 20), // Larger touch target
                      child: VideoProgressIndicator(
                        player!.controller,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: Colors.white.withValues(alpha: 0.8),
                          bufferedColor: Colors.white.withValues(alpha: 0.2),
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                  ),
                // Controls Overlay
                Positioned(
                  right: 16,
                  bottom: 100,
                  child: Column(
                    children: [
                      _ControlButton(
                        icon: _isLooping ? Icons.repeat_one : Icons.loop,
                        onTap: () {
                          setState(() {
                            _isLooping = !_isLooping;
                          });
                          player?.controller.setLooping(_isLooping);
                        },
                        label: 'Loop',
                      ),
                      const SizedBox(height: 16),
                      _ControlButton(
                        icon: _volume > 0 ? Icons.volume_up : Icons.volume_off,
                        onTap: () {
                          setState(() {
                            _volume = _volume > 0 ? 0 : 1.0;
                          });
                          player?.controller.setVolume(_volume);
                        },
                        label: 'Mute',
                      ),
                      const SizedBox(height: 16),
                      _ControlButton(
                        icon: Icons.replay_10,
                        onTap: () => _seekBy(index, const Duration(seconds: -10)),
                        label: '-10s',
                      ),
                      const SizedBox(height: 16),
                      _ControlButton(
                        icon: Icons.forward_10,
                        onTap: () => _seekBy(index, const Duration(seconds: 10)),
                        label: '+10s',
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 40,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Video #$index - ${MockData.videoUrls[index].title}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Cashing: ${isInitialized ? "Active" : "Pending..."}',
                        style: const TextStyle(
                          color: Colors.white70,
                          shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                        ),
                      ),
                      if (_initTimes.containsKey(index))
                        Text(
                          'Init: ${_initTimes[index]!.inMilliseconds}ms',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12,
                            shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                          ),
                        ),
                      if (_firstFrameTimes.containsKey(index))
                        Text(
                          'Render: ${_firstFrameTimes[index]!.inMilliseconds}ms',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                            shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                          ),
                        ),
                      if (_scrollToRenderTimes.containsKey(index))
                        Text(
                          'Scroll-to-Render: ${_scrollToRenderTimes[index]!.inMilliseconds}ms',
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 12,
                            shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                          ),
                        ),
                      if (isInitialized)
                        SizedBox(
                          width: 200,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            ),
                            child: Slider(
                              value: _volume,
                              onChanged: (v) {
                                setState(() {
                                  _volume = v;
                                });
                                player?.controller.setVolume(v);
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ],
    );
  }
}
