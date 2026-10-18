import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/utils/router_identity.dart';

void main() {
  test('prefers a board serial as a router fingerprint', () {
    expect(
      routerSerialFingerprint([
        0,
        {'serial_number': 'ABC-123'},
      ]),
      'serial:abc-123',
    );
  });

  test('normalizes a LAN MAC as a router fingerprint', () {
    expect(
      routerMacFingerprint([
        0,
        {'macaddr': 'AA:BB:CC:DD:EE:FF'},
      ]),
      'lan-mac:aabbccddeeff',
    );
  });

  test('reads the effective LAN device from interface status', () {
    expect(
      routerInterfaceDeviceName([
        0,
        {'l3_device': 'br-lan'},
      ]),
      'br-lan',
    );
  });
}
