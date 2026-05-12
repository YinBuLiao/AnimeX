import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/cast/cast_manager.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/download/download_manager.dart';
import 'package:animex_mobile/core/notifications/device_registrar.dart';
import 'package:animex_mobile/core/preferences/app_preferences.dart';
import 'package:animex_mobile/core/preferences/notifications_seen.dart';
import 'package:animex_mobile/core/preferences/subscribed_store.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/admin_repository.dart';
import 'package:animex_mobile/data/repositories/auth_repository.dart';
import 'package:animex_mobile/data/repositories/discover_repository.dart';
import 'package:animex_mobile/data/repositories/history_repository.dart';
import 'package:animex_mobile/data/repositories/library_repository.dart';
import 'package:animex_mobile/data/repositories/notifications_repository.dart';
import 'package:animex_mobile/data/repositories/subscription_repository.dart';
import 'package:animex_mobile/data/dtos/health_info.dart';
import 'package:animex_mobile/data/repositories/system_repository.dart';

/// Injectable factory for [Dio]. Tests override this to supply a Dio with a
/// `DioAdapter` mock attached.
typedef DioBuilder = Dio Function({
  required ServerConfig config,
  required SessionStore sessionStore,
  OnUnauthorized? onUnauthorized,
});

final dioBuilderProvider = Provider<DioBuilder>((_) => buildDio);

final serverConfigStoreProvider =
    Provider<ServerConfigStore>((_) => SecureServerConfigStore());

final sessionStoreProvider =
    Provider<SessionStore>((_) => SecureSessionStore());

/// Current persisted ServerConfig. Invalidate to re-read after the user
/// changes servers.
final serverConfigProvider = FutureProvider<ServerConfig>((ref) async {
  final store = ref.watch(serverConfigStoreProvider);
  return store.load();
});

/// Dio bound to the current ServerConfig + SessionStore.
final dioProvider = FutureProvider<Dio>((ref) async {
  final config = await ref.watch(serverConfigProvider.future);
  final sessions = ref.watch(sessionStoreProvider);
  final builder = ref.watch(dioBuilderProvider);
  return builder(
    config: config,
    sessionStore: sessions,
    onUnauthorized: () {
      // Fire-and-forget: drop the stored token so future calls don't keep
      // sending it, then invalidate the session provider so the router
      // refresh listener bounces the user to /login.
      sessions.clear();
      ref.invalidate(currentSessionProvider);
    },
  );
});

final systemRepositoryProvider = FutureProvider<SystemRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return SystemRepository(dio);
});

final authRepositoryProvider = FutureProvider<AuthRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  final sessions = ref.watch(sessionStoreProvider);
  return AuthRepository(dio: dio, sessions: sessions);
});

final discoverRepositoryProvider =
    FutureProvider<DiscoverRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return DiscoverRepository(dio);
});

final libraryRepositoryProvider =
    FutureProvider<LibraryRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return LibraryRepository(dio);
});

final subscriptionRepositoryProvider =
    FutureProvider<SubscriptionRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return SubscriptionRepository(dio);
});

final historyRepositoryProvider =
    FutureProvider<HistoryRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return HistoryRepository(dio);
});

final notificationsRepositoryProvider =
    FutureProvider<NotificationsRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return NotificationsRepository(dio);
});

final adminRepositoryProvider = FutureProvider<AdminRepository>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  return AdminRepository(dio);
});

/// Cached "is the user logged in" check — used by router redirect.
final currentSessionProvider = FutureProvider<StoredSession?>((ref) async {
  final sessions = ref.watch(sessionStoreProvider);
  return sessions.load();
});

/// App-wide download manager (background_downloader singleton). Initialized
/// at boot in main(); subscribers should use [downloadEntriesProvider]
/// instead of reading this directly so they auto-rebuild on progress.
final downloadManagerProvider = Provider<DownloadManager>((_) {
  throw StateError(
      'downloadManagerProvider must be overridden at app startup');
});

/// Reactive list of download entries, rebuilt on every manager notify.
final downloadEntriesProvider = ChangeNotifierProvider<DownloadManager>(
    (ref) => ref.watch(downloadManagerProvider));

/// Singleton CastManager for the active player session. Lazily created on
/// first read so SSDP discovery only happens when the user opens the picker.
final castManagerProvider = ChangeNotifierProvider<CastManager>(
    (ref) => CastManager());

/// Source of the FCM device token. Default is a no-op so the app builds
/// without Firebase. Override at app startup with a firebase_messaging
/// implementation once a Firebase project is wired up.
final pushTokenSourceProvider =
    Provider<PushTokenSource>((_) => const NoopPushTokenSource());

/// App-wide preferences (toggles, default volume, …). Loaded at boot and
/// exposed as a ChangeNotifier so widgets rebuild on change.
final appPreferencesProvider = ChangeNotifierProvider<AppPreferences>((_) {
  throw StateError(
      'appPreferencesProvider must be overridden at app startup');
});

/// Best-effort local mirror of bangumi titles the user subscribed to.
final subscribedStoreProvider = FutureProvider<SubscribedStore>((_) async {
  return SubscribedStore.load();
});

/// Persists the "last seen" notification timestamp for the unread badge.
final notificationsSeenStoreProvider =
    FutureProvider<NotificationsSeenStore>((_) async {
  return NotificationsSeenStore.load();
});

/// Server health snapshot for the profile tab status pills. Auto-dispose
/// so we don't keep hitting /api/health between visits.
final healthInfoProvider = FutureProvider.autoDispose<HealthInfo>((ref) async {
  final repo = await ref.watch(systemRepositoryProvider.future);
  return repo.health();
});

/// Pending admin download-request count for the bottom-nav badge. Admin
/// only; auto-disposes so non-admin sessions don't poll.
final pendingAdminRequestsCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  try {
    final list = await repo.downloadRequests();
    return list.where((r) => r.isPending).length;
  } catch (_) {
    return 0;
  }
});

/// Unread notification count. Watches the notifications repo + the local
/// last-seen pref. Invalidate after the user views the notifications page
/// to clear the badge.
final unreadNotificationsCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final repo = await ref.watch(notificationsRepositoryProvider.future);
  final seen = await ref.watch(notificationsSeenStoreProvider.future);
  final resp = await repo.list();
  final cutoff = seen.lastSeenAt;
  var count = 0;
  for (final e in resp.entries) {
    if (e.createdAt > cutoff) count++;
  }
  return count;
});
