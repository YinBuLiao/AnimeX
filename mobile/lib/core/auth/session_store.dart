import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  final String token;
  final String username;
  final String role;
  final int expiresAtSec;

  const StoredSession({
    required this.token,
    required this.username,
    required this.role,
    required this.expiresAtSec,
  });

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        'role': role,
        'expires_at': expiresAtSec,
      };

  factory StoredSession.fromJson(Map<String, dynamic> j) => StoredSession(
        token: j['token'] as String,
        username: j['username'] as String,
        role: j['role'] as String,
        expiresAtSec: (j['expires_at'] as num).toInt(),
      );
}

abstract class SessionStore {
  Future<StoredSession?> load();
  Future<void> save(StoredSession s);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  static const _key = 'session';
  final FlutterSecureStorage _storage;
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<StoredSession?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    return StoredSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(StoredSession s) =>
      _storage.write(key: _key, value: jsonEncode(s.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class InMemorySessionStore implements SessionStore {
  StoredSession? _current;
  @override
  Future<StoredSession?> load() async => _current;
  @override
  Future<void> save(StoredSession s) async => _current = s;
  @override
  Future<void> clear() async => _current = null;
}
