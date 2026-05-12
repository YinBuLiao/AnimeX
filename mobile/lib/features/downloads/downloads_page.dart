import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/download_entry.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/features/detail/detail_page.dart'
    show libraryListProvider;
import 'package:animex_mobile/features/player/player_args.dart';
import 'package:animex_mobile/features/player/player_launcher.dart';

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

    final hasRunning =
        running.any((e) => e.status == DownloadStatus.running);
    final hasPaused = running.any((e) => e.status == DownloadStatus.paused);

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载'),
        actions: [
          if (hasRunning)
            IconButton(
              icon: const Icon(Icons.pause_circle_outline),
              tooltip: '全部暂停',
              onPressed: () async {
                final n = await ref.read(downloadManagerProvider).pauseAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已暂停 $n 个任务')),
                  );
                }
              },
            ),
          if (hasPaused)
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: '全部继续',
              onPressed: () async {
                final n = await ref.read(downloadManagerProvider).resumeAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已恢复 $n 个任务')),
                  );
                }
              },
            ),
          if (failed.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: '清理失败',
              onPressed: () async {
                final n = await ref
                    .read(downloadManagerProvider)
                    .clearFinishedFailures();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已清理 $n 条失败记录')),
                  );
                }
              },
            ),
        ],
      ),
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

  void _play(BuildContext context, WidgetRef ref) {
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
        coverUrlFallback: entry.coverUrl,
      );
    }
    args ??= PlayerArgs(
      url: entry.url,
      fileId: entry.fileId,
      title: entry.episode == null
          ? entry.bangumiTitle
          : '${entry.bangumiTitle} · ${entry.episode}',
      bangumiTitle: entry.bangumiTitle,
      episode: entry.episode,
      coverUrl: entry.coverUrl,
      localPath: entry.isComplete ? entry.localPath : null,
    );
    context.push('/player', extra: args);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(downloadManagerProvider);
    return ListTile(
      onTap: entry.isComplete ? () => _play(context, ref) : null,
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
              _play(context, ref);
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
