import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/widgets/cover_image.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

final _animeListProvider =
    FutureProvider<List<AdminAnimeItem>>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  return repo.listAnime();
});

class AdminAnimePage extends ConsumerStatefulWidget {
  const AdminAnimePage({super.key});

  @override
  ConsumerState<AdminAnimePage> createState() => _AdminAnimePageState();
}

class _AdminAnimePageState extends ConsumerState<AdminAnimePage> {
  final Set<String> _selected = {};
  bool _busy = false;

  String _formatBytes(int b) {
    if (b <= 0) return '—';
    if (b > 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b > 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b > 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '$b B';
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    bool deleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('删除 ${_selected.length} 项番剧？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('从快照中移除选中的番剧。'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFiles,
                onChanged: (v) => setLocal(() => deleteFiles = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('同时删除存储桶中的文件'),
                subtitle: const Text('不可恢复'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除')),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(adminRepositoryProvider.future);
      final n = await repo.deleteAnime(
        titles: _selected.toList(),
        deleteFiles: deleteFiles,
      );
      _selected.clear();
      ref.invalidate(_animeListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $n 项')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_animeListProvider);
    final selectionMode = _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(selectionMode ? '已选 ${_selected.length} 项' : '番剧管理'),
        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              )
            : null,
        actions: [
          if (selectionMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _busy ? null : _deleteSelected,
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(_animeListProvider),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', textAlign: TextAlign.center),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('暂无番剧'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_animeListProvider),
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final a = items[i];
                final selected = _selected.contains(a.title);
                return ListTile(
                  selected: selected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3),
                  leading: SizedBox(
                    width: 48,
                    height: 64,
                    child: CoverImage(
                      url: a.coverUrl.isEmpty ? null : a.coverUrl,
                      cacheWidth: 192,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  title: Text(
                    a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${a.episodeCount} 集 · ${a.fileCount} 文件 · ${_formatBytes(a.storageBytes)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: selectionMode
                      ? Checkbox(
                          value: selected,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selected.add(a.title);
                            } else {
                              _selected.remove(a.title);
                            }
                          }),
                        )
                      : const Icon(Icons.more_vert),
                  onTap: () {
                    if (selectionMode) {
                      setState(() {
                        if (selected) {
                          _selected.remove(a.title);
                        } else {
                          _selected.add(a.title);
                        }
                      });
                    } else {
                      setState(() => _selected.add(a.title));
                    }
                  },
                  onLongPress: () => setState(() => _selected.add(a.title)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
