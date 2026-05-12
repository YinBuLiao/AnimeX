class HealthInfo {
  final String version;
  final bool installed;
  const HealthInfo({required this.version, required this.installed});

  factory HealthInfo.fromJson(Map<String, dynamic> j) => HealthInfo(
        version: (j['version'] as String?) ?? '',
        installed: (j['installed'] as bool?) ?? false,
      );
}
