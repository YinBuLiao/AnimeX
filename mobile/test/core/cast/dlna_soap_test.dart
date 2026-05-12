import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/core/cast/dlna_soap.dart';

void main() {
  group('envelope builders', () {
    test('SetAVTransportURI escapes & encodes URL', () {
      final body = buildSetAvTransportUri(
        uri: 'http://x/file?a=1&b=2',
        metadata: '',
      );
      expect(body, contains('<s:Envelope'));
      expect(body, contains('u:SetAVTransportURI'));
      expect(body, contains('xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"'));
      expect(body, contains('http://x/file?a=1&amp;b=2'));
      expect(body, contains('<InstanceID>0</InstanceID>'));
    });

    test('Play envelope carries speed=1', () {
      final body = buildPlay();
      expect(body, contains('<u:Play '));
      expect(body, contains('<Speed>1</Speed>'));
    });

    test('Seek encodes target as HH:MM:SS', () {
      final body = buildSeek(const Duration(minutes: 65, seconds: 7));
      expect(body, contains('<Target>01:05:07</Target>'));
      expect(body, contains('<Unit>REL_TIME</Unit>'));
    });

    test('soapAction wraps action in quotes', () {
      expect(soapAction('Play'),
          '"urn:schemas-upnp-org:service:AVTransport:1#Play"');
    });
  });

  group('parseHms / formatHms', () {
    test('parses HH:MM:SS', () {
      expect(parseHms('00:00:00'), Duration.zero);
      expect(parseHms('00:01:30'), const Duration(seconds: 90));
      expect(parseHms('01:02:03'),
          const Duration(hours: 1, minutes: 2, seconds: 3));
    });

    test('parses NOT_IMPLEMENTED as zero', () {
      expect(parseHms('NOT_IMPLEMENTED'), Duration.zero);
    });

    test('strips fractional seconds', () {
      expect(parseHms('00:00:05.123'), const Duration(seconds: 5));
    });

    test('formats round-trip via formatHms', () {
      const d = Duration(hours: 1, minutes: 5, seconds: 7);
      expect(formatHms(d), '01:05:07');
      expect(parseHms(formatHms(d)), d);
    });
  });

  group('parsePositionInfoResponse', () {
    test('extracts RelTime + TrackDuration', () {
      const xml = '''
<?xml version="1.0"?>
<s:Envelope><s:Body>
<u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <Track>1</Track>
  <TrackDuration>00:24:30</TrackDuration>
  <TrackMetaData></TrackMetaData>
  <TrackURI>http://example.com/file.mp4</TrackURI>
  <RelTime>00:05:12</RelTime>
  <AbsTime>00:05:12</AbsTime>
  <RelCount>1</RelCount>
  <AbsCount>1</AbsCount>
</u:GetPositionInfoResponse>
</s:Body></s:Envelope>''';
      final info = parsePositionInfoResponse(xml);
      expect(info.relTime, const Duration(minutes: 5, seconds: 12));
      expect(info.trackDuration, const Duration(minutes: 24, seconds: 30));
      expect(info.trackUri, 'http://example.com/file.mp4');
    });
  });
}
