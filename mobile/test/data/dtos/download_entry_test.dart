import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/data/dtos/download_entry.dart';

void main() {
  group('sanitizeFilename', () {
    test('replaces path-illegal characters with underscore', () {
      expect(sanitizeFilename('Frieren / Ep:01 *?<>|.mkv'),
          'Frieren _ Ep_01 _____.mkv');
    });
    test('replaces nothing in a clean name', () {
      expect(sanitizeFilename('frieren_ep01.mkv'), 'frieren_ep01.mkv');
    });
    test('falls back to underscore on empty string', () {
      expect(sanitizeFilename(''), '_');
      expect(sanitizeFilename('   '), '_');
    });
    test('strips trailing dots', () {
      expect(sanitizeFilename('name...'), 'name');
    });
  });

  group('buildDownloadPath', () {
    test('joins app docs + sanitized bangumi + filename', () {
      final p = buildDownloadPath(
        appDocsDir: '/tmp/app',
        bangumiTitle: 'Frieren: Beyond Journey\'s End',
        fileName: 'EP01.mkv',
      );
      expect(p, '/tmp/app/AnimeX/Frieren_ Beyond Journey\'s End/EP01.mkv');
    });
  });

  group('DownloadEntry.toJson/fromJson', () {
    test('round-trips with all fields', () {
      final e = DownloadEntry(
        fileId: 'f1',
        bangumiTitle: 'Frieren',
        episode: '01',
        fileName: 'ep01.mkv',
        coverUrl: 'https://cdn/cover.jpg',
        url: 'https://srv/api/stream?id=f1',
        localPath: '/tmp/x/ep01.mkv',
        totalBytes: 1024 * 1024,
        downloadedBytes: 512 * 1024,
        status: DownloadStatus.running,
        updatedAt: 1700000000,
      );
      final j = e.toJson();
      final back = DownloadEntry.fromJson(j);
      expect(back.fileId, 'f1');
      expect(back.bangumiTitle, 'Frieren');
      expect(back.episode, '01');
      expect(back.status, DownloadStatus.running);
      expect(back.totalBytes, 1024 * 1024);
      expect(back.downloadedBytes, 512 * 1024);
      expect(back.progress, closeTo(0.5, 0.0001));
    });

    test('omits null episode / cover_url in json', () {
      final j = DownloadEntry(
        fileId: 'f',
        bangumiTitle: 'X',
        fileName: 'y',
        url: 'u',
        localPath: '/p',
        updatedAt: 1,
      ).toJson();
      expect(j.containsKey('episode'), isFalse);
      expect(j.containsKey('cover_url'), isFalse);
    });
  });
}
