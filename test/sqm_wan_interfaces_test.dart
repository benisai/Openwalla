import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/sqm_wan_interfaces.dart';

void main() {
  test(
    'WAN, WWAN and custom WAN members use logical names, not vnStat output',
    () {
      final interfaces = parseSqmWanInterfaces(
        network: {
          for (final name in ['wan', 'wwan', 'cellular', 'lan', 'guest'])
            name: {'.type': 'interface'},
        },
        firewall: {
          'zone': {
            '.type': 'zone',
            'name': 'wan',
            'network': ['wan', 'wwan', 'cellular'],
          },
        },
        interfaceDump: {
          'interface': [
            {'interface': 'wan', 'l3_device': 'eth1'},
            {'interface': 'wwan', 'l3_device': 'phy0-sta0'},
            {'interface': 'cellular', 'l3_device': 'wwan0'},
            {'interface': 'lan', 'l3_device': 'br-lan'},
          ],
        },
      );
      expect(interfaces.map((item) => item.label), ['WAN', 'CELLULAR', 'WWAN']);
      expect(interfaces.map((item) => item.device), [
        'eth1',
        'wwan0',
        'phy0-sta0',
      ]);
    },
  );

  test(
    'default-route interfaces are included while LAN and non-default routes are excluded',
    () {
      final interfaces = parseSqmWanInterfaces(
        network: {},
        firewall: {},
        interfaceDump: {
          'interface': [
            {
              'interface': 'fiber',
              'l3_device': 'eth2.20',
              'route': [
                {'target': '0.0.0.0', 'mask': 0},
              ],
            },
            {
              'interface': 'lte6',
              'l3_device': 'wwan0',
              'route': [
                {'target': '::', 'mask': 0},
              ],
            },
            {
              'interface': 'lan',
              'l3_device': 'br-lan',
              'route': [
                {'target': '0.0.0.0', 'mask': 0},
              ],
            },
            {
              'interface': 'guest',
              'device': 'br-guest',
              'route': [
                {'target': '0.0.0.0', 'mask': 8},
              ],
            },
          ],
        },
      );
      expect(interfaces.map((item) => item.name), ['fiber', 'lte6']);
    },
  );

  test(
    'PPPoE uses runtime L3 device, never the underlying Ethernet parent',
    () {
      final network = {
        'wan': {'.type': 'interface', 'proto': 'pppoe', 'device': 'eth1'},
      };
      expect(
        parseSqmWanInterfaces(
          network: network,
          firewall: {},
          interfaceDump: {
            'interface': [
              {'interface': 'wan', 'l3_device': 'pppoe-wan', 'device': 'eth1'},
            ],
          },
        ).single.device,
        'pppoe-wan',
      );
      expect(
        parseSqmWanInterfaces(
          network: network,
          firewall: {},
          interfaceDump: {
            'interface': [
              {'interface': 'wan', 'device': 'eth1'},
            ],
          },
        ).single.device,
        isNull,
      );
    },
  );

  test(
    'disconnected WAN remains named, unresolved WWAN is unavailable, no fake fallback',
    () {
      final interfaces = parseSqmWanInterfaces(
        network: {
          'wan': {'.type': 'interface', 'ifname': 'eth0.2'},
          'wwan': {'.type': 'interface', 'proto': 'dhcp'},
          'wan6': {'.type': 'interface', 'device': '@wan'},
        },
        firewall: {},
        interfaceDump: {},
      );
      expect(interfaces.first.device, 'eth0.2');
      expect(
        interfaces
            .where((item) => item.name != 'wan')
            .every((item) => item.device == null),
        isTrue,
      );
      expect(
        parseSqmWanInterfaces(network: {}, firewall: {}, interfaceDump: {}),
        isEmpty,
      );
    },
  );
}
