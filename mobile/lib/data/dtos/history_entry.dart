class HistoryEntry {
  final String fileId;
  final String? url;
  final String bangumiTitle;
  final String? episode;
  final String? coverUrl;
  final int positionSec;
  final int durationSec;
  final int updatedAt;

  const HistoryEntry({
    required this.fileId,
    this.url,
    required this.bangumiTitle,
    this.episode,
    this.coverUrl,
    required this.positionSec,
    required this.durationSec,
    required this.updatedAt,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        fileId: (j['file_id'] ?? '').toString(),
        url: (j['url'] as String?)?.trim().isEmpty == true
            ? null
            : j['url'] as String?,
        bangumiTitle: (j['bangumi_title'] ?? '').toString(),
        episode: (j['episode'] as String?)?.trim().isEmpty == true
            ? null
            : j['episode'] as String?,
        coverUrl: (j['cover_url'] as String?)?.trim().isEmpty == true
            ? null
            : j['cover_url'] as String?,
        positionSec: (j['position_sec'] as num?)?.toInt() ?? 0,
        durationSec: (j['duration_sec'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        if (url != null) 'url': url,
        'bangumi_title': bangumiTitle,
        if (episode != null) 'episode': episode,
        if (coverUrl != null) 'cover_url': coverUrl,
        'position_sec': positionSec,
        'duration_sec': durationSec,
        if (updatedAt > 0) 'updated_at': updatedAt,
      };
}

class HistoryResponse {
  final List<HistoryEntry> entries;
  const HistoryResponse({required this.entries});

  factory HistoryResponse.fromJson(Map<String, dynamic> j) => HistoryResponse(
        entries: ((j['entries'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(HistoryEntry.fromJson)
            .toList(),
      );
}
