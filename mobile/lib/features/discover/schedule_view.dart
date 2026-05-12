import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/mikan_schedule.dart';
import 'package:animex_mobile/data/dtos/search_result.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';

/// Caches the Mikan schedule for the current session.
final mikanScheduleProvider = FutureProvider<MikanSchedule>((ref) async {
  final repo = await ref.watch(discoverRepositoryProvider.future);
  return repo.mikanSchedule();
});

class ScheduleView extends ConsumerWidget {
  const ScheduleView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(mikanScheduleProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mikanScheduleProvider),
      child: schedule.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorState(message: '$e', onRetry: () {
          ref.invalidate(mikanScheduleProvider);
        }),
        data: (sch) {
          if (sch.days.isEmpty) {
            return const _EmptyState(text: '暂无时间表数据');
          }
          return _ScheduleList(schedule: sch);
        },
      ),
    );
  }
}

class _ScheduleList extends StatelessWidget {
  final MikanSchedule schedule;
  const _ScheduleList({required this.schedule});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        for (final day in schedule.days) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                day.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          SliverPadding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.62,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = day.items[i];
                  return _ScheduleItemCard(item: item);
                },
                childCount: day.items.length,
              ),
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }
}

class _ScheduleItemCard extends StatelessWidget {
  final ScheduleItem item;
  const _ScheduleItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        // Bridge schedule item → search-result-shaped detail args. The
        // detail page accepts either path; here we have no torrent yet,
        // so subscribe button on detail page will just send the title.
        final stub = SearchResult(
          title: item.title,
          torrentUrl: '',
          coverUrl: item.coverUrl,
        );
        context.push(
          '/detail',
          extra: DetailArgs.fromSearch(stub, subjectId: item.id),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _Cover(url: item.coverUrl)),
          const SizedBox(height: 4),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (item.updated != null && item.updated!.isNotEmpty)
            Text(
              item.updated!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String? url;
  const _Cover({required this.url});

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});
  @override
  Widget build(BuildContext context) =>
      Center(child: Text(text, style: Theme.of(context).textTheme.bodyMedium));
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(message, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}
