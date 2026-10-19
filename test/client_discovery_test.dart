import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/services/client_discovery_service.dart';

const laptop = 'AA:BB:CC:00:00:01';
const phone = 'AA:BB:CC:00:00:02';
const oldDevice = 'AA:BB:CC:00:00:03';
const routerMac = 'AA:BB:CC:00:00:04';

Client history(
  String mac, {
  String status = 'offline',
  String ip = '192.168.1.20',
}) => Client(
  macAddress: mac,
  ipAddress: ip,
  hostname: 'Old name',
  status: status,
  vendor: 'Example vendor',
  deviceIcon: 'laptop',
  totalDownloadBytes: 12345,
  totalUploadBytes: 678,
);

ClientDiscoverySnapshot snapshot() => ClientDiscoverySnapshot(
  leases: {
    'dhcp_leases': [
      {
        'macaddr': laptop.toLowerCase(),
        'ipaddr': '192.168.1.99',
        'hostname': 'Live laptop',
      },
    ],
  },
);

void main() {
  test('live discovery includes new clients despite nonempty history', () {
    final state = snapshot();
    state.parseNetworkOutput(
      'OPENWALLA_NEIGH_OK\n192.168.1.99 dev br-lan lladdr $laptop REACHABLE',
    );
    final clients = state.merge(
      history: [history(oldDevice)],
      wireless: {phone: Client.fromWirelessStation(phone)},
    );
    expect(
      clients.map((c) => c.macAddress),
      containsAll([laptop.toLowerCase(), phone, oldDevice]),
    );
    expect(
      clients.firstWhere((c) => c.macAddress == phone).isConnected,
      isTrue,
    );
    expect(
      clients.firstWhere((c) => c.macAddress == oldDevice).isOffline,
      isTrue,
    );
  });

  test(
    'live IP and name replace stale cache while metadata and totals survive',
    () {
      final state = snapshot();
      state.parseNetworkOutput(
        'OPENWALLA_NEIGH_OK\n192.168.1.99 dev br-lan lladdr $laptop REACHABLE',
      );
      final client = state
          .merge(history: [history(laptop)], wireless: {})
          .single;
      expect(client.ipAddress, '192.168.1.99');
      expect(client.hostname, 'Live laptop');
      expect(client.vendor, 'Example vendor');
      expect(client.deviceIcon, 'laptop');
      expect(client.totalDownloadBytes, 12345);
      expect(client.totalUploadBytes, 678);
      expect(client.isConnected, isTrue);
    },
  );

  test('static DHCP name wins, including multi-MAC host entries', () {
    final state = ClientDiscoverySnapshot(
      leases: snapshot().leases,
      dhcp: {
        'values': {
          'host': {
            '.type': 'host',
            'mac': [laptop.toLowerCase(), phone],
            'name': 'Configured',
            'ip': '192.168.1.99',
          },
        },
      },
    );
    expect(
      state
          .merge(history: [], wireless: {})
          .every((c) => c.hostname == 'Configured'),
      isTrue,
    );
  });

  test(
    'host hints fill missing names without treating hints as online proof',
    () {
      final state = ClientDiscoverySnapshot(
        leases: {
          'dhcp_leases': [
            {'macaddr': laptop, 'ipaddr': '192.168.1.99'},
          ],
        },
        hints: {
          laptop.toLowerCase(): {'name': 'Hint name'},
        },
      )..parseNetworkOutput('OPENWALLA_NEIGH_OK\n');
      final client = state.merge(history: [], wireless: {}).single;
      expect(client.hostname, 'Hint name');
      expect(client.isOffline, isTrue);
    },
  );

  test(
    'reachable, stale and failed neighbors produce distinct online evidence',
    () {
      final state = ClientDiscoverySnapshot()
        ..parseNetworkOutput('''OPENWALLA_NEIGH_OK
192.168.1.20 dev br-lan lladdr $laptop REACHABLE
192.168.1.21 dev br-lan lladdr $phone STALE
192.168.1.22 dev br-lan lladdr $oldDevice FAILED
''');
      final clients = state.merge(history: [], wireless: {});
      expect(clients.where((c) => c.isConnected).map((c) => c.macAddress), [
        laptop,
      ]);
      expect(clients.where((c) => c.isOffline).length, 2);
    },
  );

  test('bridge evidence activates a wired client and skips local entries', () {
    final state = ClientDiscoverySnapshot()
      ..parseNetworkOutput('''OPENWALLA_FDB_OK
$laptop dev lan1 master br-lan
$routerMac dev br-lan self permanent
1 $oldDevice yes 0.00
''');
    expect(state.activeWired, {laptop});
    expect(
      state.merge(history: [history(laptop)], wireless: {}).single.isConnected,
      isTrue,
    );
  });

  test(
    'cached wireless device is offline without association despite bridge evidence',
    () {
      final state = ClientDiscoverySnapshot()
        ..parseNetworkOutput(
          'OPENWALLA_FDB_OK\n$phone dev wlan0 master br-lan',
        );
      final client = state
          .merge(
            history: [
              history(phone).copyWith(connectionType: ConnectionType.wireless),
            ],
            wireless: {},
          )
          .single;
      expect(client.isOffline, isTrue);
      expect(client.connectionType, ConnectionType.wireless);
    },
  );

  test(
    'denied queries preserve cached state rather than inventing disconnections',
    () async {
      final service = ClientDiscoveryService(
        (object, method, params) async => [6],
      );
      final state = await service.fetch();
      final client = state
          .merge(
            history: [history(laptop, status: 'online')],
            wireless: {},
            wirelessAvailable: false,
          )
          .single;
      expect(client.isConnected, isTrue);
      expect(client.hostname, 'Old name');
    },
  );

  test('router, hidden and upstream MACs are excluded', () {
    final state = ClientDiscoverySnapshot(
      devices: {
        'br-lan': {'macaddr': routerMac},
      },
    );
    state.excludedMacs.add(phone);
    state.uplinkDevices.add('eth1');
    state.parseNetworkOutput(
      'OPENWALLA_NEIGH_OK\n192.0.2.1 dev eth1 lladdr $oldDevice REACHABLE',
    );
    final clients = state.merge(
      history: [
        history(routerMac),
        history(phone),
        history(oldDevice),
        history(laptop),
      ],
      wireless: {},
    );
    expect(clients.map((c) => c.macAddress), [laptop]);
  });

  test('reused IP never transfers another MAC vendor or traffic totals', () {
    final clients = snapshot().merge(
      history: [history(oldDevice, ip: '192.168.1.99')],
      wireless: {},
    );
    final client = clients.firstWhere(
      (c) => c.macAddress.toUpperCase() == laptop,
    );
    expect(client.vendor, isNull);
    expect(client.totalDownloadBytes, 0);
  });

  test('live nlbwmon totals use named columns and sum records per MAC', () {
    final state = snapshot();
    state.parseTraffic(
      jsonEncode({
        'columns': ['tx_bytes', 'mac', 'rx_bytes'],
        'data': [
          [10, laptop, 100],
          [20, laptop.toLowerCase(), 200],
        ],
      }),
    );
    final client = state.merge(history: [history(laptop)], wireless: {}).single;
    expect(client.totalDownloadBytes, 300);
    expect(client.totalUploadBytes, 30);
  });

  test('router hostname is not copied onto unnamed clients', () {
    final state = ClientDiscoverySnapshot(
      routerHostname: 'OpenWrt',
      leases: {
        'dhcp_leases': [
          {'macaddr': laptop, 'ipaddr': '192.168.1.99', 'hostname': 'OpenWrt'},
        ],
      },
    );
    expect(
      state.merge(history: [history(laptop)], wireless: {}).single.hostname,
      'Unknown',
    );
  });

  test(
    'wireless discovery without DHCP uses host hints for its IP and name',
    () {
      final state = ClientDiscoverySnapshot(
        leases: {'dhcp_leases': []},
        hints: {
          phone.toLowerCase(): {
            'name': 'My phone',
            'ipaddrs': ['192.168.1.55'],
          },
        },
      );
      final client = state
          .merge(
            history: [],
            wireless: {phone: Client.fromWirelessStation(phone)},
          )
          .single;
      expect(client.isConnected, isTrue);
      expect(client.ipAddress, '192.168.1.55');
      expect(client.hostname, 'My phone');
    },
  );

  test(
    'bridge-only discoveries appear even before the collector sees them',
    () {
      final state = ClientDiscoverySnapshot()
        ..parseNetworkOutput(
          'OPENWALLA_FDB_OK\n$laptop dev lan1 master br-lan',
        );
      final client = state.merge(history: [], wireless: {}).single;
      expect(client.isConnected, isTrue);
      expect(client.ipAddress, 'N/A');
      expect(client.hostname, 'Unknown');
    },
  );

  test(
    'LAN default gateway on an access point does not exclude LAN clients',
    () async {
      final service = ClientDiscoveryService((object, method, params) async {
        if (object == 'network.interface') {
          return [
            0,
            {
              'interface': [
                {
                  'interface': 'lan',
                  'l3_device': 'br-lan',
                  'ipv4-address': [
                    {'address': '192.168.1.2'},
                  ],
                  'route': [
                    {'target': '0.0.0.0'},
                  ],
                },
              ],
            },
          ];
        }
        if (object == 'file' &&
            method == 'exec' &&
            params['command'] == '/bin/sh') {
          return [
            0,
            {
              'code': 0,
              'stdout':
                  'OPENWALLA_NEIGH_OK\n192.168.1.99 dev br-lan lladdr $laptop REACHABLE',
            },
          ];
        }
        return [0, <String, dynamic>{}];
      });
      final state = await service.fetch();
      expect(state.uplinkDevices, isEmpty);
      expect(state.merge(history: [], wireless: {}).single.isConnected, isTrue);
    },
  );
}
