import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/data/dtos/download_entry.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';
import 'package:animex_mobile/features/player/player_args.dart';

/// Looks up library entries once per session (heavy call). Detail pages
/// filter locally by title match.
final libraryListProvider = FutureProvider<LibraryResponse>((ref) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.library();
});

/// Cached history list. Detail uses it to seed playback resume positions;
/// the dedicated HistoryPage subscribes to the same provider.
final historyListProvider = FutureProvider((ref) async {
  final repo = await ref.watch(historyRepositoryProvider.future);
  return repo.list();
});

class DetailPage extends ConsumerStatefulWidget {
  final DetailArgs args;
  const DetailPage({super.key, required this.args});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  bool _subscribing = false;
  String? _subscribeMsg;
  bool _subscribeOk = false;

  Future<void> _subscribe() async {
    setState(() {
      _subscribing = true;
      _subscribeMsg = null;
    });
    try {
      final repo = await ref.read(subscriptionRepositoryProvider.future);
      await repo.subscribe(
        title: widget.args.title,
        subjectId: widget.args.subjectId,
        coverUrl: widget.args.coverUrl,
        summary: widget.args.summary,
      );
      setState(() {
        _subscribeOk = true;
        _subscribeMsg = '订阅成功';
        _subscribing = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _subscribeMsg = e.message;
        _subscribing = false;
      });
    } catch (e) {
      setState(() {
        _subscribeMsg = '$e';
        _subscribing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final libraryAsync = ref.watch(libraryListProvider);
    final matched = libraryAsync.maybeWhen(
      data: (lib) => lib.bangumi
          .where((b) => b.title == args.title)
          .cast<LibraryBangumi?>()
          .firstWhere((_) => true, orElse: () => null),
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(title: Text(args.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Hero(args: args),
          const SizedBox(height: 16),
          if (args.summary != null && args.summary!.isNotEmpty)
            Text(args.summary!, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 20),
          Text('剧集', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (matched != null && matched.episodes.isNotEmpty)
            _EpisodeGrid(bangumi: matched, detailArgs: args)
          else
            _EpisodeEmpty(loading: libraryAsync.isLoading),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_subscribing || _subscribeOk) ? null : _subscribe,
            icon: _subscribing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_subscribeOk ? Icons.check : Icons.bookmark_add_outlined),
            label: Text(_subscribeOk ? '已订阅' : '订阅'),
          ),
          if (_subscribeMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _subscribeMsg!,
                style: TextStyle(
                  color: _subscribeOk
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final DetailArgs args;
  const _Hero({required this.args});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          height: 160,
          child: (args.coverUrl == null || args.coverUrl!.isEmpty)
              ? Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.image_not_supported_outlined),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    args.coverUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(args.title,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (args.score > 0)
                Text('★ ${args.score.toStringAsFixed(1)}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary)),
              if (args.meta != null && args.meta!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    args.meta!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EpisodeGrid extends ConsumerWidget {
  final LibraryBangumi bangumi;
  final DetailArgs detailArgs;
  const _EpisodeGrid({required this.bangumi, required this.detailArgs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(serverConfigProvider);
    final historyAsync = ref.watch(historyListProvider);
    final downloads = ref.watch(downloadEntriesProvider);
    final baseUrl = configAsync.maybeWhen(
      data: (c) => c.baseUrl.trimRight(),
      orElse: () => '',
    );
    final history = historyAsync.asData?.value.entries ?? const [];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 64,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.4,
      ),
      itemCount: bangumi.episodes.length,
      itemBuilder: (context, i) {
        final ep = bangumi.episodes[i];
        final file = ep.files.isEmpty ? null : ep.files.first;
        final resumeSec = file == null
            ? 0
            : history
                .where((e) => e.fileId == file.id)
                .map((e) => e.positionSec)
                .followedBy(const [0])
                .first;
        final dlEntry = file == null ? null : downloads.entryFor(file.id);
        // Build full playlist so PlayerPage can auto-advance.
        final playlist = <PlayerArgs>[];
        if (baseUrl.isNotEmpty) {
          for (final pep in bangumi.episodes) {
            if (pep.files.isEmpty) continue;
            final pf = pep.files.first;
            final pDl = downloads.entryFor(pf.id);
            playlist.add(PlayerArgs(
              url: _absoluteUrl(baseUrl, pf.streamUrl),
              fileId: pf.id,
              title: '${bangumi.title} · ${pep.label}',
              bangumiTitle: bangumi.title,
              episode: pep.label,
              coverUrl: bangumi.coverUrl ?? detailArgs.coverUrl,
              localPath: pDl?.isComplete == true ? pDl!.localPath : null,
            ));
          }
        }
        final pIndex =
            file == null ? -1 : playlist.indexWhere((a) => a.fileId == file.id);
        return Stack(
          children: [
            OutlinedButton(
              onPressed: file == null || baseUrl.isEmpty
                  ? null
                  : () => context.push(
                        '/player',
                        extra: PlayerArgs(
                          url: _absoluteUrl(baseUrl, file.streamUrl),
                          fileId: file.id,
                          title: '${bangumi.title} · ${ep.label}',
                          bangumiTitle: bangumi.title,
                          episode: ep.label,
                          coverUrl: bangumi.coverUrl ?? detailArgs.coverUrl,
                          initialPositionSec: resumeSec,
                          localPath: dlEntry?.isComplete == true
                              ? dlEntry!.localPath
                              : null,
                          playlist: playlist,
                          currentIndex: pIndex < 0 ? 0 : pIndex,
                        ),
                      ),
              onLongPress: file == null || baseUrl.isEmpty
                  ? null
                  : () => _showEpisodeMenu(
                        context,
                        ref,
                        bangumi: bangumi,
                        episode: ep,
                        file: file,
                        baseUrl: baseUrl,
                        existing: dlEntry,
                      ),
              child: Text(ep.label, overflow: TextOverflow.ellipsis),
            ),
            if (dlEntry != null)
              Positioned(
                top: 2,
                right: 2,
                child: _DownloadBadge(entry: dlEntry),
              ),
          ],
        );
      },
    );
  }
}

class _DownloadBadge extends StatelessWidget {
  final DownloadEntry entry;
  const _DownloadBadge({required this.entry});

  @override
  Widget build(BuildContext context) {
    switch (entry.status) {
      case DownloadStatus.complete:
        return Icon(Icons.cloud_done,
            size: 14, color: Theme.of(context).colorScheme.primary);
      case DownloadStatus.running:
      case DownloadStatus.queued:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: entry.progress > 0 ? entry.progress : null,
          ),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle_outline, size: 14);
      case DownloadStatus.failed:
        return Icon(Icons.error_outline,
            size: 14, color: Theme.of(context).colorScheme.error);
      case DownloadStatus.canceled:
        return const SizedBox.shrink();
    }
  }
}

Future<void> _showEpisodeMenu(
  BuildContext context,
  WidgetRef ref, {
  required LibraryBangumi bangumi,
  required Episode episode,
  required PlayableFile file,
  required String baseUrl,
  required DownloadEntry? existing,
}) async {
  final manager = ref.read(downloadManagerProvider);
  final canDownload = existing == null ||
      existing.status == DownloadStatus.failed ||
      existing.status == DownloadStatus.canceled;
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('下载该集'),
            enabled: canDownload,
            onTap: () => Navigator.pop(ctx, 'download'),
          ),
          if (existing != null &&
              existing.status != DownloadStatus.complete)
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('取消下载'),
              onTap: () => Navigator.pop(ctx, 'cancel'),
            ),
          if (existing != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除离线文件'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
        ],
      ),
    ),
  );
  if (action == null) return;
  switch (action) {
    case 'download':
      final session = await ref.read(sessionStoreProvider).load();
      final headers = <String, String>{};
      if (session != null && session.token.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${session.token}';
      }
      await manager.enqueue(
        fileId: file.id,
        url: _absoluteUrl(baseUrl, file.streamUrl),
        bangumiTitle: bangumi.title,
        episode: episode.label,
        fileName: file.name,
        coverUrl: bangumi.coverUrl,
        headers: headers,
      );
    case 'cancel':
      await manager.cancel(file.id);
    case 'delete':
      await manager.deleteEntry(file.id);
  }
}

String _absoluteUrl(String base, String path) {
  if (path.isEmpty) return base;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  if (path.startsWith('/')) return '$base$path';
  return '$base/$path';
}

class _EpisodeEmpty extends StatelessWidget {
  final bool loading;
  const _EpisodeEmpty({required this.loading});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : const Text(
                '暂无剧集，订阅后会自动下载到媒体库',
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
