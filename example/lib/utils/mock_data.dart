class VideoInfo {
  final String title;
  final String url;

  const VideoInfo({required this.title, required this.url});
}

class MockData {
  static const List<VideoInfo> videoUrls = [
    VideoInfo(
      title: 'Big Buck Bunny (10s)',
      url: 'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_30MB.mp4',
    ),
    VideoInfo(
      title: 'Jellyfish (10s)',
      url: 'https://test-videos.co.uk/vids/jellyfish/mp4/h264/1080/Jellyfish_1080_10s_30MB.mp4',
    ),
    VideoInfo(
      title: 'Sintel (10s)',
      url: 'https://test-videos.co.uk/vids/sintel/mp4/h264/1080/Sintel_1080_10s_30MB.mp4',
    ),
    VideoInfo(
      title: 'Big Buck Bunny (Short)',
      url: 'https://www.w3schools.com/tags/mov_bbb.mp4',
    ),
    VideoInfo(
      title: 'Playdoh Overview',
      url: 'https://videos.cdn.mozilla.net/serv/flux/playdoh/playdoh-overview.mp4',
    ),
    VideoInfo(
      title: 'Bee',
      url: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    ),
    VideoInfo(
      title: 'Butterfly',
      url: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    ),
    VideoInfo(
      title: 'Nature 05',
      url: 'https://github.com/albemala/native_video_player/raw/refs/heads/main/example/assets/video/05.mp4',
    ),
    VideoInfo(
      title: 'Nature 06',
      url: 'https://github.com/albemala/native_video_player/raw/refs/heads/main/example/assets/video/06.mp4',
    ),
    VideoInfo(
      title: 'BBB 1080p 30s',
      url: 'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-1080p-30sec.mp4',
    ),
    VideoInfo(
      title: 'BBB 1080p 60fps',
      url: 'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-1080p-60fps-30sec.mp4',
    ),
    VideoInfo(
      title: 'BBB 480p 30s',
      url: 'https://raw.githubusercontent.com/chthomos/video-media-samples/master/big-buck-bunny-480p-30sec.mp4',
    ),
  ];
}
