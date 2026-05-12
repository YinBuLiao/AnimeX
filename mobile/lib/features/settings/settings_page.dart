import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';

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
            Text(
              '0.1.0',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
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
