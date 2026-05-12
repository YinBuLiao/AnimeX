import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/data/dtos/history_entry.dart';
import 'package:animex_mobile/features/detail/detail_page.dart';
import 'package:animex_mobile/features/player/player_args.dart';

class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('观看历史')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(historyListProvider),
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
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
            return ListView.separated(
              itemCount: resp.entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _HistoryTile(entry: resp.entries[i]),
            );
          },
        ),
      ),
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
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 64,
        child: (cover == null || cover.isEmpty)
            ? Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.movie_outlined),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
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
      onTap: entry.url == null
          ? null
          : () => context.push(
                '/player',
                extra: PlayerArgs(
                  url: entry.url!,
                  fileId: entry.fileId,
                  title: entry.episode == null
                      ? entry.bangumiTitle
                      : '${entry.bangumiTitle} · ${entry.episode}',
                  bangumiTitle: entry.bangumiTitle,
                  episode: entry.episode,
                  coverUrl: entry.coverUrl,
                  initialPositionSec: entry.positionSec,
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
