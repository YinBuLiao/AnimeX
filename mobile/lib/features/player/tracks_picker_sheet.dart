import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Bottom sheet that lists every available audio + subtitle track on the
/// current media. mpv exposes `auto` / `no` sentinels plus per-stream
/// entries with optional language/title metadata.
class TracksPickerSheet extends StatelessWidget {
  final Tracks tracks;
  final Track selected;
  final ValueChanged<AudioTrack> onPickAudio;
  final ValueChanged<SubtitleTrack> onPickSubtitle;

  const TracksPickerSheet({
    super.key,
    required this.tracks,
    required this.selected,
    required this.onPickAudio,
    required this.onPickSubtitle,
  });

  String _audioLabel(AudioTrack t) {
    if (t.id == 'auto') return '自动';
    if (t.id == 'no') return '关闭';
    final parts = <String>[
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.language != null && t.language!.isNotEmpty) t.language!,
    ];
    return parts.isEmpty ? '音轨 ${t.id}' : parts.join(' · ');
  }

  String _subtitleLabel(SubtitleTrack t) {
    if (t.id == 'auto') return '自动';
    if (t.id == 'no') return '关闭';
    final parts = <String>[
      if (t.title != null && t.title!.isNotEmpty) t.title!,
      if (t.language != null && t.language!.isNotEmpty) t.language!,
    ];
    return parts.isEmpty ? '字幕 ${t.id}' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '字幕与音轨',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const Divider(height: 1),
              _SectionHeader(
                icon: Icons.volume_up_outlined,
                label: '音轨',
                count: tracks.audio.length,
              ),
              for (final t in tracks.audio)
                ListTile(
                  dense: true,
                  leading: Icon(
                    t == selected.audio
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: t == selected.audio
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    _audioLabel(t),
                    style: TextStyle(
                      fontWeight: t == selected.audio
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    onPickAudio(t);
                  },
                ),
              const Divider(height: 1),
              _SectionHeader(
                icon: Icons.closed_caption_outlined,
                label: '字幕',
                count: tracks.subtitle.length,
              ),
              for (final t in tracks.subtitle)
                ListTile(
                  dense: true,
                  leading: Icon(
                    t == selected.subtitle
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: t == selected.subtitle
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  title: Text(
                    _subtitleLabel(t),
                    style: TextStyle(
                      fontWeight: t == selected.subtitle
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    onPickSubtitle(t);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.outline),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.outline,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
