import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/notification_entry.dart';

final _notificationsListProvider =
    FutureProvider<List<NotificationEntry>>((ref) async {
  final repo = await ref.watch(notificationsRepositoryProvider.future);
  final resp = await repo.list();
  return resp.entries;
});

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_notificationsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('通知')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_notificationsListProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 80),
              const Icon(Icons.cloud_off_outlined, size: 32),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text('$e', textAlign: TextAlign.center),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(_notificationsListProvider),
                  child: const Text('重试'),
                ),
              ),
            ],
          ),
          data: (entries) {
            if (entries.isEmpty) return const _Empty();
            return ListView.builder(
              itemCount: entries.length,
              itemBuilder: (_, i) => _Tile(entry: entries[i]),
            );
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final NotificationEntry entry;
  const _Tile({required this.entry});

  IconData _iconFor(String kind) {
    switch (kind) {
      case NotificationEntry.kindNewEpisode:
        return Icons.movie_filter_outlined;
      case NotificationEntry.kindRequestApproved:
        return Icons.check_circle_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _formatTime(int unixSec) {
    if (unixSec <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_iconFor(entry.kind)),
      title: Text(entry.title.isEmpty ? '通知' : entry.title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.body.isNotEmpty) Text(entry.body),
            Text(
              _formatTime(entry.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.notifications_off_outlined, size: 36),
        const SizedBox(height: 12),
        const Center(child: Text('暂无通知')),
        const SizedBox(height: 4),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '新剧集入库 / 下载申请通过会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ),
      ],
    );
  }
}
