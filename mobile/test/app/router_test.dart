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
      );
      expect(r, '/login');
    });

    test('routes to /login when session has empty token', () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: const StoredSession(
            token: '', username: 'u', role: 'user', expiresAtSec: 0),
      );
      expect(r, '/login');
    });

    test('routes to / (home) when both server and session present', () {
      final r = decideStartRoute(
        config: const ServerConfig(baseUrl: 'https://x'),
        session: const StoredSession(
            token: 't', username: 'u', role: 'user', expiresAtSec: 0),
      );
      expect(r, '/');
    });
  });
}
