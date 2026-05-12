import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/data/dtos/bangumi_subject.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/data/dtos/mikan_schedule.dart';
import 'package:animex_mobile/data/dtos/search_result.dart';

void main() {
  group('BangumiDiscoverPage', () {
    test('parses /api/bangumi/discover sample', () {
      // Real payload sampled with curl on the docker backend.
      final json = jsonDecode('''
{
  "limit": 24, "offset": 0, "has_more": true,
  "subjects": [
    {
      "id": 1530, "title": "海豹宝宝", "name": "クプ〜!!まめゴマ!",
      "cover_url": "https://lain.bgm.tv/pic/cover/l/cb/8a/1530.jpg",
      "summary": "豆太是一只…",
      "score": 6.9, "air_date": "2009-01-10",
      "doing": 3, "collection": 23
    }
  ]
}
''') as Map<String, dynamic>;
      final page = BangumiDiscoverPage.fromJson(json);
      expect(page.limit, 24);
      expect(page.offset, 0);
      expect(page.hasMore, isTrue);
      expect(page.subjects, hasLength(1));
      final s = page.subjects.first;
      expect(s.id, 1530);
      expect(s.title, '海豹宝宝');
      expect(s.name, 'クプ〜!!まめゴマ!');
      expect(s.coverUrl, 'https://lain.bgm.tv/pic/cover/l/cb/8a/1530.jpg');
      expect(s.score, 6.9);
      expect(s.airDate, '2009-01-10');
      expect(s.doing, 3);
      expect(s.collection, 23);
    });

    test('tolerates missing optional fields', () {
      final s = BangumiSubject.fromJson(<String, dynamic>{
        'id': 1,
        'title': 'X',
      });
      expect(s.id, 1);
      expect(s.title, 'X');
      expect(s.name, isNull);
      expect(s.score, 0.0);
      expect(s.doing, 0);
    });
  });

  group('MikanSchedule', () {
    test('parses /api/mikan/schedule sample', () {
      final json = jsonDecode('''
{
  "year": 2026, "season": "春",
  "days": [
    {
      "weekday": 1, "label": "星期一",
      "items": [
        {
          "id": 3899, "title": "尖帽子的魔法工房",
          "cover_url": "https://mikanani.me/x.jpg",
          "cover_from": "mikan",
          "page_url": "https://mikanani.me/Home/Bangumi/3899",
          "updated": "2026/05/11 更新",
          "weekday": 1, "day_label": "星期一"
        }
      ]
    }
  ]
}
''') as Map<String, dynamic>;
      final sch = MikanSchedule.fromJson(json);
      expect(sch.year, 2026);
      expect(sch.season, '春');
      expect(sch.days, hasLength(1));
      final day = sch.days.first;
      expect(day.weekday, 1);
      expect(day.label, '星期一');
      expect(day.items, hasLength(1));
      final item = day.items.first;
      expect(item.id, 3899);
      expect(item.title, '尖帽子的魔法工房');
      expect(item.pageUrl, 'https://mikanani.me/Home/Bangumi/3899');
      expect(item.updated, '2026/05/11 更新');
    });
  });

  group('SearchResponse', () {
    test('parses /api/search sample', () {
      final json = jsonDecode('''
{
  "results": [
    {
      "title": "[ANi] Fate/strange Fake - 13",
      "bangumi_title": "Fate/strange Fake",
      "cover_url": "https://lain.bgm.tv/pic/cover/l/f0/51/443831.jpg",
      "summary": "魔术师与英灵…",
      "link": "https://mikanani.me/Home/Episode/abc",
      "torrent_url": "https://mikanani.me/Download/abc.torrent",
      "magnet": "magnet:?xt=urn:btih:abc",
      "size": "1.4 GB",
      "updated": "2026/05/10 22:33",
      "episode_label": "13"
    }
  ],
  "query": "fate", "matched_query": "fate strange fake"
}
''') as Map<String, dynamic>;
      final resp = SearchResponse.fromJson(json);
      expect(resp.query, 'fate');
      expect(resp.matchedQuery, 'fate strange fake');
      expect(resp.results, hasLength(1));
      final r = resp.results.first;
      expect(r.bangumiTitle, 'Fate/strange Fake');
      expect(r.torrentUrl, 'https://mikanani.me/Download/abc.torrent');
      expect(r.magnet, startsWith('magnet:'));
      expect(r.episodeLabel, '13');
    });

    test('handles empty results array', () {
      final resp = SearchResponse.fromJson(<String, dynamic>{
        'results': <dynamic>[],
      });
      expect(resp.results, isEmpty);
      expect(resp.query, isNull);
    });
  });

  group('LibraryResponse', () {
    test('parses /api/library payload', () {
      final json = jsonDecode('''
{
  "bangumi": [
    {
      "id": "bgm-1",
      "title": "Fate",
      "cover_url": "https://lain.bgm.tv/x.jpg",
      "summary": "...",
      "episodes": [
        {
          "id": "ep-1",
          "label": "01",
          "files": [
            {
              "id": "f-1",
              "name": "ep01.mkv",
              "size": 1500000000,
              "mime_type": "video/x-matroska",
              "thumbnail_url": "",
              "stream_url": "/api/stream?id=f-1"
            }
          ]
        }
      ]
    }
  ]
}
''') as Map<String, dynamic>;
      final lib = LibraryResponse.fromJson(json);
      expect(lib.bangumi, hasLength(1));
      final b = lib.bangumi.first;
      expect(b.id, 'bgm-1');
      expect(b.title, 'Fate');
      expect(b.episodes, hasLength(1));
      final ep = b.episodes.first;
      expect(ep.id, 'ep-1');
      expect(ep.label, '01');
      expect(ep.files, hasLength(1));
      final f = ep.files.first;
      expect(f.size, 1500000000);
      expect(f.streamUrl, '/api/stream?id=f-1');
      expect(f.mimeType, 'video/x-matroska');
    });

    test('handles bangumi without episodes', () {
      final b = LibraryBangumi.fromJson(<String, dynamic>{
        'id': 'b',
        'title': 't',
      });
      expect(b.episodes, isEmpty);
    });
  });
}
