import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';

class _UnreadBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(unreadNotificationsCountProvider);
    final count = async.asData?.value ?? 0;
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onError,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final config = ref.watch(serverConfigProvider);
    final serverLabel = config.maybeWhen(
      data: (c) => c.baseUrl,
      orElse: () => '',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        automaticallyImplyLeading: false,
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          if (s == null) {
            return const Center(child: Text('未登录'));
          }
          return ListView(
            children: [
              const SizedBox(height: 16),
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    s.username.isNotEmpty
                        ? s.username.substring(0, 1).toUpperCase()
                        : '?',
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  s.username,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '角色：${s.role}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('当前服务器'),
                subtitle: Text(serverLabel),
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('更换服务器'),
                onTap: () async {
                  final router = GoRouter.of(context);
                  await ref.read(sessionStoreProvider).clear();
                  await ref.read(serverConfigStoreProvider).clear();
                  ref.invalidate(currentSessionProvider);
                  ref.invalidate(serverConfigProvider);
                  if (context.mounted) router.go('/setup');
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('观看历史'),
                onTap: () => GoRouter.of(context).push('/history'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('通知'),
                trailing: _UnreadBadge(),
                onTap: () => GoRouter.of(context).push('/notifications'),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                onTap: () => GoRouter.of(context).push('/settings'),
              ),
              ListTile(
                leading: const Icon(Icons.password_outlined),
                title: const Text('修改密码'),
                subtitle: const Text('请前往 Web 管理面板'),
                enabled: false,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout,
                    color: Theme.of(context).colorScheme.error),
                title: Text(
                  '退出登录',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () async {
                  final router = GoRouter.of(context);
                  final repo =
                      await ref.read(authRepositoryProvider.future);
                  await repo.logout();
                  ref.invalidate(currentSessionProvider);
                  if (context.mounted) router.go('/login');
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
