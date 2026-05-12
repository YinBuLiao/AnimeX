import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animex_mobile/core/cast/device_description.dart';
import 'package:animex_mobile/core/cast/dlna_device.dart';
import 'package:animex_mobile/core/cast/ssdp_response.dart';

/// SSDP multicast address + port.
const _ssdpAddress = '239.255.255.250';
const _ssdpPort = 1900;

const _msearchBody = 'M-SEARCH * HTTP/1.1\r\n'
    'HOST: 239.255.255.250:1900\r\n'
    'MAN: "ssdp:discover"\r\n'
    'MX: 3\r\n'
    'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'
    '\r\n';

typedef DescriptionFetcher = Future<String> Function(Uri location);

/// Discovers DLNA AVTransport renderers on the local network by broadcasting
/// SSDP M-SEARCH and resolving each LOCATION header to a DlnaDevice.
class DlnaDiscovery {
  final Duration timeout;
  final DescriptionFetcher fetcher;

  DlnaDiscovery({
    this.timeout = const Duration(seconds: 4),
    DescriptionFetcher? fetcher,
  }) : fetcher = fetcher ?? _defaultFetcher;

  Stream<DlnaDevice> search() async* {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final seenLocations = <String>{};
    final seenDevices = <String>{};
    final controller = StreamController<DlnaDevice>();

    final sub = socket.listen((event) async {
      if (event != RawSocketEvent.read) return;
      final dgram = socket.receive();
      if (dgram == null) return;
      String text;
      try {
        text = utf8.decode(dgram.data, allowMalformed: true);
      } catch (_) {
        return;
      }
      final headers = parseSsdpResponse(text);
      final loc = headers['LOCATION'];
      if (loc == null || loc.isEmpty) return;
      if (!seenLocations.add(loc)) return;
      Uri locUri;
      try {
        locUri = Uri.parse(loc);
      } catch (_) {
        return;
      }
      try {
        final xml = await fetcher(locUri);
        final device = parseDeviceDescription(xml, locUri);
        if (device == null) return;
        if (!seenDevices.add(device.id)) return;
        controller.add(device);
      } catch (_) {
        // Ignore unreachable / malformed devices.
      }
    });

    socket.send(
      utf8.encode(_msearchBody),
      InternetAddress(_ssdpAddress),
      _ssdpPort,
    );

    final timer = Timer(timeout, () async {
      await sub.cancel();
      socket.close();
      await controller.close();
    });

    try {
      yield* controller.stream;
    } finally {
      timer.cancel();
      await sub.cancel();
      socket.close();
      if (!controller.isClosed) await controller.close();
    }
  }
}

Future<String> _defaultFetcher(Uri location) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 3);
  try {
    final req = await client.getUrl(location);
    final res = await req.close().timeout(const Duration(seconds: 4));
    return await res.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
  }
}
