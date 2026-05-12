import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/core/preferences/search_history.dart';
import 'package:animex_mobile/core/widgets/cover_image.dart';
import 'package:animex_mobile/data/dtos/library_bangumi.dart';
import 'package:animex_mobile/data/dtos/search_result.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';
import 'package:animex_mobile/features/detail/detail_page.dart'
    show libraryListProvider;

class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _busy = false;
  String _query = '';
  List<SearchResult>? _results;
  String? _error;
  SearchHistoryStore? _historyStore;
  List<String> _history = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final store = await SearchHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _historyStore = store;
      _history = store.all;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _runSearch(text);
    });
  }

  Future<void> _runSearch(String text) async {
    final q = text.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(discoverRepositoryProvider.future);
      final resp = await repo.search(q);
      if (!mounted || _query != q) return;
      setState(() {
        _results = resp.results;
        _busy = false;
      });
      final store = _historyStore;
      if (store != null) {
        await store.add(q);
        if (mounted) setState(() => _history = store.all);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: '搜索番剧标题',
              suffixIcon: _ctrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _ctrl.clear();
                        _runSearch('');
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _runSearch,
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_results == null) {
      return _historyBody();
    }
    if (_results!.isEmpty) {
      return Center(child: Text('未找到与 "$_query" 匹配的结果'));
    }
    return ListView.separated(
      itemCount: _results!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _ResultTile(result: _results![i]),
    );
  }

  Widget _historyBody() {
    if (_history.isEmpty) {
      return const Center(child: Text('输入关键词开始搜索'));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '历史搜索',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await _historyStore?.clear();
                  if (mounted) setState(() => _history = const <String>[]);
                },
                child: const Text('清空'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final q in _history)
                InputChip(
                  label: Text(q),
                  onPressed: () {
                    _ctrl.text = q;
                    _ctrl.selection =
                        TextSelection.collapsed(offset: q.length);
                    _runSearch(q);
                  },
                  onDeleted: () async {
                    await _historyStore?.remove(q);
                    if (mounted) {
                      setState(() => _history =
                          _historyStore?.all ?? const <String>[]);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends ConsumerWidget {
  final SearchResult result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = result.coverUrl;
    final libAsync = ref.watch(libraryListProvider);
    final inLib = libAsync.maybeWhen(
      data: (lib) {
        final title = result.bangumiTitle ?? result.title;
        return lib.bangumi.any((LibraryBangumi b) => b.title == title);
      },
      orElse: () => false,
    );
    return ListTile(
      onTap: () => context.push(
        '/detail',
        extra: DetailArgs.fromSearch(result),
      ),
      trailing: inLib
          ? Icon(
              Icons.video_library,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
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
        result.bangumiTitle ?? result.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (result.episodeLabel != null) 'EP ${result.episodeLabel}',
          if (result.size != null) result.size!,
          if (result.updated != null) result.updated!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
