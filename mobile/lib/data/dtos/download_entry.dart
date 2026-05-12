enum DownloadStatus { queued, running, paused, complete, failed, canceled }

DownloadStatus parseDownloadStatus(String? v) {
  switch (v) {
    case 'queued':
      return DownloadStatus.queued;
    case 'running':
      return DownloadStatus.running;
    case 'paused':
      return DownloadStatus.paused;
    case 'complete':
      return DownloadStatus.complete;
    case 'failed':
      return DownloadStatus.failed;
    case 'canceled':
      return DownloadStatus.canceled;
  }
  return DownloadStatus.queued;
}

class DownloadEntry {
  /// Stable identifier (the file_id used by /api/stream).
  final String fileId;
  final String bangumiTitle;
  final String? episode;
  final String fileName;
  final String? coverUrl;

  /// Source URL the downloader pulls from. Stored so resume works without
  /// having to re-resolve the library entry.
  final String url;

  /// File path under the application documents directory. Always set once the
  /// task is created, but the file may not exist until status==complete.
  final String localPath;

  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;
  final String? errorMessage;
  final int updatedAt;

  const DownloadEntry({
    required this.fileId,
    required this.bangumiTitle,
    this.episode,
    required this.fileName,
    this.coverUrl,
    required this.url,
    required this.localPath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.queued,
    this.errorMessage,
    required this.updatedAt,
  });

  double get progress {
    if (totalBytes <= 0) return 0;
    final p = downloadedBytes / totalBytes;
    return p.clamp(0.0, 1.0);
  }

  bool get isComplete => status == DownloadStatus.complete;

  DownloadEntry copyWith({
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    String? errorMessage,
    int? updatedAt,
  }) =>
      DownloadEntry(
        fileId: fileId,
        bangumiTitle: bangumiTitle,
        episode: episode,
        fileName: fileName,
        coverUrl: coverUrl,
        url: url,
        localPath: localPath,
        totalBytes: totalBytes ?? this.totalBytes,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        'bangumi_title': bangumiTitle,
        if (episode != null) 'episode': episode,
        'file_name': fileName,
        if (coverUrl != null) 'cover_url': coverUrl,
        'url': url,
        'local_path': localPath,
        'total_bytes': totalBytes,
        'downloaded_bytes': downloadedBytes,
        'status': status.name,
        if (errorMessage != null) 'error_message': errorMessage,
        'updated_at': updatedAt,
      };

  factory DownloadEntry.fromJson(Map<String, dynamic> j) => DownloadEntry(
        fileId: (j['file_id'] ?? '').toString(),
        bangumiTitle: (j['bangumi_title'] ?? '').toString(),
        episode: j['episode'] as String?,
        fileName: (j['file_name'] ?? '').toString(),
        coverUrl: j['cover_url'] as String?,
        url: (j['url'] ?? '').toString(),
        localPath: (j['local_path'] ?? '').toString(),
        totalBytes: (j['total_bytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (j['downloaded_bytes'] as num?)?.toInt() ?? 0,
        status: parseDownloadStatus(j['status'] as String?),
        errorMessage: j['error_message'] as String?,
        updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
      );
}

/// Strip characters illegal on FAT/exFAT/macOS HFS+ paths.
String sanitizeFilename(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  if (cleaned.isEmpty) return '_';
  // Avoid empty / reserved trailing dots on Windows-style paths.
  return cleaned.replaceAll(RegExp(r'\.+$'), '');
}

/// Compute the on-disk path for a download under [appDocsDir]:
///   <appDocsDir>/AnimeX/<sanitized bangumi>/<sanitized filename>
String buildDownloadPath({
  required String appDocsDir,
  required String bangumiTitle,
  required String fileName,
}) {
  final bangumiSeg = sanitizeFilename(bangumiTitle);
  final fileSeg = sanitizeFilename(fileName);
  return '$appDocsDir/AnimeX/$bangumiSeg/$fileSeg';
}
