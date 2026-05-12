import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/system_repository.dart';

Dio _newDio() => buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );

void main() {
  test('health() returns parsed HealthInfo on 200', () async {
    final dio = _newDio();
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(200, {'ok': true, 'version': 'v0.2', 'installed': true}),
    );
    final repo = SystemRepository(dio);
    final h = await repo.health();
    expect(h.version, 'v0.2');
    expect(h.installed, isTrue);
  });

  test('health() throws ApiException on 500 response', () async {
    final dio = _newDio();
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(500, {'error': 'boom'}),
    );
    final repo = SystemRepository(dio);
    await expectLater(repo.health(), throwsA(isA<ApiException>()));
  });
}
