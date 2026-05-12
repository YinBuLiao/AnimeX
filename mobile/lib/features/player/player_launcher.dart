import 'package:animex_mobile/core/download/download_manager.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/features/player/player_args.dart';

/// Joins a base URL with a relative or absolute path. Mirrors the rule used
/// by media_kit's HTTP loader: absolute URLs pass through unchanged.
String absoluteUrl(String base, String path) {
  if (path.isEmpty) return base;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  if (path.startsWith('/')) return '$base$path';
  return '$base/$path';
}

/// Builds a [PlayerArgs] with the full bangumi playlist resolved, so the
/// player can auto-advance through the season once the user picks any
/// episode.
///
/// Returns null when [baseUrl] is empty or the bangumi has no playable
/// episodes — the caller should fall back to a single-shot args.
PlayerArgs? buildBangumiArgs({
  required LibraryBangumi bangumi,
  required String selectedFileId,
  required String baseUrl,
  required DownloadManager downloads,
  int initialPositionSec = 0,
  String? coverUrlFallback,
}) {
  if (baseUrl.isEmpty) return null;
  final playlist = <PlayerArgs>[];
  for (final ep in bangumi.episodes) {
    if (ep.files.isEmpty) continue;
    final f = ep.files.first;
    final dl = downloads.entryFor(f.id);
    playlist.add(PlayerArgs(
      url: absoluteUrl(baseUrl, f.streamUrl),
      fileId: f.id,
      title: '${bangumi.title} · ${ep.label}',
      bangumiTitle: bangumi.title,
      episode: ep.label,
      coverUrl: bangumi.coverUrl ?? coverUrlFallback,
      localPath: dl?.isComplete == true ? dl!.localPath : null,
    ));
  }
  if (playlist.isEmpty) return null;
  var idx = playlist.indexWhere((a) => a.fileId == selectedFileId);
  if (idx < 0) idx = 0;
  final base = playlist[idx];
  return PlayerArgs(
    url: base.url,
    fileId: base.fileId,
    title: base.title,
    bangumiTitle: base.bangumiTitle,
    episode: base.episode,
    coverUrl: base.coverUrl,
    initialPositionSec: initialPositionSec,
    localPath: base.localPath,
    playlist: playlist,
    currentIndex: idx,
  );
}
