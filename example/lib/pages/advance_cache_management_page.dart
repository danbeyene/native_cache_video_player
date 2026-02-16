import 'package:native_cache_video_player/native_cache_video_player.dart';
import 'package:flutter/material.dart';
import 'package:native_cache_video_player_example/utils/mock_data.dart';


class _VideoInfo {
  _VideoInfo(this.url, this.title);

  final String url;
  final String title;
}

/// A page providing administrative controls for managing the native cache.
/// 
/// This example demonstrates how to configure global cache settings (size limits, 
/// concurrency), clear the entire cache, or remove specific files by key.
class AdvanceCacheManagementPage extends StatefulWidget {
  const AdvanceCacheManagementPage({super.key});

  @override
  State<AdvanceCacheManagementPage> createState() =>
      _AdvanceCacheManagementPageState();
}

class _AdvanceCacheManagementPageState
    extends State<AdvanceCacheManagementPage> {
  final _videoUrls = MockData.videoUrls.skip(4).take(5).map((v) => _VideoInfo(v.url, v.title)).toList();

  int _selectedIndex = 0;
  double _maxCacheSizeMB = 500;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
  }



  Future<void> _clearAllCache() async {
    setState(() => _statusMessage = 'Clearing cache...');
    debugPrint('EXAMPLE: Clearing all cache...');
    try {
      final cleared = await NativeCacheVideoPlayer.clearAllCache();
      if (mounted) {
        final message = cleared ? 'Cache cleared successfully.' : 'Cache was already empty.';
        debugPrint('EXAMPLE: $message');
        setState(() => _statusMessage = message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: cleared ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
       debugPrint('EXAMPLE Error: Clear cache failed: $e');
       if (mounted) {
         setState(() => _statusMessage = 'Clear cache failed: $e');
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Clear cache failed: $e'),
             backgroundColor: Colors.red,
           ),
         );
       }
    }
  }

  Future<void> _deleteCacheFile(String url) async {
    setState(() => _statusMessage = 'Removing cache for: $url...');
    debugPrint('EXAMPLE: Removing cache for $url');
    try {
      final removed = await NativeCacheVideoPlayer.removeFileFromCache(Uri.parse(url));
      if (mounted) {
        final message = removed ? 'File removed from cache.' : 'File was not in cache.';
        debugPrint('EXAMPLE: $message');
        setState(() => _statusMessage = message);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: removed ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('EXAMPLE Error: Remove failed: $e');
      if (mounted) {
        setState(() => _statusMessage = 'Remove failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Remove failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  Future<void> _updateConfig() async {
    debugPrint('EXAMPLE: Updating config: Size=${_maxCacheSizeMB}MB');
    try {
      await NativeCacheVideoPlayer.init(NCVPConfig(
        maxCacheSize: (_maxCacheSizeMB * 1024 * 1024).toInt(),
      ));
      if (mounted) {
        debugPrint('EXAMPLE: Config updated successfully.');
        setState(() => _statusMessage = 'Config updated successfully.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration updated successfully.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('EXAMPLE Error: Failed to update config: $e');
      if (mounted) {
        setState(() => _statusMessage = 'Failed to update config: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update config: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced Cache Management')),
      resizeToAvoidBottomInset: false,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text('Select Video:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<int>(
                    value: _selectedIndex,
                    isExpanded: true,
                    items: List.generate(
                      _videoUrls.length,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(_videoUrls[i].title),
                      ),
                    ),
                    onChanged: (i) {
                      if (i == null) return;
                      setState(() => _selectedIndex = i);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete),
                  label: const Text('Remove Selected'),
                  onPressed: () {
                     _deleteCacheFile(_videoUrls[_selectedIndex].url);
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.redAccent),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Clear All'),
                  onPressed: _clearAllCache,
                ),
              ],
            ),
            const Divider(height: 25),
            Text('Global Configuration:',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            _ConfigSlider(
              label: 'Max Cache Size',
              value: _maxCacheSizeMB,
              min: 50,
              max: 2000,
              suffix: ' MB',
              onChanged: (v) => setState(() => _maxCacheSizeMB = v),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _updateConfig,
                child: const Text('Apply Configuration'),
              ),
            ),
            const Divider(height: 25),
            Text('Status:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_statusMessage.isEmpty ? 'Ready' : _statusMessage),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigSlider extends StatelessWidget {
  const _ConfigSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toInt()}$suffix', style: const TextStyle(fontSize: 13)),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
