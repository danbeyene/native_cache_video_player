import 'package:native_cache_video_player/native_cache_video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pages/advance_cache_management_page.dart';
import 'pages/asset_playback_page.dart';
import 'pages/basic_playback_page.dart';
import 'pages/chewie_integration_page.dart';
import 'pages/tiktok_style_page.dart';

/// Main entry point for the demo application.
/// 
/// Initializes the Flutter bindings and clears the cache in debug mode to ensure 
/// a fresh start for testing and demonstration.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if(kDebugMode){
    await NativeCacheVideoPlayer.clearAllCache();
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>{
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Cache Video Player Demo',
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

/// The home screen of the demo application, providing navigation to various feature demonstrations.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native Cache Video Player'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Native Cache Video Player Demo',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Explore the comprehensive features of the Native Cache Video Player library. '
                        'Each example demonstrates specific capabilities and integration patterns for '
                        'robust video playback and optimized resource management.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth > 700 ? 2 : 1;
                    final childAspectRatio =
                        constraints.maxWidth > 1000 ? 4.5 : 3.14;

                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      childAspectRatio: childAspectRatio,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      children: [
                        _FeatureCard(
                          title: 'Basic Playback',
                          subtitle:
                              'Network video streaming with automatic caching.',
                          icon: Icons.play_circle,
                          color: Colors.blue,
                          onTap: () =>
                              _navigateTo(context, const BasicPlaybackPage()),
                        ),
                        _FeatureCard(
                          title: 'Vertical Feed',
                          subtitle: 'TikTok-style vertical video feed with auto-cache.',
                          icon: Icons.unfold_more,
                          color: Colors.pink,
                          onTap: () => _navigateTo(
                            context,
                            const TikTokStylePage(),
                          ),
                        ),
                        _FeatureCard(
                          title: 'Chewie Integration',
                          subtitle:
                              'Advanced UI integration using the Chewie player.',
                          icon: Icons.video_library,
                          color: Colors.orange,
                          onTap: () => _navigateTo(
                            context,
                            const ChewieIntegrationPage(),
                          ),
                        ),

                        _FeatureCard(
                          title: 'Cache Management',
                          subtitle:
                              'Administrative tools for storage and cache control.',
                          icon: Icons.storage,
                          color: Colors.red,
                          onTap: () => _navigateTo(
                            context,
                            const AdvanceCacheManagementPage(),
                          ),
                        ),
                        _FeatureCard(
                          title: 'Asset Playback',
                          subtitle:
                              'Playback of locally bundled video resources.',
                          icon: Icons.video_file,
                          color: Colors.teal,
                          onTap: () => _navigateTo(
                            context,
                            const AssetPlaybackPage(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => page));
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(context).dividerColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
