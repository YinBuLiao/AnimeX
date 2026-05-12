import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('AnimeX')),
      body: Center(
        child: session.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('错误：$e'),
          data: (s) {
            if (s == null) {
              return const Text('未登录');
            }
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('欢迎，${s.username}',
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(height: 8),
                Text('角色：${s.role}'),
                const SizedBox(height: 32),
                const Text('M1 完成：服务器连接 + 登录可用'),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    final router = GoRouter.of(context);
                    final repo = await ref.read(authRepositoryProvider.future);
                    await repo.logout();
                    ref.invalidate(currentSessionProvider);
                    router.go('/login');
                  },
                  child: const Text('退出登录'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
