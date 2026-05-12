import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/features/auth/login_page.dart';

Widget _harness({
  required ServerConfigStore configStore,
  required SessionStore sessions,
  required Dio dio,
}) {
  return ProviderScope(
    overrides: [
      serverConfigStoreProvider.overrideWithValue(configStore),
      sessionStoreProvider.overrideWithValue(sessions),
      dioBuilderProvider.overrideWithValue(
        ({
          required ServerConfig config,
          required SessionStore sessionStore,
          OnUnauthorized? onUnauthorized,
        }) =>
            dio,
      ),
    ],
    child: const MaterialApp(home: LoginPage()),
  );
}

void main() {
  testWidgets('shows username + password fields + login button', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://x'),
      sessionStore: InMemorySessionStore(),
    );
    final configStore = InMemoryServerConfigStore();
    await configStore.save(const ServerConfig(baseUrl: 'https://x'));
    await tester.pumpWidget(_harness(
      configStore: configStore,
      sessions: InMemorySessionStore(),
      dio: dio,
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '用户名'), findsOneWidget);
    expect(find.widgetWithText(TextField, '密码'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
  });

  testWidgets('successful login persists session', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(200, {
        'ok': true,
        'token': 'tok-X',
        'expires_at': 1700000000,
        'username': 'alice',
        'role': 'admin',
      }),
      data: {'username': 'alice', 'password': 'secret'},
    );
    final sessions = InMemorySessionStore();
    final configStore = InMemoryServerConfigStore();
    await configStore.save(const ServerConfig(baseUrl: 'https://server.example'));

    await tester.pumpWidget(_harness(
      configStore: configStore,
      sessions: sessions,
      dio: dio,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'alice');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    final saved = await sessions.load();
    expect(saved?.token, 'tok-X');
  });

  testWidgets('401 shows error message', (tester) async {
    final dio = buildDio(
      config: const ServerConfig(baseUrl: 'https://server.example'),
      sessionStore: InMemorySessionStore(),
    );
    DioAdapter(dio: dio).onPost(
      '/api/auth/mobile-login',
      (s) => s.reply(401, {'ok': false, 'error': '用户名或密码错误'}),
      data: {'username': 'alice', 'password': 'WRONG'},
    );
    final configStore = InMemoryServerConfigStore();
    await configStore.save(const ServerConfig(baseUrl: 'https://server.example'));

    await tester.pumpWidget(_harness(
      configStore: configStore,
      sessions: InMemorySessionStore(),
      dio: dio,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'alice');
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'WRONG');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.textContaining('用户名或密码错误'), findsOneWidget);
  });
}
