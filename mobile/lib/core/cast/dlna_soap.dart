const String _serviceType = 'urn:schemas-upnp-org:service:AVTransport:1';

String soapAction(String action) => '"$_serviceType#$action"';

String buildSetAvTransportUri({required String uri, String metadata = ''}) {
  return _envelope('SetAVTransportURI', '''
      <InstanceID>0</InstanceID>
      <CurrentURI>${_escape(uri)}</CurrentURI>
      <CurrentURIMetaData>${_escape(metadata)}</CurrentURIMetaData>''');
}

String buildPlay({int speed = 1}) {
  return _envelope('Play', '''
      <InstanceID>0</InstanceID>
      <Speed>$speed</Speed>''');
}

String buildPause() {
  return _envelope('Pause', '<InstanceID>0</InstanceID>');
}

String buildStop() {
  return _envelope('Stop', '<InstanceID>0</InstanceID>');
}

String buildSeek(Duration position) {
  return _envelope('Seek', '''
      <InstanceID>0</InstanceID>
      <Unit>REL_TIME</Unit>
      <Target>${formatHms(position)}</Target>''');
}

String buildGetPositionInfo() {
  return _envelope('GetPositionInfo', '<InstanceID>0</InstanceID>');
}

String _envelope(String action, String body) {
  return '<?xml version="1.0" encoding="utf-8"?>\n'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
      '<s:Body>'
      '<u:$action xmlns:u="$_serviceType">'
      '$body'
      '</u:$action>'
      '</s:Body>'
      '</s:Envelope>';
}

class PositionInfo {
  final Duration relTime;
  final Duration trackDuration;
  final String trackUri;

  const PositionInfo({
    required this.relTime,
    required this.trackDuration,
    required this.trackUri,
  });
}

PositionInfo parsePositionInfoResponse(String xml) {
  final rel = _firstTag(xml, 'RelTime');
  final dur = _firstTag(xml, 'TrackDuration');
  final uri = _firstTag(xml, 'TrackURI') ?? '';
  return PositionInfo(
    relTime: parseHms(rel ?? ''),
    trackDuration: parseHms(dur ?? ''),
    trackUri: uri,
  );
}

Duration parseHms(String s) {
  if (s.isEmpty || s == 'NOT_IMPLEMENTED') return Duration.zero;
  final parts = s.split(':');
  if (parts.length != 3) return Duration.zero;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  final sec = int.tryParse(parts[2].split('.').first) ?? 0;
  return Duration(hours: h, minutes: m, seconds: sec);
}

String formatHms(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String? _firstTag(String xml, String name) {
  final re = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>', caseSensitive: false);
  final m = re.firstMatch(xml);
  if (m == null) return null;
  return _unescape(m.group(1)!.trim());
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");
