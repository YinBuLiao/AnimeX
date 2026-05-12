import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/library_repository.dart';

void main() {
  late Dio dio;
  setUp(() {
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
  });

  test('library() returns parsed response on 200', () async {
    DioAdapter(dio: dio).onGet(
      '/api/library',
      (s) => s.reply(200, {
        'bangumi': [
          {
            'id': 'b1',
            'title': 'Fate',
            'cover_url': 'http://x/c.jpg',
            'episodes': [
              {
                'id': 'ep1',
                'label': '01',
                'files': [
                  {
                    'id': 'f1',
                    'name': 'ep1.mkv',
                    'size': 100,
                    'stream_url': '/api/stream?id=f1'
                  }
                ]
              }
            ]
          }
        ]
      }),
    );
    final repo = LibraryRepository(dio);
    final lib = await repo.library();
    expect(lib.bangumi.first.id, 'b1');
    expect(lib.bangumi.first.episodes.first.files.first.streamUrl,
        '/api/stream?id=f1');
  });

  test('library() surfaces 403 as ApiException (non-admin without snapshot)',
      () async {
    DioAdapter(dio: dio).onGet(
      '/api/library',
      (s) => s.reply(403, {'ok': false, 'error': '媒体库快照不可用'}),
    );
    final repo = LibraryRepository(dio);
    try {
      await repo.library();
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 403);
      expect(e.message, '媒体库快照不可用');
    }
  });
}
