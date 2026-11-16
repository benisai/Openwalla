import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/ethernet_port.dart';

void main() {
  test(
    'two LAN ports and one WAN give three ports regardless of logical networks',
    () {
      final ports = EthernetPort.discover(
        board: {
          'network': {
            'lan': {
              'ports': ['lan1', 'lan2'],
            },
            'wan': {'device': 'wan'},
          },
        },
        builtin: [
          {'device': 'lan1', 'role': 'lan'},
          {'device': 'lan2', 'role': 'lan'},
          {'device': 'wan', 'role': 'wan'},
        ],
        devices: {
          'lan1': {
            'devtype': 'dsa',
            'parent': 'eth0',
            'link': {'carrier': true},
          },
          'lan2': {
            'devtype': 'dsa',
            'up': true,
            'link': {'carrier': false},
          },
          'wan': {
            'devtype': 'dsa',
            'link': {'carrier': true},
          },
          'eth0': {'devtype': 'ethernet', 'up': true},
          'br-lan': {'devtype': 'bridge'},
          'lan1.10': {'devtype': 'vlan'},
          'wg0': {'tunnel': true},
          'phy0-ap0': {'wireless': true},
        },
      )!;
      expect(ports.map((p) => p.name), ['lan1', 'lan2', 'wan']);
      expect(ports.map((p) => p.up), [true, false, true]);
      expect(ports.first.toJson()['label'], 'LAN (lan1)');
    },
  );

  test('legacy switch ports exclude CPU and VLAN device duplicates', () {
    final ports = EthernetPort.discover(
      board: {
        'switch': {
          'switch0': {
            'ports': [
              {'num': 0, 'device': 'eth0'},
              {'num': 1, 'role': 'lan', 'index': 1},
              {'num': 2, 'role': 'lan', 'index': 2},
              {'num': 3, 'role': 'wan'},
            ],
          },
        },
        'network': {
          'lan': {'device': 'eth0.1'},
          'wan': {'device': 'eth0.2'},
        },
      },
      builtin: [
        {'device': 'eth0.1'},
        {'device': 'eth0.2'},
        {'device': 'eth0'},
      ],
      devices: {
        'eth0': {
          'up': true,
          'link': {'carrier': true},
        },
      },
    )!;
    expect(ports.map((p) => p.name), ['switch0:1', 'switch0:2', 'switch0:3']);
    expect(ports.every((p) => p.up == null), isTrue);
  });

  test(
    'native inventory supports independent Ethernet NICs and deduplicates',
    () {
      final ports = EthernetPort.discover(
        builtin: [
          {'device': 'eth0', 'role': 'lan'},
          {'device': 'eth1', 'role': 'wan'},
          {'device': 'eth2', 'role': 'unknown'},
          {'device': 'eth1', 'role': 'wan'},
        ],
        devices: {
          'eth0': {'up': true},
          'eth1': {
            'link': {'carrier': 0},
          },
          'eth2': {
            'link': {'carrier': 1},
          },
        },
      )!;
      expect(ports.length, 3);
      expect(ports.map((p) => p.up), [null, false, true]);
    },
  );

  test(
    'no physical-port inference from bridges, virtual NICs or Ethernet type alone',
    () {
      expect(
        EthernetPort.discover(
          devices: {
            'eth0': {'devtype': 'ethernet'},
            'br-lan': {'bridge': true},
            'wlan0': {'wireless': true},
          },
        ),
        isNull,
      );
      final ports = EthernetPort.discover(
        devices: {
          'lan1': {
            'devtype': 'dsa',
            'link': {'carrier': false},
          },
          'lan2': {
            'devtype': 'dsa',
            'link': {'carrier': true},
          },
        },
      )!;
      expect(ports.length, 2);
    },
  );

  test('malformed/unsupported hardware data stays safe', () {
    expect(
      EthernetPort.discover(board: 42, devices: [], builtin: null),
      isNull,
    );
    expect(
      EthernetPort.discover(
        board: {
          'switch': {'bad': null},
          'network': {},
        },
        builtin: [null, 'invalid'],
      ),
      isEmpty,
    );
    expect(
      EthernetPort.discover(
        board: {
          'network': {
            'lan': {
              'ports': ['br-lan', 'eth0.1', 'wlan0'],
            },
          },
        },
        devices: {
          'wlan0': {'wireless': true},
        },
      ),
      isEmpty,
    );
  });
}
