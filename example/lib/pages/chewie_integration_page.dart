import 'package:native_cache_video_player/native_cache_video_player.dart';
import 'package:native_cache_video_player_example/utils/mock_data.dart';
import 'package:native_cache_video_player_example/widgets/fixed_material_controls.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A page demonstrating how to integrate [NativeCacheVideoPlayer] with the 
/// popular [Chewie] UI framework.
/// 
/// This example illustrates that the controller provided by [NativeCacheVideoPlayer] 
/// is fully compatible with third-party player UI libraries.
class ChewieIntegrationPage extends StatefulWidget {
  const ChewieIntegrationPage({super.key});

  @override
  State<ChewieIntegrationPage> createState() => _ChewieIntegrationPageState();
}

class _ChewieIntegrationPageState extends State<ChewieIntegrationPage> {
  late final NativeCacheVideoPlayer _player;

  ChewieController? _chewieController;
  DataSourceType? _dataSourceType;
  VideoPlayerController get _controller => _player.controller;

  @override
  void initState() {
    super.initState();

    _player = NativeCacheVideoPlayer.networkUrl(
      Uri.parse(MockData.videoUrls[11].url),
    );
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      debugPrint('EXAMPLE: Initializing Chewie with ${MockData.videoUrls[11].url}');
      await _player.initialize();
      if (!mounted) return;

      setState(() {
        _dataSourceType = _controller.dataSourceType;

        _chewieController = ChewieController(
          videoPlayerController: _controller,
          autoPlay: true,
          looping: false,
          customControls: const FixedMaterialControls(),
        );
      });
      debugPrint('EXAMPLE: Chewie initialized and playing.');
    } catch (e) {
      debugPrint('EXAMPLE Error: chewie init failed: $e');
      if (!mounted) return;
       
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load video (Chewie): $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chewie Player Integration'),
      ),
      body: _player.isInitialized && _chewieController != null
          ? Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Video Source: ${_dataSourceType!.name}\n'
                      '(Integrated playback using the Chewie UI framework)',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: Chewie(controller: _chewieController!),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Powered by native_cache_video_player and chewie\n'
                    '(A comprehensive solution for cached video playback)',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
