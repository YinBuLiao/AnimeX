import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

final _overviewProvider = FutureProvider<AdminOverview>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  return repo.overview();
});

class AdminOverviewPage extends ConsumerWidget {
  const AdminOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_overviewProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('数据概览')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_overviewProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('$e', textAlign: TextAlign.center),
          )),
          data: (o) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.05,
                ),
                itemCount: o.cards.length,
                itemBuilder: (_, i) => _Card(card: o.cards[i]),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '存储：${o.storageProvider}    最近更新：${o.libraryUpdatedAt}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final AdminOverviewCard card;
  const _Card({required this.card});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.icon, style: const TextStyle(fontSize: 20)),
            const Spacer(),
            Text(card.value,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(card.label,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              card.trend,
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
