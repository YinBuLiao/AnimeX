import 'package:flutter_test/flutter_test.dart';

import 'package:animex_mobile/core/cast/device_description.dart';

void main() {
  test('parses a typical UPnP MediaRenderer description', () {
    const xml = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>客厅电视</friendlyName>
    <manufacturer>Xiaomi</manufacturer>
    <modelName>MiBox 4S</modelName>
    <UDN>uuid:11111111-2222-3333-4444-555555555555</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <controlURL>/cm/control</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
        <controlURL>/avtransport/control</controlURL>
        <eventSubURL>/avtransport/event</eventSubURL>
      </service>
    </serviceList>
  </device>
</root>''';
    final loc = Uri.parse('http://192.168.1.100:49152/description.xml');
    final d = parseDeviceDescription(xml, loc);
    expect(d, isNotNull);
    expect(d!.friendlyName, '客厅电视');
    expect(d.manufacturer, 'Xiaomi');
    expect(d.modelName, 'MiBox 4S');
    expect(d.id, 'uuid:11111111-2222-3333-4444-555555555555');
    expect(d.controlUrl.toString(),
        'http://192.168.1.100:49152/avtransport/control');
  });

  test('returns null when no AVTransport service is present', () {
    const xml = '''
<root><device>
  <friendlyName>Light Bulb</friendlyName>
  <UDN>uuid:lamp</UDN>
  <serviceList><service>
    <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
    <controlURL>/cm/control</controlURL>
  </service></serviceList>
</device></root>''';
    final d = parseDeviceDescription(
        xml, Uri.parse('http://10.0.0.5:80/desc.xml'));
    expect(d, isNull);
  });

  test('resolves absolute control URL when path is already absolute', () {
    const xml = '''
<root><device>
  <friendlyName>TV</friendlyName>
  <UDN>uuid:tv</UDN>
  <serviceList><service>
    <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
    <controlURL>http://10.0.0.2:8001/avt</controlURL>
  </service></serviceList>
</device></root>''';
    final d = parseDeviceDescription(
        xml, Uri.parse('http://10.0.0.5:80/desc.xml'));
    expect(d!.controlUrl.toString(), 'http://10.0.0.2:8001/avt');
  });

  test('resolves relative control URL against the description location', () {
    const xml = '''
<root><device>
  <friendlyName>TV</friendlyName>
  <UDN>uuid:tv</UDN>
  <serviceList><service>
    <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
    <controlURL>control/avt</controlURL>
  </service></serviceList>
</device></root>''';
    final d = parseDeviceDescription(
        xml, Uri.parse('http://10.0.0.5:8080/upnp/desc.xml'));
    expect(d!.controlUrl.toString(),
        'http://10.0.0.5:8080/upnp/control/avt');
  });
}
