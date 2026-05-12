import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/history_entry.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';
import 'package:animex_mobile/features/detail/detail_page.dart' show libraryListProvider;
import 'package:animex_mobile/features/player/player_args.dart';

final _historyProvider = FutureProvider<List<HistoryEntry>>((ref) async {
  final repo = await ref.watch(historyRepositoryProvider.future);
  final resp = await repo.list();
  return resp.entries;
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AnimeX'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: session.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('错误：$e')),
        data: (s) {
          if (s == null) return const Center(child: Text('未登录'));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_historyProvider);
              ref.invalidate(libraryListProvider);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                _Greeting(username: s.username),
                const SizedBox(height: 16),
                _ContinueWatchingSection(),
                const SizedBox(height: 16),
                _LibrarySection(
                  title: '最近更新',
                  emptyHint: '订阅番剧后会出现在这里',
                  showAll: false,
                ),
                const SizedBox(height: 16),
                _LibrarySection(
                  title: '我的订阅',
                  emptyHint: '在「发现」中订阅番剧',
                  showAll: true,
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final String username;
  const _Greeting({required this.username});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        '你好，$username',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const _SectionHeader({required this.title, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              child: const Text('查看全部'),
            ),
        ],
      ),
    );
  }
}

class _ContinueWatchingSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_historyProvider);
    final entries = async.maybeWhen(
      data: (e) => e.take(8).toList(),
      orElse: () => const <HistoryEntry>[],
    );
    if (async.isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          _SectionHeader(title: '继续观看'),
          SizedBox(
            height: 170,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: '继续观看',
          onMore: () => context.push('/history'),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _HistoryCard(entry: entries[i]),
          ),
        ),
      ],
    );
  }
}

class _HistoryCard extends ConsumerWidget {
  final HistoryEntry entry;
  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = entry.durationSec > 0
        ? (entry.positionSec / entry.durationSec).clamp(0.0, 1.0)
        : 0.0;
    final title = entry.bangumiTitle.isEmpty ? '未知番剧' : entry.bangumiTitle;
    final ep = entry.episode == null || entry.episode!.isEmpty
        ? ''
        : ' · ${entry.episode}';
    return SizedBox(
      width: 120,
      child: InkWell(
        onTap: () => context.push(
          '/player',
          extra: PlayerArgs(
            url: entry.url ?? '',
            fileId: entry.fileId,
            title: '$title$ep',
            bangumiTitle: entry.bangumiTitle,
            episode: entry.episode,
            coverUrl: entry.coverUrl,
            initialPositionSec: entry.positionSec,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                children: [
                  Positioned.fill(child: _cover(context, entry.coverUrl)),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            if (ep.isNotEmpty)
              Text(
                ep.substring(3),
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

  Widget _cover(BuildContext ctx, String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
        return Container(
          color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined),
        );
      }),
    );
  }
}

class _LibrarySection extends ConsumerWidget {
  final String title;
  final String emptyHint;
  final bool showAll;

  const _LibrarySection({
    required this.title,
    required this.emptyHint,
    required this.showAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(libraryListProvider);
    return async.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(title: title),
          const SizedBox(
            height: 170,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
      error: (e, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(title: title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$e',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      ),
      data: (lib) {
        if (lib.bangumi.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(title: title),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  emptyHint,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            ],
          );
        }
        final items = showAll
            ? lib.bangumi
            : lib.bangumi.take(8).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(title: title),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _BangumiCard(item: items[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BangumiCard extends StatelessWidget {
  final LibraryBangumi item;
  const _BangumiCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: InkWell(
        onTap: () => context.push(
          '/detail',
          extra: DetailArgs.fromLibraryBangumi(item),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: item.coverUrl == null || item.coverUrl!.isEmpty
                  ? Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported_outlined),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        item.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              '${item.episodes.length} 集',
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
