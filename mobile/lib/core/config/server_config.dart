import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ServerConfig {
  final String baseUrl;
  final bool allowSelfSigned;

  const ServerConfig({this.baseUrl = '', this.allowSelfSigned = false});

  bool get isComplete => baseUrl.isNotEmpty;

  static ServerConfig normalize(String raw, {bool allowSelfSigned = false}) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      throw const FormatException('URL must start with http:// or https://');
    }
    var url = trimmed;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return ServerConfig(baseUrl: url, allowSelfSigned: allowSelfSigned);
  }
}

abstract class ServerConfigStore {
  Future<ServerConfig> load();
  Future<void> save(ServerConfig config);
  Future<void> clear();
}

class SecureServerConfigStore implements ServerConfigStore {
  static const _kBaseUrl = 'server_url';
  static const _kAllowSelfSigned = 'allow_self_signed_cert';

  final FlutterSecureStorage _storage;
  SecureServerConfigStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<ServerConfig> load() async {
    final url = await _storage.read(key: _kBaseUrl) ?? '';
    final flag = await _storage.read(key: _kAllowSelfSigned);
    return ServerConfig(baseUrl: url, allowSelfSigned: flag == '1');
  }

  @override
  Future<void> save(ServerConfig c) async {
    await _storage.write(key: _kBaseUrl, value: c.baseUrl);
    await _storage.write(key: _kAllowSelfSigned, value: c.allowSelfSigned ? '1' : '0');
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _kBaseUrl);
    await _storage.delete(key: _kAllowSelfSigned);
  }
}

class InMemoryServerConfigStore implements ServerConfigStore {
  ServerConfig _current = const ServerConfig();
  @override
  Future<ServerConfig> load() async => _current;
  @override
  Future<void> save(ServerConfig c) async {
    _current = c;
  }
  @override
  Future<void> clear() async {
    _current = const ServerConfig();
  }
}
