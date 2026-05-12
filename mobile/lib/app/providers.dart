import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/core/network/dio_client.dart';
import 'package:animex_mobile/data/repositories/auth_repository.dart';
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

/// Cached "is the user logged in" check — used by router redirect.
final currentSessionProvider = FutureProvider<StoredSession?>((ref) async {
  final sessions = ref.watch(sessionStoreProvider);
  return sessions.load();
});
