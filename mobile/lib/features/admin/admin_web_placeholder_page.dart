import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';

class AdminWebPlaceholderPage extends ConsumerWidget {
  final String title;
  final String webPath;

  const AdminWebPlaceholderPage({
    super.key,
    required this.title,
    required this.webPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(serverConfigProvider);
    final baseUrl = config.maybeWhen(
      data: (c) => c.baseUrl,
      orElse: () => '',
    );
    final url = baseUrl.isEmpty
        ? ''
        : '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}$webPath';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.open_in_new, size: 48),
            const SizedBox(height: 16),
            Text(
              '$title 仅在 Web 管理面板提供完整编辑',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '手机端复杂表单容易出错，请在桌面浏览器中前往以下地址操作：',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            if (url.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  url,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            const SizedBox(height: 16),
            if (url.isNotEmpty)
              FilledButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制链接'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('链接已复制')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
