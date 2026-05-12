import 'package:animex_mobile/core/cast/dlna_device.dart';

const String avTransportServiceType =
    'urn:schemas-upnp-org:service:AVTransport:1';

/// Parses a UPnP device description XML and returns a DlnaDevice if the
/// description advertises an AVTransport service. Returns null if the device
/// is not media-capable or if required fields are missing.
DlnaDevice? parseDeviceDescription(String xml, Uri location) {
  String? friendly = _firstTag(xml, 'friendlyName');
  String? udn = _firstTag(xml, 'UDN');
  String manufacturer = _firstTag(xml, 'manufacturer') ?? '';
  String modelName = _firstTag(xml, 'modelName') ?? '';
  if (friendly == null || udn == null) return null;

  final services = _extractServices(xml);
  String? controlPath;
  for (final svc in services) {
    if ((svc['serviceType'] ?? '').contains('AVTransport:1')) {
      controlPath = svc['controlURL'];
      break;
    }
  }
  if (controlPath == null || controlPath.isEmpty) return null;

  return DlnaDevice(
    id: udn,
    friendlyName: friendly,
    manufacturer: manufacturer,
    modelName: modelName,
    location: location,
    controlUrl: _resolveUrl(location, controlPath),
  );
}

String? _firstTag(String xml, String name) {
  final re = RegExp('<$name[^>]*>([^<]*)</$name>', caseSensitive: false);
  final m = re.firstMatch(xml);
  if (m == null) return null;
  return _decodeXml(m.group(1)!.trim());
}

List<Map<String, String>> _extractServices(String xml) {
  final results = <Map<String, String>>[];
  final re = RegExp(r'<service\b[^>]*>([\s\S]*?)</service>',
      caseSensitive: false);
  for (final m in re.allMatches(xml)) {
    final body = m.group(1)!;
    final svc = <String, String>{};
    for (final field in ['serviceType', 'serviceId', 'controlURL',
        'eventSubURL', 'SCPDURL']) {
      final v = _firstTag(body, field);
      if (v != null) svc[field] = v;
    }
    results.add(svc);
  }
  return results;
}

Uri _resolveUrl(Uri location, String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Uri.parse(path);
  }
  if (path.startsWith('/')) {
    return Uri(
      scheme: location.scheme,
      host: location.host,
      port: location.hasPort ? location.port : null,
      path: path,
    );
  }
  return location.resolve(path);
}

String _decodeXml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");
