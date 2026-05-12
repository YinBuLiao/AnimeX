import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/data/dtos/admin_dtos.dart';

final _monitorProvider = FutureProvider<AdminMonitor>((ref) async {
  final repo = await ref.watch(adminRepositoryProvider.future);
  return repo.monitor();
});

class AdminMonitorPage extends ConsumerWidget {
  const AdminMonitorPage({super.key});

  String _formatBytes(int b) {
    if (b <= 0) return '0 B';
    if (b > 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b > 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b > 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_monitorProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统监控'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_monitorProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (m) => ListView(
          children: [
            _RuntimeCard(
              uptime: m.uptime,
              goroutines: m.goroutines,
              memoryAlloc: _formatBytes(m.memoryAlloc),
              memorySys: _formatBytes(m.memorySys),
            ),
            const Divider(height: 1),
            const _SectionHeader('服务就绪'),
            _ServiceRow(label: 'MySQL', ready: m.mysqlReady),
            _ServiceRow(label: 'Redis', ready: m.redisReady),
            _ServiceRow(label: 'PikPak', ready: m.pikpakReady),
            _ServiceRow(
              label: '存储 (${m.storageProvider})',
              ready: m.storageReady,
            ),
            const Divider(height: 1),
            const _SectionHeader('安装状态'),
            _ServiceRow(label: '已安装', ready: m.installed),
            _ServiceRow(label: '仅安装模式', ready: m.installOnly),
          ],
        ),
      ),
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  final String uptime;
  final int goroutines;
  final String memoryAlloc;
  final String memorySys;

  const _RuntimeCard({
    required this.uptime,
    required this.goroutines,
    required this.memoryAlloc,
    required this.memorySys,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('运行时',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _kv('运行时间', uptime),
              _kv('Goroutines', '$goroutines'),
              _kv('内存分配', memoryAlloc),
              _kv('系统内存', memorySys),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
        ]),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
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

class _ServiceRow extends StatelessWidget {
  final String label;
  final bool ready;
  const _ServiceRow({required this.label, required this.ready});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        ready ? Icons.check_circle : Icons.cancel,
        color: ready
            ? Colors.green
            : Theme.of(context).colorScheme.error,
      ),
      title: Text(label),
      trailing: Text(
        ready ? '就绪' : '未就绪',
        style: TextStyle(
          color: ready
              ? Colors.green
              : Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}
