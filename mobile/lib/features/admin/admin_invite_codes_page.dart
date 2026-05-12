import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

final _codesProvider = FutureProvider<List<AdminInviteCode>>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  return repo.listInviteCodes();
});

class AdminInviteCodesPage extends ConsumerStatefulWidget {
  const AdminInviteCodesPage({super.key});

  @override
  ConsumerState<AdminInviteCodesPage> createState() =>
      _AdminInviteCodesPageState();
}

class _AdminInviteCodesPageState extends ConsumerState<AdminInviteCodesPage> {
  bool _busy = false;

  Future<void> _generate() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _GenerateSheet(),
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(adminRepositoryProvider.future);
      await repo.generateInviteCodes(
        count: (picked['count'] as int?) ?? 1,
        expiresAt: picked['expires_at'] as String?,
      );
      ref.invalidate(_codesProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String code) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除该邀请码？'),
        content: Text(code),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = await ref.read(adminRepositoryProvider.future);
      await repo.deleteInviteCodes([code]);
      ref.invalidate(_codesProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${e.message}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_codesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('邀请码'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_codesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('生成'),
        onPressed: _busy ? null : _generate,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', textAlign: TextAlign.center),
          ),
        ),
        data: (codes) {
          if (codes.isEmpty) {
            return const Center(child: Text('暂无邀请码'));
          }
          return ListView.separated(
            itemCount: codes.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = codes[i];
              return ListTile(
                leading: Icon(
                  c.isUsed
                      ? Icons.check_circle_outline
                      : Icons.confirmation_number_outlined,
                  color: c.isUsed
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  c.code,
                  style: TextStyle(
                    decoration: c.isUsed
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    fontFamily: 'monospace',
                  ),
                ),
                subtitle: Text(
                  c.isUsed
                      ? '已被 ${c.usedBy} 于 ${c.usedAt} 使用'
                      : (c.expiresAt.isEmpty
                          ? '创建于 ${c.createdAt}'
                          : '创建于 ${c.createdAt} · 到期 ${c.expiresAt}'),
                  style: TextStyle(fontSize: 11),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'copy') {
                      await Clipboard.setData(ClipboardData(text: c.code));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制')),
                        );
                      }
                    } else if (v == 'delete') {
                      _delete(c.code);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'copy', child: Text('复制')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _GenerateSheet extends StatefulWidget {
  const _GenerateSheet();

  @override
  State<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends State<_GenerateSheet> {
  int _count = 1;
  DateTime? _expiresAt;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '生成邀请码',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('数量'),
                Expanded(
                  child: Slider(
                    value: _count.toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    label: '$_count',
                    onChanged: (v) => setState(() => _count = v.round()),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text('$_count', textAlign: TextAlign.end),
                ),
              ],
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('到期时间'),
              subtitle: Text(_expiresAt == null
                  ? '永不过期'
                  : '${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}'),
              trailing: TextButton(
                child: Text(_expiresAt == null ? '设置' : '清除'),
                onPressed: () async {
                  if (_expiresAt != null) {
                    setState(() => _expiresAt = null);
                    return;
                  }
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: now.add(const Duration(days: 7)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365 * 2)),
                  );
                  if (picked != null) setState(() => _expiresAt = picked);
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop({
                  'count': _count,
                  if (_expiresAt != null)
                    'expires_at':
                        '${_expiresAt!.year}-${_expiresAt!.month.toString().padLeft(2, '0')}-${_expiresAt!.day.toString().padLeft(2, '0')}',
                });
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}
