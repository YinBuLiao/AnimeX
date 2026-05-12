import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/core/cast/cast_device.dart';
import 'package:animex_mobile/core/cast/cast_manager.dart';
import 'package:animex_mobile/core/cast/dlna_device.dart';
import 'package:animex_mobile/core/cast/dlna_renderer.dart';
import 'package:animex_mobile/core/cast/dlna_soap.dart';

class _RecordingTransport {
  final List<String> actions = [];
  final Map<String, String> responses;

  _RecordingTransport({this.responses = const {}});

  Future<String> call({
    required Uri controlUrl,
    required String action,
    required String envelope,
  }) async {
    actions.add(action);
    return responses[action] ?? '<ok/>';
  }
}

DlnaDevice _fakeDevice() => DlnaDevice(
      id: 'uuid:fake',
      friendlyName: 'Fake TV',
      manufacturer: '',
      modelName: '',
      location: Uri.parse('http://10.0.0.5/desc.xml'),
      controlUrl: Uri.parse('http://10.0.0.5/avt/control'),
    );

void main() {
  test('cast() sets URI, seeks (when position>0), and plays', () async {
    final transport = _RecordingTransport();
    final manager = CastManager(
      rendererBuilder: (d) => DlnaRenderer(d, transport: transport.call),
    );
    final device = CastDevice.fromDlna(_fakeDevice());

    await manager.cast(
      device: device,
      url: 'http://x/v.mp4',
      title: 'Episode 1',
      position: const Duration(seconds: 30),
    );

    expect(transport.actions, ['SetAVTransportURI', 'Seek', 'Play']);
    expect(manager.status, CastSessionStatus.playing);
    expect(manager.activeDevice, device);
  });

  test('cast() skips Seek when position is zero', () async {
    final transport = _RecordingTransport();
    final manager = CastManager(
      rendererBuilder: (d) => DlnaRenderer(d, transport: transport.call),
    );

    await manager.cast(
      device: CastDevice.fromDlna(_fakeDevice()),
      url: 'http://x/v.mp4',
    );

    expect(transport.actions, ['SetAVTransportURI', 'Play']);
  });

  test('stop() clears active device and resets status', () async {
    final transport = _RecordingTransport();
    final manager = CastManager(
      rendererBuilder: (d) => DlnaRenderer(d, transport: transport.call),
    );

    await manager.cast(
      device: CastDevice.fromDlna(_fakeDevice()),
      url: 'http://x/v.mp4',
    );
    await manager.stop();

    expect(manager.activeDevice, isNull);
    expect(manager.status, CastSessionStatus.idle);
    expect(transport.actions.last, 'Stop');
  });

  test('AirPlay/Chromecast cast surfaces UnimplementedError', () async {
    final manager = CastManager();
    final dev = CastDevice(
      kind: CastKind.chromecast,
      id: 'chromecast:abc',
      name: 'Living Room',
      payload: const Object(),
    );
    await manager.cast(device: dev, url: 'http://x/v.mp4');
    expect(manager.status, CastSessionStatus.error);
    expect(manager.errorMessage, contains('chromecast'));
  });

  test('pause / resume flip status when a session is active', () async {
    final transport = _RecordingTransport();
    final manager = CastManager(
      rendererBuilder: (d) => DlnaRenderer(d, transport: transport.call),
    );

    await manager.cast(
      device: CastDevice.fromDlna(_fakeDevice()),
      url: 'http://x/v.mp4',
    );
    await manager.pause();
    expect(manager.status, CastSessionStatus.paused);
    await manager.resume();
    expect(manager.status, CastSessionStatus.playing);
  });

  test('currentPosition parses GetPositionInfo response', () async {
    final transport = _RecordingTransport(responses: {
      'GetPositionInfo': '''
<s:Envelope><s:Body><u:GetPositionInfoResponse>
  <TrackDuration>00:20:00</TrackDuration>
  <RelTime>00:01:30</RelTime>
  <TrackURI>http://x/v.mp4</TrackURI>
</u:GetPositionInfoResponse></s:Body></s:Envelope>''',
    });
    final manager = CastManager(
      rendererBuilder: (d) => DlnaRenderer(d, transport: transport.call),
    );
    await manager.cast(
      device: CastDevice.fromDlna(_fakeDevice()),
      url: 'http://x/v.mp4',
    );
    final info = await manager.currentPosition();
    expect(info, isNotNull);
    expect(info!.relTime, const Duration(seconds: 90));
    expect(info.trackDuration, const Duration(minutes: 20));
  });
}
