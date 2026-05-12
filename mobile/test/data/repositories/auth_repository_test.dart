import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/auth_repository.dart';

void main() {
  late InMemorySessionStore sessions;
  late Dio dio;

  setUp(() {
    sessions = InMemorySessionStore();
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: sessions,
    );
  });

  test('login() persists session and returns user on 200', () async {
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(200, {
        'ok': true,
        'token': 'tok-1',
        'expires_at': 1700000000,
        'username': 'alice',
        'role': 'admin',
      }),
      data: {'username': 'alice', 'password': 'secret'},
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);

    final user = await repo.login('alice', 'secret');
    expect(user.username, 'alice');
    expect(user.role, 'admin');

    final stored = await sessions.load();
    expect(stored?.token, 'tok-1');
    expect(stored?.username, 'alice');
  });

  test('login() throws ApiException on 401 and does not persist session', () async {
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(401, {'ok': false, 'error': 'bad creds'}),
      data: {'username': 'a', 'password': 'b'},
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    await expectLater(repo.login('a', 'b'), throwsA(isA<ApiException>()));
    expect(await sessions.load(), isNull);
  });

  test('me() returns the current user from /api/auth/me', () async {
    await sessions.save(const StoredSession(
        token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    DioAdapter(dio: dio).onGet(
      '/api/auth/me',
      (s) => s.reply(200, {'ok': true, 'username': 'alice', 'role': 'admin'}),
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    final u = await repo.me();
    expect(u.username, 'alice');
  });

  test('logout() clears the session after a successful server call', () async {
    await sessions.save(const StoredSession(
        token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    DioAdapter(dio: dio).onPost(
      '/api/auth/logout',
      (s) => s.reply(200, {'ok': true}),
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    await repo.logout();
    expect(await sessions.load(), isNull);
  });

  test('logout() still clears the session if server returns error', () async {
    await sessions.save(const StoredSession(
        token: 't', username: 'u', role: 'user', expiresAtSec: 0));
    DioAdapter(dio: dio).onPost(
      '/api/auth/logout',
      (s) => s.reply(500, {'error': 'boom'}),
    );
    final repo = AuthRepository(dio: dio, sessions: sessions);
    await repo.logout(); // must not throw
    expect(await sessions.load(), isNull);
  });
}
