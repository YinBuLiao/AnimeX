import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/download/download_manager.dart';
import 'package:animex_mobile/data/repositories/history_repository.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('播放'),
          SwitchListTile(
            secondary: const Icon(Icons.skip_next_outlined),
            title: const Text('自动播放下一集'),
            subtitle: const Text('视频结束时自动加载同一番剧的下一集'),
            value: prefs.autoPlayNext,
            onChanged: prefs.setAutoPlayNext,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.high_quality_outlined),
            title: const Text('优先高画质'),
            subtitle: const Text('同一剧集多源时挑选体积最大的文件'),
            value: prefs.preferHighQuality,
            onChanged: prefs.setPreferHighQuality,
          ),
          ListTile(
            leading: const Icon(Icons.volume_up_outlined),
            title: const Text('默认音量'),
            subtitle: Slider(
              value: prefs.defaultVolume,
              min: 0,
              max: 100,
              divisions: 20,
              label: '${prefs.defaultVolume.round()}%',
              onChanged: prefs.setDefaultVolume,
            ),
            trailing: Text('${prefs.defaultVolume.round()}%'),
          ),
          const Divider(height: 1),
          const _SectionHeader('外观'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('主题'),
            subtitle: Text(_themeLabel(prefs.themeMode)),
            onTap: () => _pickTheme(context, ref),
          ),
          const Divider(height: 1),
          const _SectionHeader('存储'),
          const _CacheSection(),
          const Divider(height: 1),
          const _SectionHeader('其他'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于 AnimeX'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
    );
  }
}

String _themeLabel(ThemeMode m) {
  switch (m) {
    case ThemeMode.system:
      return '跟随系统';
    case ThemeMode.light:
      return '浅色';
    case ThemeMode.dark:
      return '深色';
  }
}

Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(appPreferencesProvider);
  final current = prefs.themeMode;
  final picked = await showModalBottomSheet<ThemeMode>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in ThemeMode.values)
            ListTile(
              leading: Icon(
                m == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: m == current
                    ? Theme.of(ctx).colorScheme.primary
                    : null,
              ),
              title: Text(_themeLabel(m)),
              onTap: () => Navigator.of(ctx).pop(m),
            ),
        ],
      ),
    ),
  );
  if (picked != null) await prefs.setThemeMode(picked);
}

class _CacheSection extends ConsumerStatefulWidget {
  const _CacheSection();

  @override
  ConsumerState<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends ConsumerState<_CacheSection> {
  int? _downloadBytes;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _scanning = true);
    final dl = ref.read(downloadManagerProvider);
    final bytes = await dl.totalDiskBytes();
    if (mounted) {
      setState(() {
        _downloadBytes = bytes;
        _scanning = false;
      });
    }
  }

  Future<void> _confirmClearDownloads(DownloadManager dl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空所有下载？'),
        content: const Text('所有已下载的剧集都会被删除，本地缓存空间将被释放。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final count = await dl.clearAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空 $count 个下载')),
      );
    }
    await _refresh();
  }

  Future<void> _confirmClearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空观看历史？'),
        content: const Text('断点续播信息将丢失，下次观看从头开始。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final HistoryRepository repo =
          await ref.read(historyRepositoryProvider.future);
      await repo.clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清空观看历史')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清空失败：$e')),
        );
      }
    }
  }

  String _formatBytes(int b) {
    if (b <= 0) return '0 B';
    if (b > 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b > 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b > 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    final dl = ref.watch(downloadEntriesProvider);
    final count = dl.entries.where((e) => e.isComplete).length;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.sd_card_outlined),
          title: const Text('已下载剧集'),
          subtitle: _scanning
              ? const Text('计算中…')
              : Text('$count 个文件 · ${_formatBytes(_downloadBytes ?? 0)}'),
          trailing: TextButton(
            onPressed: count == 0 ? null : () => _confirmClearDownloads(dl),
            child: const Text('清空'),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.history_outlined),
          title: const Text('观看历史'),
          subtitle: const Text('清空后断点续播失效'),
          trailing: TextButton(
            onPressed: _confirmClearHistory,
            child: const Text('清空'),
          ),
        ),
      ],
    );
  }
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

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.movie_filter_outlined, size: 56),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'AnimeX',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (_, snap) {
                final info = snap.data;
                final label = info == null
                    ? '…'
                    : 'v${info.version} (${info.buildNumber})';
                return Text(
                  label,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline),
                );
              },
            ),
            const SizedBox(height: 32),
            Text(
              '一个用 Flutter 打造的追番应用，连接自托管的 AnimeX 服务器，'
              '支持播放、下载、投屏、画中画与管理端审批。',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 24),
            const _LinkRow(
              icon: Icons.description_outlined,
              label: '签名 & 打包指南',
              detail: 'docs/mobile-signing.md',
            ),
            const _LinkRow(
              icon: Icons.code_outlined,
              label: '后端项目',
              detail: 'bangumi-pikpak',
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  const _LinkRow({required this.icon, required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            detail,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
