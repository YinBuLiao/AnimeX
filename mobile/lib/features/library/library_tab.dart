import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/download/download_manager.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/preferences/app_preferences.dart';
import 'package:animex_mobile/data/dtos/history_entry.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';
import 'package:animex_mobile/features/detail/detail_page.dart';

class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libAsync = ref.watch(libraryListProvider);
    final prefs = ref.watch(appPreferencesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<LibrarySort>(
            icon: const Icon(Icons.sort),
            tooltip: '排序：${prefs.librarySort.label}',
            onSelected: prefs.setLibrarySort,
            itemBuilder: (_) => [
              for (final s in LibrarySort.values)
                CheckedPopupMenuItem(
                  value: s,
                  checked: prefs.librarySort == s,
                  child: Text(s.label),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: '下载',
            onPressed: () => context.push('/downloads'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(libraryListProvider),
        child: libAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _libraryError(context, e, () {
            ref.invalidate(libraryListProvider);
          }),
          data: (lib) {
            if (lib.bangumi.isEmpty) {
              return const _EmptyState();
            }
            final history = ref.watch(historyListProvider).asData?.value
                    .entries ??
                const <HistoryEntry>[];
            final sorted = _sort(
              lib.bangumi,
              prefs.librarySort,
              history,
            );
            return _Grid(
              items: sorted,
              downloads: ref.watch(downloadEntriesProvider),
            );
          },
        ),
      ),
    );
  }

  List<LibraryBangumi> _sort(
    List<LibraryBangumi> items,
    LibrarySort sort,
    List<HistoryEntry> history,
  ) {
    final sorted = items.toList();
    switch (sort) {
      case LibrarySort.titleAscending:
        sorted.sort((a, b) => a.title.compareTo(b.title));
        return sorted;
      case LibrarySort.episodeCountDescending:
        sorted.sort((a, b) => b.episodes.length.compareTo(a.episodes.length));
        return sorted;
      case LibrarySort.recentlyWatched:
        final fileIds = <String, int>{
          for (final h in history) h.fileId: h.updatedAt,
        };
        int recent(LibraryBangumi b) {
          var best = 0;
          for (final ep in b.episodes) {
            for (final f in ep.files) {
              final ts = fileIds[f.id];
              if (ts != null && ts > best) best = ts;
            }
          }
          return best;
        }

        sorted.sort((a, b) {
          final ra = recent(a);
          final rb = recent(b);
          if (ra != rb) return rb.compareTo(ra);
          return a.title.compareTo(b.title);
        });
        return sorted;
    }
  }

  Widget _libraryError(
      BuildContext context, Object e, VoidCallback onRetry) {
    final msg = (e is ApiException && e.statusCode == 403)
        ? '媒体库快照不可用，请等待管理员扫描后重试。'
        : '$e';
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.cloud_off_outlined, size: 32),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(msg, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
        Center(child: TextButton(onPressed: onRetry, child: const Text('重试'))),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  final List<LibraryBangumi> items;
  final DownloadManager downloads;
  const _Grid({required this.items, required this.downloads});

  bool _bangumiHasOffline(LibraryBangumi b) {
    for (final ep in b.episodes) {
      for (final f in ep.files) {
        if (downloads.isComplete(f.id)) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.6,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final b = items[i];
        return InkWell(
          onTap: () => context.push(
            '/detail',
            extra: DetailArgs.fromLibraryBangumi(b),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: (b.coverUrl == null || b.coverUrl!.isEmpty)
                          ? Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(
                                  Icons.image_not_supported_outlined),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(b.coverUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        child: const Icon(
                                            Icons.broken_image_outlined),
                                      )),
                            ),
                    ),
                    if (_bangumiHasOffline(b))
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.cloud_done,
                              size: 12, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                b.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '${b.episodes.length} 集',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 100),
        Icon(Icons.video_library_outlined, size: 36),
        SizedBox(height: 12),
        Center(child: Text('媒体库为空')),
        SizedBox(height: 4),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '在「发现」中订阅番剧，下载完成后会自动出现在这里。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
