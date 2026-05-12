import 'package:flutter/material.dart';

import 'package:animex_mobile/features/player/player_args.dart';

/// Bottom sheet that lists every episode in the current playlist and lets
/// the user jump to any one. The currently playing item is highlighted.
class EpisodePickerSheet extends StatelessWidget {
  final List<PlayerArgs> playlist;
  final int currentIndex;
  final ValueChanged<int> onPick;

  const EpisodePickerSheet({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (playlist.isEmpty) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂无剧集列表'),
        ),
      );
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text(
                    '剧集列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${currentIndex + 1} / ${playlist.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlist.length,
                itemBuilder: (_, i) {
                  final entry = playlist[i];
                  final isCurrent = i == currentIndex;
                  final hasLocal =
                      entry.localPath != null && entry.localPath!.isNotEmpty;
                  return ListTile(
                    leading: isCurrent
                        ? Icon(Icons.play_circle,
                            color: Theme.of(context).colorScheme.primary)
                        : const Icon(Icons.play_circle_outline),
                    title: Text(
                      entry.episode == null || entry.episode!.isEmpty
                          ? entry.title
                          : entry.episode!,
                      style: TextStyle(
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.normal,
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    trailing: hasLocal
                        ? Icon(
                            Icons.cloud_done,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    selected: isCurrent,
                    onTap: () {
                      Navigator.of(context).pop();
                      if (!isCurrent) onPick(i);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
