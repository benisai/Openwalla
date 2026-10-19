import 'dart:convert';

import '../models/client.dart';
import '../utils/device_identity.dart';
import '../utils/router_identity.dart';

typedef DiscoveryCall =
    Future<dynamic> Function(
      String object,
      String method,
      Map<String, dynamic> params,
    );

class ClientDiscoveryService {
  ClientDiscoveryService(this.call);

  final DiscoveryCall call;

  Future<Map<String, dynamic>?> _read(
    String object,
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    try {
      return rpcDataMap(await call(object, method, params));
    } catch (_) {
      return null;
    }
  }

  Future<ClientDiscoverySnapshot> fetch() async {
    final results = await Future.wait([
      _read('luci-rpc', 'getDHCPLeases'),
      _read('luci-rpc', 'getHostHints'),
      _read('uci', 'get', {'config': 'dhcp'}),
      _read('network.device', 'status'),
      _read('file', 'exec', {
        'command': '/bin/sh',
        'params': ['-c', neighborCommand],
      }),
      _read('system', 'board'),
      _read('network.interface', 'dump'),
      _read('file', 'exec', {
        'command': '/usr/libexec/nlbwmon-action',
        'params': ['download', '-f', 'json', '-g', 'mac', '-o', 'rx'],
      }),
    ]);
    final snapshot = ClientDiscoverySnapshot(
      leases: results[0],
      hints: results[1],
      dhcp: results[2],
      devices: results[3],
      routerHostname: results[5]?['hostname']?.toString() ?? '',
    );
    snapshot.parseTraffic(results[7]?['stdout']?.toString() ?? '');
    for (final interface in results[6]?['interface'] as List? ?? const []) {
      if (interface is! Map) continue;
      for (final address in interface['ipv4-address'] as List? ?? const []) {
        if (address is Map) {
          snapshot.routerIps.add(address['address'].toString());
        }
      }
      final routes = interface['route'] as List? ?? const [];
      if (interface['interface'] != 'lan' &&
          routes.whereType<Map>().any(
            (route) => route['target'] == '0.0.0.0' || route['target'] == '::',
          )) {
        for (final key in const ['l3_device', 'device']) {
          final device = interface[key]?.toString();
          if (device != null) snapshot.uplinkDevices.add(device);
        }
      }
    }
    snapshot.parseNetworkOutput(results[4]?['stdout']?.toString() ?? '');
    if (!snapshot.wiredAvailable) {
      final arp = await _read('file', 'read', {'path': '/proc/net/arp'});
      if (arp?['data'] is String) {
        snapshot.parseArp(arp!['data'] as String);
      }
    }
    return snapshot;
  }

  // Capability markers distinguish an empty table from a denied/failed query.
  static const neighborCommand = '''
if neighbors="\$(ip neigh show 2>/dev/null)"; then
  echo OPENWALLA_NEIGH_OK
  printf '%s\\n' "\$neighbors"
  ip -6 neigh show 2>/dev/null
fi
if bridge fdb show >/dev/null 2>&1; then
  echo OPENWALLA_FDB_OK
  bridge fdb show 2>/dev/null
elif brctl showmacs br-lan >/dev/null 2>&1; then
  echo OPENWALLA_FDB_OK
  brctl showmacs br-lan 2>/dev/null
fi
''';
}

class ClientDiscoverySnapshot {
  ClientDiscoverySnapshot({
    this.leases,
    this.hints,
    this.dhcp,
    this.devices,
    this.routerHostname = '',
  });

  final Map<String, dynamic>? leases;
  final Map<String, dynamic>? hints;
  final Map<String, dynamic>? dhcp;
  final Map<String, dynamic>? devices;
  final String routerHostname;
  bool wiredAvailable = false;
  final Set<String> activeWired = {};
  final Map<String, String> neighborIps = {};
  final Set<String> routerMacs = {};
  final Set<String> excludedMacs = {};
  final Set<String> routerIps = {};
  final Set<String> uplinkDevices = {};
  final Map<String, ({int down, int up})> traffic = {};
  static final _macPattern = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

  static String mac(String value) => normalizeDeviceMac(value);
  static bool validMac(String value) =>
      _macPattern.hasMatch(value) &&
      value != '00:00:00:00:00:00' &&
      (int.parse(value.substring(0, 2), radix: 16) & 1) == 0;

  void parseTraffic(String output) {
    try {
      final decoded = jsonDecode(output);
      if (decoded is! Map ||
          decoded['columns'] is! List ||
          decoded['data'] is! List) {
        return;
      }
      final columns = decoded['columns'] as List;
      final macIndex = columns.indexOf('mac');
      final downIndex = columns.indexOf('rx_bytes');
      final upIndex = columns.indexOf('tx_bytes');
      if (macIndex < 0 || downIndex < 0 || upIndex < 0) return;
      for (final row in (decoded['data'] as List).whereType<List>()) {
        if ([
          macIndex,
          downIndex,
          upIndex,
        ].any((index) => index >= row.length)) {
          continue;
        }
        final key = mac(row[macIndex].toString());
        if (!validMac(key)) continue;
        final previous = traffic[key];
        traffic[key] = (
          down:
              (previous?.down ?? 0) +
              (int.tryParse(row[downIndex].toString()) ?? 0),
          up:
              (previous?.up ?? 0) +
              (int.tryParse(row[upIndex].toString()) ?? 0),
        );
      }
    } catch (_) {
      // A missing accounting package leaves the collector's cached totals intact.
    }
  }

  void parseNetworkOutput(String output) {
    var fdb = false;
    for (final line in output.split('\n')) {
      if (line == 'OPENWALLA_NEIGH_OK') {
        wiredAvailable = true;
        continue;
      }
      if (line == 'OPENWALLA_FDB_OK') {
        wiredAvailable = true;
        fdb = true;
        continue;
      }
      final parts = line.trim().split(RegExp(r'\s+'));
      if (fdb) {
        final candidate = parts.map(mac).where(validMac).firstOrNull;
        if (candidate == null) continue;
        if (parts.contains('self') ||
            parts.contains('permanent') ||
            parts.contains('yes')) {
          continue;
        }
        activeWired.add(candidate);
      } else {
        final index = parts.indexOf('lladdr');
        if (index < 0 || index + 1 >= parts.length) continue;
        final candidate = mac(parts[index + 1]);
        if (!validMac(candidate)) continue;
        final devIndex = parts.indexOf('dev');
        if (devIndex >= 0 && devIndex + 1 < parts.length) {
          if (uplinkDevices.contains(parts[devIndex + 1])) {
            excludedMacs.add(candidate);
            continue;
          }
        }
        final ip = parts.first;
        if (!ip.contains(':') || !neighborIps.containsKey(candidate)) {
          neighborIps[candidate] = ip;
        }
        if (parts.any(const {'REACHABLE', 'DELAY', 'PROBE'}.contains)) {
          activeWired.add(candidate);
        }
      }
    }
  }

  void parseArp(String output) {
    wiredAvailable = true;
    for (final line in output.split('\n').skip(1)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 6) continue;
      final candidate = mac(parts[3]);
      if (!validMac(candidate)) continue;
      if (uplinkDevices.contains(parts[5])) {
        excludedMacs.add(candidate);
        continue;
      }
      neighborIps[candidate] = parts[0];
      if (parts[2] == '0x2') activeWired.add(candidate);
    }
  }

  List<Client> merge({
    required Iterable<Client> history,
    required Map<String, Client> wireless,
    bool wirelessAvailable = true,
  }) {
    for (final value in devices?.values ?? const []) {
      if (value is Map && value['macaddr'] != null) {
        routerMacs.add(mac(value['macaddr'].toString()));
      }
    }
    final cached = {
      for (final client in history) mac(client.macAddress): client,
    };
    final live = <String, Client>{};
    for (final lease in leases?['dhcp_leases'] as List? ?? const []) {
      if (lease is! Map) continue;
      final client = Client.fromLease(Map<String, dynamic>.from(lease));
      live[mac(client.macAddress)] = client;
    }
    final normalizedHints = <String, Map>{};
    hints?.forEach((key, value) {
      if (value is Map) normalizedHints[mac(key)] = value;
    });
    final names = <String, String>{};
    final staticIps = <String, String>{};
    final values = dhcp?['values'];
    if (values is Map) {
      for (final section in values.values.whereType<Map>()) {
        if (section['.type'] != 'host') continue;
        final raw = section['mac'];
        final macs = raw is List
            ? raw
            : (raw?.toString() ?? '').split(RegExp(r'[\s,]+'));
        for (final item in macs) {
          final key = mac(item.toString());
          names[key] = section['name']?.toString().trim() ?? '';
          staticIps[key] = section['ip']?.toString().trim() ?? '';
        }
      }
    }
    final keys = {
      ...live.keys,
      ...wireless.keys,
      ...cached.keys,
      ...neighborIps.keys,
      ...activeWired,
      ...staticIps.keys,
    };
    final result = <Client>[];
    for (final key in keys) {
      if (!validMac(key) ||
          routerMacs.contains(key) ||
          excludedMacs.contains(key)) {
        continue;
      }
      final old = cached[key];
      final lease = live[key];
      final station = wireless[key];
      final hint = normalizedHints[key];
      final hintIps = hint?['ipaddrs'];
      final ip =
          [
                lease?.ipAddress,
                neighborIps[key],
                (hintIps is List && hintIps.isNotEmpty
                    ? hintIps.first.toString()
                    : null),
                staticIps[key],
                old?.ipAddress,
              ]
              .whereType<String>()
              .where(
                (value) =>
                    value.isNotEmpty &&
                    value != 'N/A' &&
                    value != 'ignore' &&
                    value != '*',
              )
              .firstOrNull ??
          'N/A';
      String usable(dynamic value) {
        final text = value?.toString().trim() ?? '';
        return text == '*' || text.toLowerCase() == 'unknown' ? '' : text;
      }

      final name =
          [
            usable(names[key]),
            if (usable(lease?.hostname).toLowerCase() !=
                routerHostname.toLowerCase())
              usable(lease?.hostname),
            if (usable(hint?['name']).toLowerCase() !=
                routerHostname.toLowerCase())
              usable(hint?['name']),
            if ((lease == null || (leases == null && dhcp == null)) &&
                usable(old?.hostname).toLowerCase() !=
                    routerHostname.toLowerCase())
              usable(old?.hostname),
          ].where((value) => value.isNotEmpty).firstOrNull ??
          'Unknown';
      final wasWireless = old?.connectionType == ConnectionType.wireless;
      final available = wasWireless
          ? wirelessAvailable
          : wiredAvailable && wirelessAvailable;
      final active =
          station != null || (!wasWireless && activeWired.contains(key));
      final status = active
          ? 'online'
          : available
          ? 'offline'
          : old?.status ?? 'unknown';
      if (routerIps.contains(ip)) continue;
      result.add(
        (old ??
                lease ??
                station ??
                Client(macAddress: key, ipAddress: ip, hostname: name))
            .copyWith(
              ipAddress: ip,
              hostname: name,
              status: status,
              connectionType: station != null || wasWireless
                  ? ConnectionType.wireless
                  : activeWired.contains(key)
                  ? ConnectionType.wired
                  : ConnectionType.unknown,
              ssid: station?.ssid,
              wirelessInterface: station?.wirelessInterface,
              wirelessBand: station?.wirelessBand,
              leaseTime: lease?.leaseTime,
              ipv6Addresses: lease?.ipv6Addresses,
              staticIpAddress: staticIps[key],
              totalDownloadBytes: traffic[key]?.down,
              totalUploadBytes: traffic[key]?.up,
            ),
      );
    }
    return result;
  }
}
