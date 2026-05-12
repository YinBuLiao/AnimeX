import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/widgets/cover_image.dart';
import 'package:animex_mobile/data/dtos/bangumi_subject.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';

/// In-memory list of currently loaded subjects + pagination cursor.
class RankingState {
  final List<BangumiSubject> subjects;
  final int nextOffset;
  final bool hasMore;
  final bool loading;
  final String? error;

  const RankingState({
    this.subjects = const [],
    this.nextOffset = 0,
    this.hasMore = true,
    this.loading = false,
    this.error,
  });

  RankingState copyWith({
    List<BangumiSubject>? subjects,
    int? nextOffset,
    bool? hasMore,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      RankingState(
        subjects: subjects ?? this.subjects,
        nextOffset: nextOffset ?? this.nextOffset,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class RankingController extends StateNotifier<RankingState> {
  static const int pageSize = 24;
  final Ref _ref;
  RankingController(this._ref) : super(const RankingState()) {
    loadNext();
  }

  Future<void> loadNext() async {
    if (state.loading || !state.hasMore) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final repo = await _ref.read(discoverRepositoryProvider.future);
      final page = await repo.bangumiDiscover(
        offset: state.nextOffset,
        limit: pageSize,
      );
      state = state.copyWith(
        subjects: [...state.subjects, ...page.subjects],
        nextOffset: state.nextOffset + page.subjects.length,
        hasMore: page.hasMore,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> refresh() async {
    state = const RankingState();
    await loadNext();
  }
}

final rankingControllerProvider =
    StateNotifierProvider<RankingController, RankingState>(
        RankingController.new);

class RankingView extends ConsumerStatefulWidget {
  const RankingView({super.key});

  @override
  ConsumerState<RankingView> createState() => _RankingViewState();
}

class _RankingViewState extends ConsumerState<RankingView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  void _maybeLoadMore() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 400) {
      ref.read(rankingControllerProvider.notifier).loadNext();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rankingControllerProvider);
    if (state.subjects.isEmpty) {
      if (state.error != null) {
        return _ErrorState(
          message: state.error!,
          onRetry: () =>
              ref.read(rankingControllerProvider.notifier).refresh(),
        );
      }
      if (state.loading) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(child: Text('暂无排行数据'));
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(rankingControllerProvider.notifier).refresh(),
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.55,
        ),
        itemCount: state.subjects.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= state.subjects.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _SubjectCard(subject: state.subjects[i]);
        },
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final BangumiSubject subject;
  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(
        '/detail',
        extra: DetailArgs.fromBangumiSubject(subject),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _Cover(url: subject.coverUrl)),
          const SizedBox(height: 4),
          Text(
            subject.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          if (subject.score > 0)
            Text(
              '★ ${subject.score.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
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
    return CoverImage(
      url: url,
      cacheWidth: 360,
      borderRadius: BorderRadius.circular(6),
    );
  }
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
