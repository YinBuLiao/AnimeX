class NotificationEntry {
  static const String kindNewEpisode = 'new_episode';
  static const String kindRequestApproved = 'request_approved';
  static const String kindGeneric = 'generic';

  final String id;
  final String kind;
  final String title;
  final String body;
  final String? bangumiTitle;
  final String? episode;
  final String? coverUrl;
  final String? fileId;
  final int createdAt;

  const NotificationEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.bangumiTitle,
    this.episode,
    this.coverUrl,
    this.fileId,
  });

  factory NotificationEntry.fromJson(Map<String, dynamic> json) {
    return NotificationEntry(
      id: (json['id'] ?? '').toString(),
      kind: (json['kind'] ?? kindGeneric).toString(),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      bangumiTitle: json['bangumi_title']?.toString(),
      episode: json['episode']?.toString(),
      coverUrl: json['cover_url']?.toString(),
      fileId: json['file_id']?.toString(),
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

class NotificationsResponse {
  final List<NotificationEntry> entries;
  const NotificationsResponse(this.entries);

  factory NotificationsResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['entries'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(NotificationEntry.fromJson)
        .toList();
    return NotificationsResponse(list);
  }
}
