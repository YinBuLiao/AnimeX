import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/discover_repository.dart';

void main() {
  late Dio dio;
  setUp(() {
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
  });

  group('DiscoverRepository.bangumiDiscover', () {
    test('returns parsed page on 200', () async {
      DioAdapter(dio: dio).onGet(
        '/api/bangumi/discover',
        (s) => s.reply(200, {
          'limit': 24,
          'offset': 0,
          'has_more': true,
          'subjects': [
            {'id': 1, 'title': 'A', 'score': 8.5},
          ],
        }),
        queryParameters: {'offset': 0, 'limit': 24},
      );
      final repo = DiscoverRepository(dio);
      final page = await repo.bangumiDiscover();
      expect(page.subjects.first.id, 1);
      expect(page.subjects.first.score, 8.5);
      expect(page.hasMore, isTrue);
    });

    test('passes offset+limit query params', () async {
      DioAdapter(dio: dio).onGet(
        '/api/bangumi/discover',
        (s) => s.reply(200, {
          'limit': 12, 'offset': 24, 'has_more': false, 'subjects': []
        }),
        queryParameters: {'offset': 24, 'limit': 12},
      );
      final repo = DiscoverRepository(dio);
      final page = await repo.bangumiDiscover(offset: 24, limit: 12);
      expect(page.subjects, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('throws ApiException on backend 502', () async {
      DioAdapter(dio: dio).onGet(
        '/api/bangumi/discover',
        (s) => s.reply(502, {'ok': false, 'error': 'upstream down'}),
        queryParameters: {'offset': 0, 'limit': 24},
      );
      final repo = DiscoverRepository(dio);
      try {
        await repo.bangumiDiscover();
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 502);
        expect(e.message, 'upstream down');
      }
    });
  });

  group('DiscoverRepository.mikanSchedule', () {
    test('returns parsed schedule on 200', () async {
      DioAdapter(dio: dio).onGet(
        '/api/mikan/schedule',
        (s) => s.reply(200, {
          'year': 2026,
          'season': '春',
          'days': [
            {'weekday': 1, 'label': 'Mon', 'items': []},
          ],
        }),
      );
      final repo = DiscoverRepository(dio);
      final sch = await repo.mikanSchedule();
      expect(sch.year, 2026);
      expect(sch.days, hasLength(1));
    });
  });

  group('DiscoverRepository.search', () {
    test('passes q query param and returns results', () async {
      DioAdapter(dio: dio).onGet(
        '/api/search',
        (s) => s.reply(200, {
          'results': [
            {'title': 'X', 'torrent_url': 'https://t/x.torrent'},
          ],
          'query': 'foo',
        }),
        queryParameters: {'q': 'foo'},
      );
      final repo = DiscoverRepository(dio);
      final resp = await repo.search('foo');
      expect(resp.query, 'foo');
      expect(resp.results.first.title, 'X');
    });
  });
}
