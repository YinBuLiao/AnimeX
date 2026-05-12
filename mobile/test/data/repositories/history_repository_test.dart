import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/dtos/history_entry.dart';
import 'package:animex_mobile/data/repositories/history_repository.dart';

void main() {
  late Dio dio;
  setUp(() {
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
  });

  test('list() parses entries', () async {
    DioAdapter(dio: dio).onGet(
      '/api/history',
      (s) => s.reply(200, {
        'entries': [
          {
            'file_id': 'f1',
            'bangumi_title': 'Frieren',
            'episode': '01',
            'position_sec': 120,
            'duration_sec': 1440,
            'updated_at': 1700000000,
          }
        ],
      }),
    );
    final resp = await HistoryRepository(dio).list();
    expect(resp.entries, hasLength(1));
    expect(resp.entries.first.fileId, 'f1');
    expect(resp.entries.first.positionSec, 120);
    expect(resp.entries.first.updatedAt, 1700000000);
  });

  test('report() PUTs entry payload and returns merged list', () async {
    DioAdapter(dio: dio).onPut(
      '/api/history',
      (s) => s.reply(200, {
        'entries': [
          {
            'file_id': 'f1',
            'bangumi_title': 'Frieren',
            'position_sec': 300,
            'duration_sec': 1440,
            'updated_at': 1700000300,
          }
        ],
      }),
      data: {
        'file_id': 'f1',
        'bangumi_title': 'Frieren',
        'episode': '01',
        'position_sec': 300,
        'duration_sec': 1440,
      },
    );
    final entry = HistoryEntry(
      fileId: 'f1',
      bangumiTitle: 'Frieren',
      episode: '01',
      positionSec: 300,
      durationSec: 1440,
      updatedAt: 0,
    );
    final resp = await HistoryRepository(dio).report(entry);
    expect(resp.entries.first.positionSec, 300);
  });

  test('list() surfaces non-2xx as ApiException', () async {
    DioAdapter(dio: dio).onGet(
      '/api/history',
      (s) => s.reply(500, {'ok': false, 'error': 'boom'}),
    );
    try {
      await HistoryRepository(dio).list();
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 500);
      expect(e.message, 'boom');
    }
  });
}
