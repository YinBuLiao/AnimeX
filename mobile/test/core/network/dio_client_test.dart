import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/dio_client.dart';

/// Simple interceptor that captures the last request's headers for assertions.
class _CapturingInterceptor extends Interceptor {
  Map<String, dynamic>? capturedHeaders;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedHeaders = Map<String, dynamic>.from(options.headers);
    handler.next(options);
  }
}

void main() {
  test('dio is configured with the server base URL', () {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example:8080'),
      sessionStore: InMemorySessionStore(),
    );
    expect(dio.options.baseUrl, 'https://server.example:8080');
  });

  test('auth interceptor injects Bearer header when session exists', () async {
    final sessions = InMemorySessionStore();
    await sessions.save(const StoredSession(
        token: 'my-token', username: 'a', role: 'user', expiresAtSec: 0));
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: sessions,
    );
    final capture = _CapturingInterceptor();
    dio.interceptors.add(capture);
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/auth/me', (server) {
      server.reply(200, {'ok': true, 'username': 'a', 'role': 'user'});
    });

    final resp = await dio.get('/api/auth/me');
    expect(resp.statusCode, 200);

    expect(capture.capturedHeaders?['Authorization'], 'Bearer my-token');
  });

  test('auth interceptor omits Bearer header when no session', () async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    final capture = _CapturingInterceptor();
    dio.interceptors.add(capture);
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/health', (s) => s.reply(200, {'ok': true}));
    await dio.get('/api/health');
    expect(
        capture.capturedHeaders?.containsKey('Authorization'), isFalse);
  });

  test('401 response surfaces as ApiException with isUnauthorized=true',
      () async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/auth/me',
        (s) => s.reply(401, {'ok': false, 'error': 'nope'}));
    try {
      await dio.get('/api/auth/me');
      fail('expected DioException');
    } on DioException catch (e) {
      final api = e.toApi();
      expect(api.statusCode, 401);
      expect(api.isUnauthorized, isTrue);
      expect(api.message, 'nope');
    }
  });

  test('401 on a non-login endpoint fires onUnauthorized callback', () async {
    var hits = 0;
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
      onUnauthorized: () => hits++,
    );
    final adapter = DioAdapter(dio: dio);
    adapter.onGet('/api/auth/me',
        (s) => s.reply(401, {'ok': false, 'error': 'gone'}));
    try {
      await dio.get('/api/auth/me');
    } on DioException catch (_) {
      // expected
    }
    expect(hits, 1);
  });

  test('401 from mobile-login does NOT fire onUnauthorized', () async {
    var hits = 0;
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
      onUnauthorized: () => hits++,
    );
    final adapter = DioAdapter(dio: dio);
    adapter.onPost('/api/auth/mobile-login',
        (s) => s.reply(401, {'ok': false, 'error': 'bad password'}));
    try {
      await dio.post('/api/auth/mobile-login',
          data: {'username': 'x', 'password': 'y'});
    } on DioException catch (_) {
      // expected
    }
    expect(hits, 0);
  });
}
