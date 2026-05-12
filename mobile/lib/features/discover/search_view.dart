import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/network/api_exception.dart';
import 'package:animex_mobile/data/dtos/search_result.dart';
import 'package:animex_mobile/features/detail/detail_args.dart';

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
      return const Center(child: Text('输入关键词开始搜索'));
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
}

class _ResultTile extends StatelessWidget {
  final SearchResult result;
  const _ResultTile({required this.result});

  @override
  Widget build(BuildContext context) {
    final cover = result.coverUrl;
    return ListTile(
      onTap: () => context.push(
        '/detail',
        extra: DetailArgs.fromSearch(result),
      ),
      leading: SizedBox(
        width: 48,
        height: 64,
        child: (cover == null || cover.isEmpty)
            ? Container(
                color:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.image_not_supported_outlined),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  cover,
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
