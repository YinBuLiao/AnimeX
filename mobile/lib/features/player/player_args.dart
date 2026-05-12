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

  const PlayerArgs({
    required this.url,
    required this.fileId,
    required this.title,
    required this.bangumiTitle,
    this.episode,
    this.coverUrl,
    this.initialPositionSec = 0,
    this.localPath,
  });
}
