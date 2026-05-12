class PlayerArgs {
  /// Absolute URL the player should open (already includes scheme + host).
  final String url;

  /// Stable file ID used as the history key.
  final String fileId;

  /// Headline shown in the player UI.
  final String title;

  /// Bangumi-level title (used in history reports).
  final String bangumiTitle;

  /// Episode label, e.g. "01".
  final String? episode;

  /// Optional cover for history poster.
  final String? coverUrl;

  /// Seconds to seek to on open (0 = start from beginning).
  final int initialPositionSec;

  /// Optional absolute filesystem path. If present and the file exists, the
  /// player opens this directly without going through the network.
  final String? localPath;

  /// Optional playlist for auto-play-next. When non-empty, the player loads
  /// `playlist[currentIndex]` and advances to `currentIndex+1` on completion
  /// if the user has the auto-play-next preference enabled.
  final List<PlayerArgs> playlist;
  final int currentIndex;

  const PlayerArgs({
    required this.url,
    required this.fileId,
    required this.title,
    required this.bangumiTitle,
    this.episode,
    this.coverUrl,
    this.initialPositionSec = 0,
    this.localPath,
    this.playlist = const <PlayerArgs>[],
    this.currentIndex = 0,
  });

  PlayerArgs? get next {
    final i = currentIndex + 1;
    if (i < 0 || i >= playlist.length) return null;
    return playlist[i];
  }

  PlayerArgs copyWithReset({int? initialPositionSec}) => PlayerArgs(
        url: url,
        fileId: fileId,
        title: title,
        bangumiTitle: bangumiTitle,
        episode: episode,
        coverUrl: coverUrl,
        initialPositionSec: initialPositionSec ?? 0,
        localPath: localPath,
        playlist: playlist,
        currentIndex: currentIndex,
      );
}
