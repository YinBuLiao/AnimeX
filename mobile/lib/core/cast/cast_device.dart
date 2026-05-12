import 'package:animex_mobile/core/cast/dlna_device.dart';

enum CastKind { dlna, airplay, chromecast }

/// Generic representation of a discovered cast target. The underlying
/// vendor-specific handle (e.g. DlnaDevice) is carried in `payload`.
class CastDevice {
  final CastKind kind;
  final String id;
  final String name;
  final String? modelLabel;
  final Object payload;

  const CastDevice({
    required this.kind,
    required this.id,
    required this.name,
    required this.payload,
    this.modelLabel,
  });

  factory CastDevice.fromDlna(DlnaDevice d) => CastDevice(
        kind: CastKind.dlna,
        id: 'dlna:${d.id}',
        name: d.friendlyName,
        modelLabel: d.modelName.isNotEmpty ? d.modelName : null,
        payload: d,
      );
}

enum CastSessionStatus { idle, connecting, playing, paused, error }
