import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/vlan_discovery_service.dart';

Map<String, dynamic> bridgeConfig() => {
  'bridge': {
    '.type': 'device',
    'type': 'bridge',
    'name': 'br-lan',
    'ports': ['lan1', 'lan2'],
    'vlan_filtering': '1',
  },
  'home_vlan': {
    '.type': 'bridge-vlan',
    'device': 'br-lan',
    'vlan': '10',
    'ports': ['lan1:u*', 'lan2:t'],
  },
  'iot_vlan': {
    '.type': 'bridge-vlan',
    'device': 'br-lan',
    'vlan': '20',
    'ports': ['lan2:t'],
    'local': '0',
  },
  'lan': {'.type': 'interface', 'device': 'br-lan.10'},
};

void main() {
  test('two LAN ports and WAN use reported DSA names without CPU guessing', () {
    final topology = VlanDiscoveryService.parse(bridgeConfig(), {
      'lan1': {'devtype': 'dsa', 'parent': 'eth0', 'link': true},
      'lan2': {'devtype': 'dsa', 'parent': 'eth0', 'link': false},
      'wan': {'devtype': 'dsa', 'parent': 'eth0', 'link': true},
    }, {});
    expect(topology.layoutLabel, 'DSA switch ports detected');
    expect(topology.ports.map((p) => p.name), ['lan1', 'lan2', 'wan']);
    expect(topology.ports.first.bridges, ['br-lan']);
    expect(topology.ports.last.bridges, isEmpty);
    expect(topology.vlans.length, 2);
    expect(topology.vlans.first.interfaces, ['lan']);
    expect(topology.vlans.first.local, isTrue);
    expect(topology.vlans.last.local, isFalse);
    expect(topology.vlans.first.ports.first.primary, isTrue);
    expect(topology.vlans.first.ports.first.tagged, isFalse);
    expect(topology.vlans.first.ports.last.tagged, isTrue);
  });

  test('bridge configuration alone does not prove DSA hardware', () {
    final topology = VlanDiscoveryService.parse(bridgeConfig(), {}, {});
    expect(topology.layoutLabel, 'Switch topology not confirmed');
    expect(topology.ports.first.link, isNull);
  });

  test('legacy numbered ports distinguish board-reported CPU connection', () {
    final topology = VlanDiscoveryService.parse(
      {
        'vlan': {
          '.type': 'switch_vlan',
          'device': 'switch0',
          'vlan': '1',
          'vid': '20',
          'ports': '0 2 6t',
        },
      },
      {},
      {
        'switch': {
          'switch0': {
            'ports': [
              {'num': 0, 'role': 'lan', 'index': 1},
              {'num': 2, 'role': 'lan', 'index': 2},
              {'num': 6, 'device': 'eth0'},
            ],
          },
        },
      },
    );
    expect(topology.layoutLabel, 'Legacy switch configuration');
    expect(topology.vlans.single.id, '20');
    expect(topology.vlans.single.ports.last.tagged, isTrue);
    expect(topology.ports.map((p) => p.label), [
      'LAN 1',
      'LAN 2',
      'CPU (eth0)',
    ]);
    expect(topology.ports.last.kind, 'CPU connection');
  });

  test('legacy ports without board mapping keep numeric identity', () {
    final topology = VlanDiscoveryService.parse(
      {
        'vlan': {
          '.type': 'switch_vlan',
          'device': 'switch0',
          'vlan': '2',
          'ports': ['1', '5t'],
        },
      },
      {},
      {},
    );
    expect(topology.ports.map((p) => p.label), ['Port 1', 'Port 5']);
    expect(topology.ports.every((p) => p.kind == 'Switch port'), isTrue);
  });

  test(
    'tagged Ethernet device and implicit dotted interface are discovered',
    () {
      final topology = VlanDiscoveryService.parse(
        {
          'tagged': {
            '.type': 'device',
            'type': '8021q',
            'name': 'eth1.30',
            'ifname': 'eth1',
            'vid': '30',
          },
          'iot': {'.type': 'interface', 'device': 'eth1.30'},
          'guest': {'.type': 'interface', 'ifname': 'eth2.40'},
        },
        {},
        {},
      );
      expect(topology.vlans.length, 2);
      expect(topology.vlans.first.interfaces, ['iot']);
      expect(topology.vlans.last.interfaces, ['guest']);
      expect(topology.vlans.last.id, '40');
    },
  );

  test(
    'runtime bridge members are included without inventing VLAN entries',
    () {
      final topology = VlanDiscoveryService.parse({}, {
        'br-lan': {
          'bridge': true,
          'ports': ['lan1', 'lan2'],
        },
      }, {});
      expect(topology.bridges.single.name, 'br-lan');
      expect(topology.ports.length, 2);
      expect(topology.vlans, isEmpty);
    },
  );

  test('plain membership strings and unknown local settings are supported', () {
    final topology = VlanDiscoveryService.parse(
      {
        'br': {
          '.type': 'device',
          'type': 'bridge',
          'name': 'br0',
          'ports': 'eth0 eth1',
        },
        'v': {
          '.type': 'bridge-vlan',
          'device': 'br0',
          'vlan': 1,
          'ports': 'eth0 eth1:t*',
        },
      },
      {},
      {},
    );
    expect(topology.bridges.single.filtering, isNull);
    expect(topology.vlans.single.ports.last.primary, isTrue);
    expect(topology.vlans.single.ports.first.tagged, isFalse);
  });

  test(
    'optional metadata failures preserve configured VLAN discovery',
    () async {
      final calls = <String>[];
      final topology = await VlanDiscoveryService(
        call: (object, method, params) async {
          calls.add('$object.$method');
          if (object == 'uci') {
            return [
              0,
              {'values': bridgeConfig()},
            ];
          }
          throw StateError('Permission denied');
        },
      ).load();
      expect(topology.vlans.length, 2);
      expect(topology.warnings.length, 2);
      expect(calls, [
        'uci.get',
        'luci-rpc.getNetworkDevices',
        'luci-rpc.getBoardJSON',
      ]);
      expect(
        calls.any((c) => c.contains('set') || c.contains('apply')),
        isFalse,
      );
    },
  );

  test(
    'required network configuration failures are errors, not empty success',
    () async {
      await expectLater(
        VlanDiscoveryService(call: (_, _, _) async => [6]).load(),
        throwsStateError,
      );
      await expectLater(
        VlanDiscoveryService(call: (_, _, _) async => [0, {}]).load(),
        throwsStateError,
      );
    },
  );

  test('empty and malformed optional metadata do not invent ports', () {
    final topology = VlanDiscoveryService.parse(
      {},
      {
        'lo': {'type': 772},
      },
      {
        'switch': {
          'switch0': {
            'ports': [
              'bad',
              {'role': 'lan'},
            ],
          },
        },
      },
    );
    expect(topology.vlans, isEmpty);
    expect(topology.ports, isEmpty);
  });
}
