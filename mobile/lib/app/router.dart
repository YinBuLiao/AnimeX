import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/features/auth/login_page.dart';
import 'package:animex_mobile/features/home/home_page.dart';
import 'package:animex_mobile/features/server_setup/server_setup_page.dart';

String decideStartRoute({
  required ServerConfig config,
  required StoredSession? session,
}) {
  if (!config.isComplete) return '/setup';
  if (session == null || session.token.isEmpty) return '/login';
  return '/';
}

GoRouter buildRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final configAsync = ref.read(serverConfigProvider);
      final sessionAsync = ref.read(currentSessionProvider);
      final config = configAsync.asData?.value;
      final session = sessionAsync.asData?.value;
      // While initial data still loading, stay where we are.
      if (config == null || sessionAsync.isLoading) return null;

      final desired = decideStartRoute(config: config, session: session);
      final loc = state.matchedLocation;

      // If we're already at the desired route, no redirect.
      if (loc == desired) return null;
      // Allow free movement between login <-> setup once both load.
      if (loc == '/setup' && desired == '/login') return null;
      return desired;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, __) => const ServerSetupPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
    ],
  );
}

final routerProvider = Provider<GoRouter>(buildRouter);
