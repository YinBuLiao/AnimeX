import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/notifications_repository.dart';

void main() {
  late Dio dio;
  setUp(() {
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
  });

  test('list() parses notification entries', () async {
    DioAdapter(dio: dio).onGet(
      '/api/notifications',
      (s) => s.reply(200, {
        'entries': [
          {
            'id': 'n1',
            'kind': 'new_episode',
            'title': '新剧集',
            'body': 'Frieren · 12',
            'bangumi_title': 'Frieren',
            'episode': '12',
            'created_at': 1700000000,
          }
        ],
      }),
    );
    final resp = await NotificationsRepository(dio).list();
    expect(resp.entries, hasLength(1));
    expect(resp.entries.first.kind, 'new_episode');
    expect(resp.entries.first.bangumiTitle, 'Frieren');
  });

  test('list(since:) forwards query param', () async {
    DioAdapter(dio: dio).onGet(
      '/api/notifications',
      (s) => s.reply(200, {'entries': []}),
      queryParameters: {'since': 1700000000},
    );
    final resp = await NotificationsRepository(dio).list(since: 1700000000);
    expect(resp.entries, isEmpty);
  });

  test('registerDevice() POSTs token and platform', () async {
    DioAdapter(dio: dio).onPost(
      '/api/devices/register',
      (s) => s.reply(200, {'ok': true}),
      data: {'fcm_token': 'tok-1', 'platform': 'android'},
    );
    await NotificationsRepository(dio).registerDevice(
      fcmToken: 'tok-1',
      platform: 'android',
    );
  });

  test('unregisterDevice() POSTs token', () async {
    DioAdapter(dio: dio).onPost(
      '/api/devices/unregister',
      (s) => s.reply(200, {'ok': true}),
      data: {'fcm_token': 'tok-1'},
    );
    await NotificationsRepository(dio).unregisterDevice('tok-1');
  });

  test('list() surfaces non-2xx as ApiException', () async {
    DioAdapter(dio: dio).onGet(
      '/api/notifications',
      (s) => s.reply(500, {'ok': false, 'error': 'boom'}),
    );
    try {
      await NotificationsRepository(dio).list();
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 500);
    }
  });
}
