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
import 'package:animex_mobile/features/admin/admin_logs_page.dart';
import 'package:animex_mobile/features/admin/admin_monitor_page.dart';
import 'package:animex_mobile/features/admin/admin_overview_page.dart';
import 'package:animex_mobile/features/admin/admin_requests_page.dart';
import 'package:animex_mobile/features/admin/admin_tab.dart';
import 'package:animex_mobile/features/admin/admin_web_placeholder_page.dart';
import 'package:animex_mobile/features/discover/discover_tab.dart';
import 'package:animex_mobile/features/discover/search_view.dart';
import 'package:animex_mobile/features/downloads/downloads_page.dart';
import 'package:animex_mobile/features/history/history_page.dart';
import 'package:animex_mobile/features/home/home_page.dart';
import 'package:animex_mobile/features/library/library_tab.dart';
import 'package:animex_mobile/features/notifications/notifications_page.dart';
import 'package:animex_mobile/features/profile/profile_tab.dart';
import 'package:animex_mobile/features/server_setup/server_setup_page.dart';
import 'package:animex_mobile/features/settings/settings_page.dart';
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
        builder: (_, __) => const _RootShell(),
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
        path: '/notifications',
        builder: (_, __) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsPage(),
      ),
      GoRoute(
        path: '/search',
        builder: (_, __) => Scaffold(
          appBar: AppBar(title: const Text('搜索')),
          body: const SearchView(),
        ),
      ),
      GoRoute(
        path: '/admin/overview',
        builder: (_, __) => const AdminOverviewPage(),
      ),
      GoRoute(
        path: '/admin/monitor',
        builder: (_, __) => const AdminMonitorPage(),
      ),
      GoRoute(
        path: '/admin/download-requests',
        builder: (_, __) => const AdminRequestsPage(),
      ),
      GoRoute(
        path: '/admin/logs',
        builder: (_, __) => const AdminLogsPage(),
      ),
      GoRoute(
        path: '/admin/web/users',
        builder: (_, __) => const AdminWebPlaceholderPage(
          title: '用户管理',
          webPath: '/admin#users',
        ),
      ),
      GoRoute(
        path: '/admin/web/invite-codes',
        builder: (_, __) => const AdminWebPlaceholderPage(
          title: '邀请码',
          webPath: '/admin#invites',
        ),
      ),
      GoRoute(
        path: '/admin/web/anime',
        builder: (_, __) => const AdminWebPlaceholderPage(
          title: '番剧管理',
          webPath: '/admin#anime',
        ),
      ),
      GoRoute(
        path: '/admin/web/storage',
        builder: (_, __) => const AdminWebPlaceholderPage(
          title: '储存桶配置',
          webPath: '/admin#storage',
        ),
      ),
      GoRoute(
        path: '/admin/web/settings',
        builder: (_, __) => const AdminWebPlaceholderPage(
          title: '系统设置',
          webPath: '/admin#settings',
        ),
      ),
      GoRoute(
        path: '/downloads',
        builder: (_, __) => const DownloadsPage(),
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

class _AdminIcon extends StatelessWidget {
  final WidgetRef ref;
  const _AdminIcon({required this.ref});

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingAdminRequestsCountProvider);
    final count = pending.asData?.value ?? 0;
    const icon = Icon(Icons.admin_panel_settings_outlined);
    if (count <= 0) return icon;
    return Badge.count(count: count, child: icon);
  }
}

class _RootShell extends ConsumerWidget {
  const _RootShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final isAdmin = session.maybeWhen(
      data: (s) => s?.role == 'admin',
      orElse: () => false,
    );
    final tabs = <Widget>[
      const HomePage(),
      const DiscoverTab(),
      const LibraryTab(),
      if (isAdmin) const AdminTab(),
      const ProfileTab(),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
      const NavigationDestination(
          icon: Icon(Icons.explore_outlined), label: '发现'),
      const NavigationDestination(
          icon: Icon(Icons.video_library_outlined), label: '媒体库'),
      if (isAdmin)
        NavigationDestination(
          icon: _AdminIcon(ref: ref),
          label: '管理',
        ),
      const NavigationDestination(
          icon: Icon(Icons.person_outline), label: '我的'),
    ];
    return AppShell(tabs: tabs, destinations: destinations);
  }
}
