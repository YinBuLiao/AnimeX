import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/subscription_repository.dart';

void main() {
  late Dio dio;
  setUp(() {
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
  });

  test('subscribe() POSTs title + optional fields and returns on 200',
      () async {
    DioAdapter(dio: dio).onPost(
      '/api/mikan/subscribe',
      (s) => s.reply(200, {'ok': true}),
      data: {
        'subject_id': 3899,
        'title': '尖帽子的魔法工房',
        'cover_url': 'http://x/c.jpg',
        'summary': 'plot',
        'language': 0,
      },
    );
    final repo = SubscriptionRepository(dio);
    await repo.subscribe(
      title: '尖帽子的魔法工房',
      subjectId: 3899,
      coverUrl: 'http://x/c.jpg',
      summary: 'plot',
    );
  });

  test('subscribe() throws ApiException on 400 (mikan未配置)', () async {
    DioAdapter(dio: dio).onPost(
      '/api/mikan/subscribe',
      (s) => s.reply(400, {'ok': false, 'error': 'Mikan 用户名或密码未配置'}),
      data: {'title': 'X', 'language': 0},
    );
    final repo = SubscriptionRepository(dio);
    try {
      await repo.subscribe(title: 'X');
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 400);
      expect(e.message, 'Mikan 用户名或密码未配置');
    }
  });
}
