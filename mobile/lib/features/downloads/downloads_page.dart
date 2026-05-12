import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/download_entry.dart';
import 'package:animex_mobile/features/player/player_args.dart';

class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(downloadEntriesProvider);
    final entries = manager.entries;
    final running = entries
        .where((e) =>
            e.status == DownloadStatus.queued ||
            e.status == DownloadStatus.running ||
            e.status == DownloadStatus.paused)
        .toList();
    final completed = entries
        .where((e) => e.status == DownloadStatus.complete)
        .toList();
    final failed = entries
        .where((e) =>
            e.status == DownloadStatus.failed ||
            e.status == DownloadStatus.canceled)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('下载')),
      body: entries.isEmpty
          ? const _Empty()
          : ListView(
              children: [
                if (running.isNotEmpty) ...[
                  const _SectionHeader(text: '进行中'),
                  ...running.map((e) => _Tile(entry: e)),
                ],
                if (completed.isNotEmpty) ...[
                  const _SectionHeader(text: '已完成'),
                  ...completed.map((e) => _Tile(entry: e)),
                ],
                if (failed.isNotEmpty) ...[
                  const _SectionHeader(text: '失败 / 已取消'),
                  ...failed.map((e) => _Tile(entry: e)),
                ],
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  final DownloadEntry entry;
  const _Tile({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadManagerProvider);
    return ListTile(
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
            if (entry.status == DownloadStatus.running ||
                entry.status == DownloadStatus.queued ||
                entry.status == DownloadStatus.paused)
              LinearProgressIndicator(
                value: entry.progress > 0 ? entry.progress : null,
                minHeight: 4,
              ),
            const SizedBox(height: 4),
            Text(
              _subtitleFor(entry),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            if (entry.errorMessage != null)
              Text(
                entry.errorMessage!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
          ],
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'play':
              context.push(
                '/player',
                extra: PlayerArgs(
                  url: entry.url,
                  fileId: entry.fileId,
                  title: entry.episode == null
                      ? entry.bangumiTitle
                      : '${entry.bangumiTitle} · ${entry.episode}',
                  bangumiTitle: entry.bangumiTitle,
                  episode: entry.episode,
                  coverUrl: entry.coverUrl,
                  localPath: entry.isComplete ? entry.localPath : null,
                ),
              );
            case 'pause':
              await manager.pause(entry.fileId);
            case 'resume':
              await manager.resume(entry.fileId);
            case 'cancel':
              await manager.cancel(entry.fileId);
            case 'delete':
              await manager.deleteEntry(entry.fileId);
          }
        },
        itemBuilder: (_) => [
          if (entry.isComplete)
            const PopupMenuItem(value: 'play', child: Text('播放')),
          if (entry.status == DownloadStatus.running)
            const PopupMenuItem(value: 'pause', child: Text('暂停')),
          if (entry.status == DownloadStatus.paused)
            const PopupMenuItem(value: 'resume', child: Text('继续')),
          if (entry.status == DownloadStatus.running ||
              entry.status == DownloadStatus.queued ||
              entry.status == DownloadStatus.paused)
            const PopupMenuItem(value: 'cancel', child: Text('取消')),
          const PopupMenuItem(value: 'delete', child: Text('删除')),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_download_outlined, size: 36),
            const SizedBox(height: 12),
            const Text('暂无下载任务'),
            const SizedBox(height: 4),
            Text(
              '在番剧详情页长按剧集即可加入下载。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

String _subtitleFor(DownloadEntry e) {
  String fmtBytes(int b) {
    if (b <= 0) return '';
    if (b > 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b > 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b > 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '$b B';
  }

  switch (e.status) {
    case DownloadStatus.queued:
      return '排队中';
    case DownloadStatus.running:
      return '${fmtBytes(e.downloadedBytes)} / ${fmtBytes(e.totalBytes)}'
          ' · ${(e.progress * 100).toStringAsFixed(0)}%';
    case DownloadStatus.paused:
      return '已暂停 · ${fmtBytes(e.downloadedBytes)} / ${fmtBytes(e.totalBytes)}';
    case DownloadStatus.complete:
      return '已完成 · ${fmtBytes(e.totalBytes)}';
    case DownloadStatus.failed:
      return '失败';
    case DownloadStatus.canceled:
      return '已取消';
  }
}
