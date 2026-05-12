import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/app/router.dart';
import 'package:animex_mobile/app/theme.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/download/download_manager.dart';
import 'package:animex_mobile/core/notifications/device_registrar.dart';
import 'package:animex_mobile/core/preferences/app_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final downloads = await DownloadManager.create();
  final prefs = await AppPreferences.load();
  runApp(ProviderScope(
    overrides: [
      downloadManagerProvider.overrideWithValue(downloads),
      appPreferencesProvider.overrideWith((_) => prefs),
    ],
    child: const AnimeXApp(),
  ));
}

class AnimeXApp extends ConsumerStatefulWidget {
  const AnimeXApp({super.key});

  @override
  ConsumerState<AnimeXApp> createState() => _AnimeXAppState();
}

class _AnimeXAppState extends ConsumerState<AnimeXApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRegisterDevice();
      _maybeSyncSubscriptions();
    });
    ref.listenManual<AsyncValue<StoredSession?>>(currentSessionProvider, (_, __) {
      _maybeRegisterDevice();
      _maybeSyncSubscriptions();
    });
  }

  Future<void> _maybeRegisterDevice() async {
    try {
      final session = await ref.read(currentSessionProvider.future);
      if (session == null || session.token.isEmpty) return;
      final source = ref.read(pushTokenSourceProvider);
      final repo = await ref.read(notificationsRepositoryProvider.future);
      await registerDeviceForPush(source: source, repo: repo);
    } catch (_) {
      // Best-effort: never block app boot on device registration.
    }
  }

  Future<void> _maybeSyncSubscriptions() async {
    try {
      final session = await ref.read(currentSessionProvider.future);
      if (session == null || session.token.isEmpty) return;
      final repo = await ref.read(subscriptionRepositoryProvider.future);
      final titles = await repo.listSubscribedTitles();
      final store = await ref.read(subscribedStoreProvider.future);
      await store.replaceAll(titles);
    } catch (_) {
      // Best-effort: missing endpoint or auth issue should not crash boot.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(appPreferencesProvider).themeMode;
    return MaterialApp.router(
      title: 'AnimeX',
      theme: animexLightTheme(),
      darkTheme: animexDarkTheme(),
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
