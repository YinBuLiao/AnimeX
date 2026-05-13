import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

final _requestsProvider =
    FutureProvider<List<AdminDownloadRequest>>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  return repo.downloadRequests();
});

class AdminRequestsPage extends ConsumerStatefulWidget {
  const AdminRequestsPage({super.key});

  @override
  ConsumerState<AdminRequestsPage> createState() => _AdminRequestsPageState();
}

class _AdminRequestsPageState extends ConsumerState<AdminRequestsPage> {
  int? _busyId;

  Color _statusColor(BuildContext ctx, String status) {
    switch (status) {
      case 'pending':
        return Theme.of(ctx).colorScheme.tertiary;
      case 'approved':
      case 'downloading':
        return Colors.green;
      case 'rejected':
      case 'failed':
        return Theme.of(ctx).colorScheme.error;
      default:
        return Theme.of(ctx).colorScheme.outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return '待审批';
      case 'approved':
        return '已通过';
      case 'downloading':
        return '下载中';
      case 'rejected':
        return '已拒绝';
      case 'failed':
        return '失败';
      default:
        return status;
    }
  }

  Future<void> _act(AdminDownloadRequest r, String action) async {
    final label = action == 'approve' ? '通过' : '拒绝';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('确认$label'),
        content: Text('${r.username} 的申请：${r.bangumiTitle} · ${r.episodeLabel}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyId = r.id);
    try {
      final repo = await ref.read(adminRepositoryProvider.future);
      await repo.actOnDownloadRequest(id: r.id, action: action);
      ref.invalidate(_requestsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_requestsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('下载申请审批')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_requestsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (items) {
            if (items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 100),
                Icon(Icons.inbox_outlined, size: 36),
                SizedBox(height: 12),
                Center(child: Text('暂无下载申请')),
              ]);
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = items[i];
                final isBusy = _busyId == r.id;
                return ListTile(
                  title: Text(
                    '${r.bangumiTitle} · ${r.episodeLabel}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.username} · ${r.createdAt}'),
                        const SizedBox(height: 2),
                        Text(
                          _statusLabel(r.status),
                          style: TextStyle(
                            fontSize: 11,
                            color: _statusColor(context, r.status),
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: isBusy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : r.isPending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline,
                                      color: Colors.green),
                                  tooltip: '通过',
                                  onPressed: () => _act(r, 'approve'),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.cancel_outlined,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  tooltip: '拒绝',
                                  onPressed: () => _act(r, 'reject'),
                                ),
                              ],
                            )
                          : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
