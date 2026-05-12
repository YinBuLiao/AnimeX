import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/auth/session_store.dart';
import 'package:animex_mobile/core/config/server_config.dart';
import 'package:animex_mobile/features/auth/login_page.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';
import 'package:animex_mobile/features/detail/detail_page.dart';
import 'package:animex_mobile/features/player/player_args.dart';
import 'package:animex_mobile/features/player/player_page.dart';
import 'package:animex_mobile/features/discover/discover_tab.dart';
import 'package:animex_mobile/features/history/history_page.dart';
import 'package:animex_mobile/features/home/home_page.dart';
import 'package:animex_mobile/features/library/library_tab.dart';
import 'package:animex_mobile/features/profile/profile_tab.dart';
import 'package:animex_mobile/features/server_setup/server_setup_page.dart';
import 'package:animex_mobile/features/shell/app_shell.dart';
import 'package:flutter/material.dart';

class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen<AsyncValue<ServerConfig>>(serverConfigProvider,
        (_, __) => notifyListeners());
    ref.listen<AsyncValue<StoredSession?>>(currentSessionProvider,
        (_, __) => notifyListeners());
  }
}

String decideStartRoute({
  required ServerConfig config,
  required StoredSession? session,
  DateTime Function()? clock,
}) {
  if (!config.isComplete) return '/setup';
  if (session == null || session.token.isEmpty) return '/login';
  final now = (clock ?? DateTime.now)().millisecondsSinceEpoch ~/ 1000;
  if (session.expiresAtSec > 0 && session.expiresAtSec <= now) return '/login';
  return '/';
}

GoRouter buildRouter(Ref ref) {
  final refresh = _RouterRefresh(ref);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final configAsync = ref.read(serverConfigProvider);
      final sessionAsync = ref.read(currentSessionProvider);
      final config = configAsync.asData?.value;
      final session = sessionAsync.asData?.value;
      // While initial data still loading, stay where we are.
      if (configAsync.isLoading || sessionAsync.isLoading) return null;
      if (config == null) return null;

      final desired = decideStartRoute(config: config, session: session);
      final loc = state.matchedLocation;

      // If we're already at the desired route, no redirect.
      if (loc == desired) return null;
      // Allow free movement between login <-> setup once both load.
      if (loc == '/setup' && desired == '/login') return null;
      // Once the user is authenticated (desired='/'), let them stay on any
      // pushed sub-route (/detail, /player, /history). The redirect only
      // bounces back to /login or /setup when the user is *not* allowed
      // anywhere else.
      if (desired == '/' && loc != '/login' && loc != '/setup') return null;
      return desired;
    },
    routes: [
      GoRoute(path: '/setup', builder: (_, __) => const ServerSetupPage()),
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(
        path: '/',
        builder: (_, __) => AppShell(
          tabs: const [
            HomePage(),
            DiscoverTab(),
            LibraryTab(),
            ProfileTab(),
          ],
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
            NavigationDestination(
                icon: Icon(Icons.explore_outlined), label: '发现'),
            NavigationDestination(
                icon: Icon(Icons.video_library_outlined), label: '媒体库'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: '我的'),
          ],
        ),
      ),
      GoRoute(
        path: '/detail',
        builder: (context, state) {
          final args = state.extra as DetailArgs?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('缺少详情参数')),
            );
          }
          return DetailPage(args: args);
        },
      ),
      GoRoute(
        path: '/history',
        builder: (_, __) => const HistoryPage(),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final args = state.extra as PlayerArgs?;
          if (args == null) {
            return const Scaffold(
              body: Center(child: Text('缺少播放参数')),
            );
          }
          return PlayerPage(args: args);
        },
      ),
    ],
  );
}

final routerProvider = Provider<GoRouter>(buildRouter);
