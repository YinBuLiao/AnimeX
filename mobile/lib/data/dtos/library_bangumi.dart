class PlayableFile {
  final String id;
  final String name;
  final int size;
  final String? mimeType;
  final String? thumbnailUrl;
  final String streamUrl;

  const PlayableFile({
    required this.id,
    required this.name,
    required this.size,
    required this.streamUrl,
    this.mimeType,
    this.thumbnailUrl,
  });

  factory PlayableFile.fromJson(Map<String, dynamic> j) => PlayableFile(
        id: j['id'] as String,
        name: j['name'] as String,
        size: (j['size'] as num?)?.toInt() ?? 0,
        streamUrl: j['stream_url'] as String? ?? '',
        mimeType: j['mime_type'] as String?,
        thumbnailUrl: j['thumbnail_url'] as String?,
      );
}

class Episode {
  final String id;
  final String label;
  final List<PlayableFile> files;

  const Episode({
    required this.id,
    required this.label,
    required this.files,
  });

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        id: j['id'] as String,
        label: j['label'] as String,
        files: ((j['files'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => PlayableFile.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class LibraryBangumi {
  final String id;
  final String title;
  final String? coverUrl;
  final String? summary;
  final List<Episode> episodes;

  const LibraryBangumi({
    required this.id,
    required this.title,
    this.coverUrl,
    this.summary,
    this.episodes = const <Episode>[],
  });

  factory LibraryBangumi.fromJson(Map<String, dynamic> j) => LibraryBangumi(
        id: j['id'] as String,
        title: j['title'] as String,
        coverUrl: j['cover_url'] as String?,
        summary: j['summary'] as String?,
        episodes: ((j['episodes'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class LibraryResponse {
  final List<LibraryBangumi> bangumi;

  const LibraryResponse({required this.bangumi});

  factory LibraryResponse.fromJson(Map<String, dynamic> j) => LibraryResponse(
        bangumi: ((j['bangumi'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => LibraryBangumi.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
}
