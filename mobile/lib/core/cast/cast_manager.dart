import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:animex_mobile/core/cast/cast_device.dart';
import 'package:animex_mobile/core/cast/dlna_device.dart';
import 'package:animex_mobile/core/cast/dlna_discovery.dart';
import 'package:animex_mobile/core/cast/dlna_renderer.dart';
import 'package:animex_mobile/core/cast/dlna_soap.dart';

typedef DlnaDiscoveryBuilder = DlnaDiscovery Function();
typedef DlnaRendererBuilder = DlnaRenderer Function(DlnaDevice device);

/// Orchestrates device discovery + active cast session for the player.
///
/// Today only DLNA is wired up; AirPlay (iOS) and Chromecast are stubbed
/// behind the same CastDevice surface so the UI does not need to branch.
class CastManager extends ChangeNotifier {
  final DlnaDiscoveryBuilder _discoveryBuilder;
  final DlnaRendererBuilder _rendererBuilder;

  final List<CastDevice> _devices = [];
  bool _discovering = false;
  CastDevice? _active;
  CastSessionStatus _status = CastSessionStatus.idle;
  String? _errorMessage;
  DlnaRenderer? _renderer;

  CastManager({
    DlnaDiscoveryBuilder? discoveryBuilder,
    DlnaRendererBuilder? rendererBuilder,
  })  : _discoveryBuilder = discoveryBuilder ?? (() => DlnaDiscovery()),
        _rendererBuilder =
            rendererBuilder ?? ((d) => DlnaRenderer(d));

  List<CastDevice> get devices => List.unmodifiable(_devices);
  bool get isDiscovering => _discovering;
  CastDevice? get activeDevice => _active;
  CastSessionStatus get status => _status;
  String? get errorMessage => _errorMessage;

  Future<void> discover() async {
    if (_discovering) return;
    _discovering = true;
    _devices.clear();
    notifyListeners();
    try {
      await for (final dev in _discoveryBuilder().search()) {
        _devices.add(CastDevice.fromDlna(dev));
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = '设备发现失败: $e';
    } finally {
      _discovering = false;
      notifyListeners();
    }
  }

  Future<void> cast({
    required CastDevice device,
    required String url,
    String title = '',
    Duration position = Duration.zero,
  }) async {
    _active = device;
    _status = CastSessionStatus.connecting;
    _errorMessage = null;
    notifyListeners();
    try {
      switch (device.kind) {
        case CastKind.dlna:
          final dlna = device.payload as DlnaDevice;
          final renderer = _rendererBuilder(dlna);
          _renderer = renderer;
          await renderer.setUri(url, metadata: _didlMetadata(url, title));
          if (position > Duration.zero) {
            try {
              await renderer.seek(position);
            } catch (_) {
              // Some renderers reject Seek before Play — ignore.
            }
          }
          await renderer.play();
          break;
        case CastKind.airplay:
        case CastKind.chromecast:
          throw UnimplementedError(
              '${device.kind.name} casting will be enabled in a follow-up.');
      }
      _status = CastSessionStatus.playing;
    } catch (e) {
      _status = CastSessionStatus.error;
      _errorMessage = '$e';
      _active = null;
      _renderer = null;
    }
    notifyListeners();
  }

  Future<void> pause() async {
    final r = _renderer;
    if (r == null) return;
    try {
      await r.pause();
      _status = CastSessionStatus.paused;
      notifyListeners();
    } catch (e) {
      _errorMessage = '$e';
      notifyListeners();
    }
  }

  Future<void> resume() async {
    final r = _renderer;
    if (r == null) return;
    try {
      await r.play();
      _status = CastSessionStatus.playing;
      notifyListeners();
    } catch (e) {
      _errorMessage = '$e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final r = _renderer;
    _renderer = null;
    _active = null;
    _status = CastSessionStatus.idle;
    notifyListeners();
    if (r == null) return;
    try {
      await r.stop();
    } catch (_) {
      // Best-effort stop.
    }
  }

  Future<PositionInfo?> currentPosition() async {
    final r = _renderer;
    if (r == null) return null;
    try {
      return await r.getPositionInfo();
    } catch (_) {
      return null;
    }
  }

  String _didlMetadata(String url, String title) {
    if (title.isEmpty) return '';
    final t = title
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="1" parentID="0" restricted="1">'
        '<dc:title>$t</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:video/mp4:*">$url</res>'
        '</item></DIDL-Lite>';
  }
}
