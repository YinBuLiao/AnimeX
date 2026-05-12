import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AnimeX'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: session.when(
          loading: () => const CircularProgressIndicator(),
          error: (e, _) => Text('错误：$e'),
          data: (s) {
            if (s == null) {
              return const Text('未登录');
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('欢迎，${s.username}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 24)),
                  const SizedBox(height: 8),
                  Text('角色：${s.role}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 32),
                  Text(
                    'M2：服务器连接 + 登录 + 发现 / 媒体库 / 我的',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '在「发现」中找番、订阅；订阅后会显示在「媒体库」。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
