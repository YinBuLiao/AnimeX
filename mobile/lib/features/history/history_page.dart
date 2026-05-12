import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/widgets/cover_image.dart';
import 'package:animex_mobile/data/dtos/history_entry.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/features/detail/detail_page.dart';
import 'package:animex_mobile/features/player/player_args.dart';
import 'package:animex_mobile/features/player/player_launcher.dart';

enum _HistoryFilter { all, inProgress, completed }

extension _HistoryFilterLabel on _HistoryFilter {
  String get label {
    switch (this) {
      case _HistoryFilter.all:
        return '全部';
      case _HistoryFilter.inProgress:
        return '进行中';
      case _HistoryFilter.completed:
        return '已看完';
    }
  }

  bool matches(HistoryEntry e) {
    if (this == _HistoryFilter.all) return true;
    if (e.durationSec <= 0) return this == _HistoryFilter.inProgress;
    final p = e.positionSec / e.durationSec;
    if (this == _HistoryFilter.completed) return p >= 0.95;
    return p < 0.95;
  }
}

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(historyListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('观看历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '清空全部',
            onPressed: () => _confirmClearAll(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final f in _HistoryFilter.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 6),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(historyListProvider),
              child: historyAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(
                  children: [
                    const SizedBox(height: 80),
                    const Icon(Icons.error_outline, size: 32),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('$e', textAlign: TextAlign.center),
                    ),
                  ],
                ),
                data: (resp) {
                  if (resp.entries.isEmpty) return const _Empty();
                  final filtered =
                      resp.entries.where(_filter.matches).toList();
                  if (filtered.isEmpty) {
                    return _FilteredEmpty(filter: _filter);
                  }
                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) =>
                        _HistoryTile(entry: filtered[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空全部历史？'),
        content: const Text('该操作不可恢复，所有播放进度会丢失。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final repo = await ref.read(historyRepositoryProvider.future);
      await repo.clearAll();
      ref.invalidate(historyListProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败：${e.message}')),
        );
      }
    }
  }
}

class _FilteredEmpty extends StatelessWidget {
  final _HistoryFilter filter;
  const _FilteredEmpty({required this.filter});

  @override
  Widget build(BuildContext context) {
    final hint = filter == _HistoryFilter.completed
        ? '还没有看完任何剧集。'
        : '没有进行中的观看记录。';
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.filter_alt_outlined, size: 32),
        const SizedBox(height: 12),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(hint, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  final HistoryEntry entry;
  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = entry.coverUrl;
    final progress = entry.durationSec > 0
        ? (entry.positionSec / entry.durationSec).clamp(0.0, 1.0)
        : 0.0;
    return Dismissible(
      key: ValueKey(entry.fileId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      onDismissed: (_) => _remove(context, ref),
      child: ListTile(
        leading: SizedBox(
          width: 48,
          height: 64,
          child: CoverImage(
            url: cover,
            cacheWidth: 192,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        title: Text(
          entry.episode == null
              ? entry.bangumiTitle
              : '${entry.bangumiTitle} · ${entry.episode}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: progress, minHeight: 4),
              const SizedBox(height: 4),
              Text(
                '${_formatDuration(entry.positionSec)} / ${_formatDuration(entry.durationSec)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        onTap: entry.url == null ? null : () => _launch(context, ref),
      ),
    );
  }

  void _launch(BuildContext context, WidgetRef ref) {
    final libAsync = ref.read(libraryListProvider);
    final cfgAsync = ref.read(serverConfigProvider);
    final downloads = ref.read(downloadManagerProvider);
    final baseUrl =
        cfgAsync.maybeWhen(data: (c) => c.baseUrl.trimRight(), orElse: () => '');
    final bangumi = libAsync.maybeWhen(
      data: (lib) => lib.bangumi
          .where((b) => b.title == entry.bangumiTitle)
          .cast<LibraryBangumi?>()
          .firstWhere((_) => true, orElse: () => null),
      orElse: () => null,
    );
    PlayerArgs? args;
    if (bangumi != null) {
      args = buildBangumiArgs(
        bangumi: bangumi,
        selectedFileId: entry.fileId,
        baseUrl: baseUrl,
        downloads: downloads,
        initialPositionSec: entry.positionSec,
        coverUrlFallback: entry.coverUrl,
      );
    }
    args ??= PlayerArgs(
      url: entry.url!,
      fileId: entry.fileId,
      title: entry.episode == null
          ? entry.bangumiTitle
          : '${entry.bangumiTitle} · ${entry.episode}',
      bangumiTitle: entry.bangumiTitle,
      episode: entry.episode,
      coverUrl: entry.coverUrl,
      initialPositionSec: entry.positionSec,
    );
    context.push('/player', extra: args);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    try {
      final repo = await ref.read(historyRepositoryProvider.future);
      await repo.remove(entry.fileId);
      ref.invalidate(historyListProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：${e.message}')),
        );
        ref.invalidate(historyListProvider);
      }
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.history, size: 36),
        SizedBox(height: 12),
        Center(child: Text('暂无观看记录')),
        SizedBox(height: 4),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '播放后会自动出现在这里，方便继续观看。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '00:00';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
