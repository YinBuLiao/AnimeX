import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/features/server_setup/server_setup_page.dart';

Widget _harness({
  required ServerConfigStore configStore,
  required Dio dio,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      serverConfigStoreProvider.overrideWithValue(configStore),
      sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      // Override dio builder so health probe hits the mocked Dio
      dioBuilderProvider.overrideWithValue(
        ({
          required ServerConfig config,
          required SessionStore sessionStore,
          OnUnauthorized? onUnauthorized,
        }) =>
            dio,
      ),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('shows URL input + self-signed checkbox + test button',
      (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://x'),
      sessionStore: InMemorySessionStore(),
    );
    await tester.pumpWidget(_harness(
      configStore: InMemoryServerConfigStore(),
      dio: dio,
      child: const ServerSetupPage(),
    ));
    expect(find.widgetWithText(TextField, '服务器地址'), findsOneWidget);
    expect(find.text('忽略 HTTPS 证书错误'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '测试连接'), findsOneWidget);
  });

  testWidgets('rejects invalid URL before calling network', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://x'),
      sessionStore: InMemorySessionStore(),
    );
    await tester.pumpWidget(_harness(
      configStore: InMemoryServerConfigStore(),
      dio: dio,
      child: const ServerSetupPage(),
    ));

    await tester.enterText(find.byType(TextField).first, 'not-a-url');
    await tester.tap(find.widgetWithText(FilledButton, '测试连接'));
    await tester.pump();
    expect(find.textContaining('http://'), findsWidgets);
  });

  testWidgets('successful health probe saves config and shows version',
      (tester) async {
    final configStore = InMemoryServerConfigStore();
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(200, {'ok': true, 'version': 'v0.2', 'installed': true}),
    );

    await tester.pumpWidget(_harness(
      configStore: configStore,
      dio: dio,
      child: const ServerSetupPage(),
    ));
    await tester.enterText(
        find.byType(TextField).first, 'https://server.example');
    await tester.tap(find.widgetWithText(FilledButton, '测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('v0.2'), findsOneWidget);
    final saved = await configStore.load();
    expect(saved.baseUrl, 'https://server.example');
  });

  testWidgets('health probe offers start button when login is not required',
      (tester) async {
    final configStore = InMemoryServerConfigStore();
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(200, {
        'ok': true,
        'version': 'v0.2',
        'installed': true,
        'require_login': false,
      }),
    );

    await tester.pumpWidget(_harness(
      configStore: configStore,
      dio: dio,
      child: const ServerSetupPage(),
    ));
    await tester.enterText(
        find.byType(TextField).first, 'https://server.example');
    await tester.tap(find.widgetWithText(FilledButton, '测试连接'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, '开始使用'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '下一步：登录'), findsNothing);
  });

  testWidgets(
      'health probe with installed=false shows warning + disables next button',
      (tester) async {
    final configStore = InMemoryServerConfigStore();
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(200, {'ok': true, 'version': 'v0.2', 'installed': false}),
    );

    await tester.pumpWidget(_harness(
      configStore: configStore,
      dio: dio,
      child: const ServerSetupPage(),
    ));
    await tester.enterText(
        find.byType(TextField).first, 'https://server.example');
    await tester.tap(find.widgetWithText(FilledButton, '测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('尚未完成安装'), findsOneWidget);
    final nextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下一步：登录'),
    );
    expect(nextButton.onPressed, isNull);
  });

  testWidgets('401 health probe still saves config and offers login',
      (tester) async {
    final configStore = InMemoryServerConfigStore();
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onGet(
      '/api/health',
      (s) => s.reply(401, {'error': '请先登录'}),
    );

    await tester.pumpWidget(_harness(
      configStore: configStore,
      dio: dio,
      child: const ServerSetupPage(),
    ));
    await tester.enterText(
        find.byType(TextField).first, 'https://server.example');
    await tester.tap(find.widgetWithText(FilledButton, '测试连接'));
    await tester.pumpAndSettle();

    expect(find.textContaining('需要登录'), findsOneWidget);
    expect(find.textContaining('连接失败'), findsNothing);
    final nextButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '下一步：登录'),
    );
    expect(nextButton.onPressed, isNotNull);
    final saved = await configStore.load();
    expect(saved.baseUrl, 'https://server.example');
  });
}
