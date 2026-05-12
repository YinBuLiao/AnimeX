import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

final _logsProvider = FutureProvider<List<AdminLogEntry>>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  return repo.logs();
});

class AdminLogsPage extends ConsumerWidget {
  const AdminLogsPage({super.key});

  Color _levelColor(BuildContext ctx, String level) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return Theme.of(ctx).colorScheme.error;
      case 'WARN':
      case 'WARNING':
        return Colors.orange;
      case 'INFO':
        return Theme.of(ctx).colorScheme.primary;
      default:
        return Theme.of(ctx).colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_logsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_logsProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_logsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (logs) {
            if (logs.isEmpty) {
              return const Center(child: Text('暂无日志'));
            }
            return ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final l = logs[i];
                return ListTile(
                  dense: true,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _levelColor(context, l.level)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l.level,
                          style: TextStyle(
                            fontSize: 10,
                            color: _levelColor(context, l.level),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l.module,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        l.time,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(l.message),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
