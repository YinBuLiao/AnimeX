import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/app/router.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';

void main() {
  group('decideStartRoute', () {
    test('routes to /setup when no server URL configured', () {
      final r = decideStartRoute(
        config: const ServerConfig(),
        session: null,
      );
      expect(r, '/setup');
    });

    test('routes to /login when server configured but no session', () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: null,
        requireLogin: true,
      );
      expect(r, '/login');
    });

    test('routes to / when server does not require login and no session exists',
        () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: null,
        requireLogin: false,
      );
      expect(r, '/');
    });

    test('routes to /login when session has empty token', () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: const StoredSession(
            token: '', username: 'u', role: 'user', expiresAtSec: 0),
        requireLogin: true,
      );
      expect(r, '/login');
    });

    test('routes to / when server does not require login and token is empty',
        () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: const StoredSession(
            token: '', username: 'u', role: 'user', expiresAtSec: 0),
        requireLogin: false,
      );
      expect(r, '/');
    });

    test('routes to / (home) when both server and session present', () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: const StoredSession(
            token: 't', username: 'u', role: 'user', expiresAtSec: 0),
      );
      expect(r, '/');
    });

    test('routes to /login when token has expired', () {
      final now = DateTime.utc(2026, 5, 12, 12, 0, 0);
      // expiresAtSec is one second in the past
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: StoredSession(
            token: 't',
            username: 'u',
            role: 'user',
            expiresAtSec: now.millisecondsSinceEpoch ~/ 1000 - 1),
        clock: () => now,
      );
      expect(r, '/login');
    });

    test('stays at / when token expires in the future', () {
      final now = DateTime.utc(2026, 5, 12, 12, 0, 0);
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: StoredSession(
            token: 't',
            username: 'u',
            role: 'user',
            expiresAtSec: now.millisecondsSinceEpoch ~/ 1000 + 60),
        clock: () => now,
      );
      expect(r, '/');
    });
  });
}
