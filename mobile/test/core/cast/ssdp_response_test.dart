import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/core/cast/ssdp_response.dart';

void main() {
  test('parses standard SSDP response headers', () {
    const raw = 'HTTP/1.1 200 OK\r\n'
        'CACHE-CONTROL: max-age=1800\r\n'
        'LOCATION: http://192.168.1.100:49152/description.xml\r\n'
        'SERVER: Linux/3.10 UPnP/1.0 Foo/1.0\r\n'
        'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'
        'USN: uuid:abcd::urn:schemas-upnp-org:service:AVTransport:1\r\n'
        '\r\n';
    final headers = parseSsdpResponse(raw);
    expect(headers['LOCATION'],
        'http://192.168.1.100:49152/description.xml');
    expect(headers['ST'], 'urn:schemas-upnp-org:service:AVTransport:1');
    expect(headers['CACHE-CONTROL'], 'max-age=1800');
  });

  test('normalizes header names to upper case', () {
    const raw = 'HTTP/1.1 200 OK\r\n'
        'location: http://example.com/desc.xml\r\n'
        'Server: foo\r\n';
    final headers = parseSsdpResponse(raw);
    expect(headers['LOCATION'], 'http://example.com/desc.xml');
    expect(headers['SERVER'], 'foo');
  });

  test('skips malformed lines', () {
    const raw = 'HTTP/1.1 200 OK\r\n'
        'no-colon-line\r\n'
        ': empty-name\r\n'
        'LOCATION: http://x/\r\n';
    final headers = parseSsdpResponse(raw);
    expect(headers.containsKey(''), isFalse);
    expect(headers['LOCATION'], 'http://x/');
  });
}
