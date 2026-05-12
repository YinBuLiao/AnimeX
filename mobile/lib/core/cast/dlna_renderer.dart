import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animex_mobile/core/cast/dlna_device.dart';
import 'package:animex_mobile/core/cast/dlna_soap.dart';

typedef SoapTransport = Future<String> Function({
  required Uri controlUrl,
  required String action,
  required String envelope,
});

class DlnaRenderer {
  final DlnaDevice device;
  final SoapTransport transport;

  DlnaRenderer(this.device, {SoapTransport? transport})
      : transport = transport ?? _defaultTransport;

  Future<void> setUri(String url, {String metadata = ''}) async {
    await transport(
      controlUrl: device.controlUrl,
      action: 'SetAVTransportURI',
      envelope: buildSetAvTransportUri(uri: url, metadata: metadata),
    );
  }

  Future<void> play() async {
    await transport(
      controlUrl: device.controlUrl,
      action: 'Play',
      envelope: buildPlay(),
    );
  }

  Future<void> pause() async {
    await transport(
      controlUrl: device.controlUrl,
      action: 'Pause',
      envelope: buildPause(),
    );
  }

  Future<void> stop() async {
    await transport(
      controlUrl: device.controlUrl,
      action: 'Stop',
      envelope: buildStop(),
    );
  }

  Future<void> seek(Duration position) async {
    await transport(
      controlUrl: device.controlUrl,
      action: 'Seek',
      envelope: buildSeek(position),
    );
  }

  Future<PositionInfo> getPositionInfo() async {
    final resp = await transport(
      controlUrl: device.controlUrl,
      action: 'GetPositionInfo',
      envelope: buildGetPositionInfo(),
    );
    return parsePositionInfoResponse(resp);
  }
}

Future<String> _defaultTransport({
  required Uri controlUrl,
  required String action,
  required String envelope,
}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 4);
  try {
    final req = await client.postUrl(controlUrl);
    req.headers.set('Content-Type', 'text/xml; charset="utf-8"');
    req.headers.set('SOAPACTION', soapAction(action));
    req.headers.set('Connection', 'close');
    req.add(utf8.encode(envelope));
    final res = await req.close().timeout(const Duration(seconds: 6));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw HttpException(
        'DLNA $action failed: HTTP ${res.statusCode}',
        uri: controlUrl,
      );
    }
    return body;
  } finally {
    client.close(force: true);
  }
}
