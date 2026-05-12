import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:animex_mobile/app/providers.dart';
import 'package:animex_mobile/core/cast/cast_device.dart';

class CastPickerSheet extends ConsumerStatefulWidget {
  final void Function(CastDevice device) onPick;
  const CastPickerSheet({super.key, required this.onPick});

  @override
  ConsumerState<CastPickerSheet> createState() => _CastPickerSheetState();
}

class _CastPickerSheetState extends ConsumerState<CastPickerSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(castManagerProvider).discover();
    });
  }

  String _kindLabel(CastKind k) {
    switch (k) {
      case CastKind.dlna:
        return 'DLNA';
      case CastKind.airplay:
        return 'AirPlay';
      case CastKind.chromecast:
        return 'Chromecast';
    }
  }

  IconData _kindIcon(CastKind k) {
    switch (k) {
      case CastKind.dlna:
        return Icons.tv_outlined;
      case CastKind.airplay:
        return Icons.airplay;
      case CastKind.chromecast:
        return Icons.cast;
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(castManagerProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('选择投屏设备',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (manager.isDiscovering)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: '重新扫描',
                    onPressed: () => manager.discover(),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (manager.devices.isEmpty && !manager.isDiscovering)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    '未发现设备\n请确认设备与手机处于同一 Wi-Fi 网络',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: manager.devices.length,
                  itemBuilder: (_, i) {
                    final d = manager.devices[i];
                    return ListTile(
                      leading: Icon(_kindIcon(d.kind)),
                      title: Text(d.name),
                      subtitle: Text(
                        [_kindLabel(d.kind), d.modelLabel]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        widget.onPick(d);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'AirPlay / Chromecast 将在真机阶段开放',
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
