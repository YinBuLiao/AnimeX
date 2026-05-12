class AdminOverviewCard {
  final String label;
  final String value;
  final String trend;
  final String icon;

  const AdminOverviewCard({
    required this.label,
    required this.value,
    required this.trend,
    required this.icon,
  });

  factory AdminOverviewCard.fromJson(Map<String, dynamic> json) {
    return AdminOverviewCard(
      label: (json['label'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
      trend: (json['trend'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
    );
  }
}

class AdminOverview {
  final List<AdminOverviewCard> cards;
  final String storageProvider;
  final String libraryUpdatedAt;

  const AdminOverview({
    required this.cards,
    required this.storageProvider,
    required this.libraryUpdatedAt,
  });

  factory AdminOverview.fromJson(Map<String, dynamic> json) {
    final cards = (json['cards'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AdminOverviewCard.fromJson)
        .toList();
    return AdminOverview(
      cards: cards,
      storageProvider: (json['storage_provider'] ?? '').toString(),
      libraryUpdatedAt: (json['library_updated_at'] ?? '').toString(),
    );
  }
}

class AdminMonitor {
  final String uptime;
  final int goroutines;
  final int memoryAlloc;
  final int memorySys;
  final bool mysqlReady;
  final bool redisReady;
  final bool pikpakReady;
  final bool storageReady;
  final String storageProvider;
  final bool installed;
  final bool installOnly;

  const AdminMonitor({
    required this.uptime,
    required this.goroutines,
    required this.memoryAlloc,
    required this.memorySys,
    required this.mysqlReady,
    required this.redisReady,
    required this.pikpakReady,
    required this.storageReady,
    required this.storageProvider,
    required this.installed,
    required this.installOnly,
  });

  factory AdminMonitor.fromJson(Map<String, dynamic> json) {
    return AdminMonitor(
      uptime: (json['uptime'] ?? '').toString(),
      goroutines: (json['goroutines'] as num?)?.toInt() ?? 0,
      memoryAlloc: (json['memory_alloc'] as num?)?.toInt() ?? 0,
      memorySys: (json['memory_sys'] as num?)?.toInt() ?? 0,
      mysqlReady: json['mysql_ready'] == true,
      redisReady: json['redis_ready'] == true,
      pikpakReady: json['pikpak_ready'] == true,
      storageReady: json['storage_ready'] == true,
      storageProvider: (json['storage_provider'] ?? '').toString(),
      installed: json['installed'] == true,
      installOnly: json['install_only'] == true,
    );
  }
}

class AdminLogEntry {
  final String time;
  final String level;
  final String module;
  final String message;

  const AdminLogEntry({
    required this.time,
    required this.level,
    required this.module,
    required this.message,
  });

  factory AdminLogEntry.fromJson(Map<String, dynamic> json) {
    return AdminLogEntry(
      time: (json['time'] ?? '').toString(),
      level: (json['level'] ?? '').toString(),
      module: (json['module'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class AdminDownloadRequest {
  final int id;
  final String username;
  final String title;
  final String bangumiTitle;
  final String episodeLabel;
  final String status;
  final String createdAt;

  const AdminDownloadRequest({
    required this.id,
    required this.username,
    required this.title,
    required this.bangumiTitle,
    required this.episodeLabel,
    required this.status,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';

  factory AdminDownloadRequest.fromJson(Map<String, dynamic> json) {
    return AdminDownloadRequest(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: (json['username'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      bangumiTitle: (json['bangumi_title'] ?? '').toString(),
      episodeLabel: (json['episode_label'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}

class AdminUser {
  final String username;
  final String role;

  const AdminUser({required this.username, required this.role});

  bool get isAdmin => role == 'admin';

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      username: (json['username'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
    );
  }
}

class AdminInviteCode {
  final String code;
  final String usedBy;
  final String usedAt;
  final String expiresAt;
  final String createdAt;

  const AdminInviteCode({
    required this.code,
    required this.usedBy,
    required this.usedAt,
    required this.expiresAt,
    required this.createdAt,
  });

  bool get isUsed => usedBy.isNotEmpty;

  factory AdminInviteCode.fromJson(Map<String, dynamic> json) {
    return AdminInviteCode(
      code: (json['code'] ?? '').toString(),
      usedBy: (json['used_by'] ?? '').toString(),
      usedAt: (json['used_at'] ?? '').toString(),
      expiresAt: (json['expires_at'] ?? '').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}
