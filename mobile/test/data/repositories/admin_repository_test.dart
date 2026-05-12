import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/admin_repository.dart';

void main() {
  late Dio dio;
  setUp(() {
    dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
  });

  test('overview() parses cards + meta', () async {
    DioAdapter(dio: dio).onGet(
      '/api/admin/overview',
      (s) => s.reply(200, {
        'cards': [
          {'label': '总用户数', 'value': 5, 'trend': '本地账号', 'icon': '👥'},
          {'label': '番剧总数', 'value': 12, 'trend': 'local 快照', 'icon': '📺'},
        ],
        'storage_provider': 'local',
        'library_updated_at': '2026-05-12T09:00:00Z',
      }),
    );
    final o = await AdminRepository(dio).overview();
    expect(o.cards, hasLength(2));
    expect(o.cards.first.label, '总用户数');
    expect(o.cards.first.value, '5');
    expect(o.storageProvider, 'local');
  });

  test('monitor() parses runtime + service readiness', () async {
    DioAdapter(dio: dio).onGet(
      '/api/admin/monitor',
      (s) => s.reply(200, {
        'uptime': '1h30m',
        'goroutines': 42,
        'memory_alloc': 1048576,
        'memory_sys': 4194304,
        'mysql_ready': true,
        'redis_ready': false,
        'pikpak_ready': false,
        'storage_ready': true,
        'storage_provider': 'local',
        'installed': true,
        'install_only': false,
      }),
    );
    final m = await AdminRepository(dio).monitor();
    expect(m.uptime, '1h30m');
    expect(m.goroutines, 42);
    expect(m.mysqlReady, isTrue);
    expect(m.redisReady, isFalse);
    expect(m.installed, isTrue);
  });

  test('logs() parses entries', () async {
    DioAdapter(dio: dio).onGet(
      '/api/admin/logs',
      (s) => s.reply(200, {
        'logs': [
          {
            'time': '2026-05-12 09:00:00',
            'level': 'INFO',
            'module': 'admin',
            'message': '面板刷新完成',
          },
          {
            'time': '2026-05-12 08:55:00',
            'level': 'WARN',
            'module': 'mysql',
            'message': '连接重建',
          },
        ],
      }),
    );
    final logs = await AdminRepository(dio).logs();
    expect(logs, hasLength(2));
    expect(logs.first.level, 'INFO');
    expect(logs[1].level, 'WARN');
  });

  test('downloadRequests() parses status', () async {
    DioAdapter(dio: dio).onGet(
      '/api/admin/download-requests',
      (s) => s.reply(200, {
        'items': [
          {
            'id': 1,
            'username': 'alice',
            'bangumi_title': 'Frieren',
            'episode_label': '第 02 话',
            'status': 'pending',
            'created_at': '2026-05-12 09:00:00',
          },
          {
            'id': 2,
            'username': 'bob',
            'bangumi_title': 'Bocchi',
            'episode_label': '第 03 话',
            'status': 'approved',
            'created_at': '2026-05-11 18:00:00',
          },
        ],
      }),
    );
    final items = await AdminRepository(dio).downloadRequests();
    expect(items, hasLength(2));
    expect(items.first.isPending, isTrue);
    expect(items[1].status, 'approved');
  });

  test('actOnDownloadRequest() POSTs id + action and returns list', () async {
    DioAdapter(dio: dio).onPost(
      '/api/admin/download-requests',
      (s) => s.reply(200, {
        'ok': true,
        'items': [
          {'id': 1, 'status': 'approved'}
        ],
      }),
      data: {'id': 1, 'action': 'approve'},
    );
    final items = await AdminRepository(dio).actOnDownloadRequest(
      id: 1,
      action: 'approve',
    );
    expect(items, hasLength(1));
    expect(items.first.status, 'approved');
  });

  test('overview() surfaces non-2xx as ApiException', () async {
    DioAdapter(dio: dio).onGet(
      '/api/admin/overview',
      (s) => s.reply(403, {'ok': false, 'error': '仅管理员可访问'}),
    );
    try {
      await AdminRepository(dio).overview();
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.statusCode, 403);
      expect(e.message, '仅管理员可访问');
    }
  });
}
