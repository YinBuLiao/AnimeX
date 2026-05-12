import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/features/home/home_page.dart';

void main() {
  testWidgets('home greets the logged-in user', (tester) async {
    final sessions = InMemorySessionStore();
    await sessions.save(const StoredSession(
        token: 'tok', username: 'alice', role: 'admin', expiresAtSec: 0));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(sessions),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    // Don't pumpAndSettle — repositories require dio which is not wired
    // in widget tests; the section providers stay in loading state.
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('alice'), findsOneWidget);
    // The logout action lives on the ProfileTab now.
    expect(find.widgetWithText(TextButton, '退出登录'), findsNothing);
  });

  testWidgets('home shows "未登录" when no session is stored', (tester) async {
    final sessions = InMemorySessionStore();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionStoreProvider.overrideWithValue(sessions),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('未登录'), findsOneWidget);
  });
}
