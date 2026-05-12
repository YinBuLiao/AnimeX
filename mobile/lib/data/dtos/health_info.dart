class HealthInfo {
  final String version;
  final bool installed;
  final bool mikanConfigured;
  final bool mysqlReady;
  final bool pikpakConfigured;
  final String storageProvider;

  const HealthInfo({
    required this.version,
    required this.installed,
    this.mikanConfigured = false,
    this.mysqlReady = false,
    this.pikpakConfigured = false,
    this.storageProvider = '',
  });

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
        version: (j['version'] as String?) ?? '',
        installed: (j['installed'] as bool?) ?? false,
        mikanConfigured: (j['mikan_configured'] as bool?) ?? false,
        mysqlReady: (j['mysql_ready'] as bool?) ?? false,
        pikpakConfigured: (j['pikpak_configured'] as bool?) ?? false,
        storageProvider: (j['storage_provider'] as String?) ?? '',
      );
}
