import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/utils/device_identity.dart';

void main() {
  const response = [
    0,
    {
      'values': {
        'cfg001': {
          '.type': 'host',
          'name': 'Bens-MacBook',
          'mac': ['7a:ff:de:3c:15:96', 'AA:BB:CC:DD:EE:FF'],
        },
        'cfg002': {'.type': 'domain', 'name': 'OpenWrt'},
      },
    },
  ];

  test('finds a configured DHCP host by normalized MAC', () {
    final identity = findDhcpHostIdentity(response, '7A-FF-DE-3C-15-96');

    expect(identity?.section, 'cfg001');
    expect(identity?.name, 'Bens-MacBook');
  });

  test('verifies the expected committed device name', () {
    expect(
      dhcpHostIdentityMatches(
        response,
        mac: '7A:FF:DE:3C:15:96',
        name: 'Bens-MacBook',
      ),
      isTrue,
    );
    expect(
      dhcpHostIdentityMatches(
        response,
        mac: '7A:FF:DE:3C:15:96',
        name: 'OpenWrt',
      ),
      isFalse,
    );
  });

  test('does not confuse non-host DHCP sections with device identities', () {
    expect(findDhcpHostIdentity(response, '00:11:22:33:44:55'), isNull);
    expect(findDhcpHostIdentity([6], '7A:FF:DE:3C:15:96'), isNull);
  });
}
