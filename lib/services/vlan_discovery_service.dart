enum VlanKind { bridge, switchVlan, taggedDevice }

class VlanMembership {
  final String port;
  final bool tagged;
  final bool primary;

  const VlanMembership(this.port, {this.tagged = false, this.primary = false});

  static VlanMembership parse(String value, {bool legacy = false}) {
    if (legacy) {
      final match = RegExp(r'^(\d+)([tu*]*)$').firstMatch(value);
      return VlanMembership(
        match?.group(1) ?? value,
        tagged: match?.group(2)?.contains('t') == true,
        primary: match?.group(2)?.contains('*') == true,
      );
    }
    final parts = value.split(':');
    final flags = parts.length > 1 ? parts[1] : '';
    return VlanMembership(
      parts.first,
      tagged: flags.contains('t'),
      primary: flags.contains('*'),
    );
  }
}

class VlanEntry {
  final String section;
  final VlanKind kind;
  final String device;
  final String id;
  final List<VlanMembership> ports;
  final List<String> interfaces;
  final bool? local;

  const VlanEntry({
    required this.section,
    required this.kind,
    required this.device,
    required this.id,
    this.ports = const [],
    this.interfaces = const [],
    this.local,
  });

  String get kindLabel => switch (kind) {
    VlanKind.bridge => 'Bridge VLAN',
    VlanKind.switchVlan => 'Legacy switch VLAN',
    VlanKind.taggedDevice => 'Tagged Ethernet device',
  };
}

class VlanPortInfo {
  final String name;
  final String label;
  final String kind;
  final String? switchName;
  final bool? link;
  final List<String> bridges;
  const VlanPortInfo({
    required this.name,
    required this.label,
    required this.kind,
    this.switchName,
    this.link,
    this.bridges = const [],
  });
}

class VlanBridgeInfo {
  final String name;
  final List<String> ports;
  final bool? filtering;
  const VlanBridgeInfo(this.name, this.ports, this.filtering);
}

class VlanTopology {
  final List<VlanEntry> vlans;
  final List<VlanBridgeInfo> bridges;
  final List<VlanPortInfo> ports;
  final List<String> warnings;
  const VlanTopology({
    required this.vlans,
    required this.bridges,
    required this.ports,
    this.warnings = const [],
  });

  String get layoutLabel {
    final dsa = ports.any((p) => p.kind == 'DSA port');
    final legacy =
        vlans.any((v) => v.kind == VlanKind.switchVlan) ||
        ports.any((p) => p.switchName != null);
    if (dsa && legacy) return 'Mixed switch topology';
    if (dsa) return 'DSA switch ports detected';
    if (legacy) return 'Legacy switch configuration';
    return 'Switch topology not confirmed';
  }
}

class VlanDiscoveryService {
  final Future<dynamic> Function(String, String, Map<String, dynamic>) call;
  VlanDiscoveryService({required this.call});

  static Map _map(dynamic data) => data is Map ? data : const {};
  static List<String> _list(dynamic data) => data is List
      ? data.map((v) => v.toString()).toList()
      : data is String
      ? data.split(RegExp(r'\s+')).where((v) => v.isNotEmpty).toList()
      : [];
  static bool? _flag(dynamic data) => switch (data) {
    true || 1 || '1' => true,
    false || 0 || '0' => false,
    _ => null,
  };

  Map _unwrap(dynamic response) {
    if (response is! List ||
        response.isEmpty ||
        response.first != 0 ||
        response.length < 2 ||
        response[1] is! Map) {
      throw StateError('The router did not return VLAN discovery data.');
    }
    return response[1] as Map;
  }

  Future<VlanTopology> load() async {
    final config = _unwrap(await call('uci', 'get', {'config': 'network'}));
    if (config['values'] is! Map) {
      throw StateError('The router did not return its network configuration.');
    }
    final warnings = <String>[];
    Future<Map> optional(String method, String warning) async {
      try {
        return _unwrap(await call('luci-rpc', method, {}));
      } catch (_) {
        warnings.add(warning);
        return {};
      }
    }

    final devices = await optional(
      'getNetworkDevices',
      'Live port state unavailable',
    );
    final board = await optional(
      'getBoardJSON',
      'Board port mapping unavailable',
    );
    return parse(_map(config['values']), devices, board, warnings: warnings);
  }

  static VlanTopology parse(
    Map config,
    Map devices,
    Map board, {
    List<String> warnings = const [],
  }) {
    final bridges = <VlanBridgeInfo>[];
    final vlans = <VlanEntry>[];
    final ports = <VlanPortInfo>[];
    final knownPorts = <String>{};
    final bridgeNames = <String>{};
    final interfaces = config.entries.where(
      (e) => _map(e.value)['.type'] == 'interface',
    );
    List<String> networks(String device) => interfaces
        .where((e) {
          final value = _map(e.value);
          return _list(value['device'] ?? value['ifname']).contains(device);
        })
        .map((e) => e.key.toString())
        .toList();

    for (final entry in config.entries) {
      final value = _map(entry.value);
      final type = value['.type'];
      if (type == 'device' && value['type'] == 'bridge') {
        final name = value['name']?.toString() ?? entry.key.toString();
        final members = _list(value['ports']);
        bridges.add(
          VlanBridgeInfo(name, members, _flag(value['vlan_filtering'])),
        );
        bridgeNames.add(name);
        knownPorts.addAll(members);
      }
      if (type == 'bridge-vlan' || type == 'switch_vlan') {
        final legacy = type == 'switch_vlan';
        final device = value['device']?.toString() ?? 'Unknown';
        final id =
            (legacy ? value['vid'] ?? value['vlan'] : value['vlan'])
                ?.toString() ??
            '?';
        final members = _list(
          value['ports'],
        ).map((p) => VlanMembership.parse(p, legacy: legacy)).toList();
        if (!legacy) knownPorts.addAll(members.map((p) => p.port));
        vlans.add(
          VlanEntry(
            section: entry.key.toString(),
            kind: legacy ? VlanKind.switchVlan : VlanKind.bridge,
            device: device,
            id: id,
            ports: members,
            interfaces: legacy ? const [] : networks('$device.$id'),
            local: legacy ? null : _flag(value['local']) ?? true,
          ),
        );
      }
      if (type == 'device' &&
          const ['8021q', '8021ad'].contains(value['type'])) {
        final name = value['name']?.toString() ?? entry.key.toString();
        vlans.add(
          VlanEntry(
            section: entry.key.toString(),
            kind: VlanKind.taggedDevice,
            device: name,
            id: value['vid']?.toString() ?? '?',
            ports: [
              VlanMembership(
                value['ifname']?.toString() ?? 'Unknown',
                tagged: true,
              ),
            ],
            interfaces: networks(name),
          ),
        );
      }
    }
    // netifd also accepts dotted VLAN devices without a separate device section.
    for (final entry in interfaces) {
      final value = _map(entry.value);
      for (final device in _list(value['device'] ?? value['ifname'])) {
        final match = RegExp(r'^(.+)\.(\d+)$').firstMatch(device);
        if (match == null) continue;
        final parent = match.group(1)!;
        final id = match.group(2)!;
        if (vlans.any(
          (v) =>
              v.device == device ||
              (v.kind == VlanKind.bridge && v.device == parent && v.id == id),
        )) {
          continue;
        }
        vlans.add(
          VlanEntry(
            section: entry.key.toString(),
            kind: VlanKind.taggedDevice,
            device: device,
            id: id,
            ports: [VlanMembership(parent, tagged: true)],
            interfaces: networks(device),
          ),
        );
      }
    }
    // Include runtime bridge members, but never infer a physical port count.
    for (final entry in devices.entries) {
      final value = _map(entry.value);
      if (value['bridge'] == true) {
        knownPorts.addAll(_list(value['ports']));
        if (bridgeNames.add(entry.key.toString())) {
          bridges.add(
            VlanBridgeInfo(entry.key.toString(), _list(value['ports']), null),
          );
        }
      } else if (value['devtype'] == 'dsa' ||
          (value['type'] == 1 &&
              value['wireless'] != true &&
              value['parent'] == null &&
              value['tunnel'] != true)) {
        knownPorts.add(entry.key.toString());
      }
    }
    for (final name in knownPorts) {
      final value = _map(devices[name]);
      ports.add(
        VlanPortInfo(
          name: name,
          label: name,
          kind: value['devtype'] == 'dsa' ? 'DSA port' : 'Network device',
          link: _flag(value['link']),
          bridges: bridges
              .where((b) => b.ports.contains(name))
              .map((b) => b.name)
              .toList(),
        ),
      );
    }
    for (final entry in _map(board['switch']).entries) {
      final layout = _map(entry.value)['ports'];
      if (layout is! List) continue;
      for (final value in layout.whereType<Map>()) {
        if (value['num'] == null) continue;
        final number = value['num'].toString();
        final cpu = value['device'];
        final role = value['role']?.toString().toUpperCase();
        final index = value['index'];
        ports.add(
          VlanPortInfo(
            name: number,
            switchName: entry.key.toString(),
            label: cpu != null
                ? 'CPU ($cpu)'
                : role == null
                ? 'Port $number'
                : '$role${index == null ? '' : ' $index'}',
            kind: cpu != null ? 'CPU connection' : 'Switch port',
          ),
        );
      }
    }
    // Always expose numeric legacy memberships even without board metadata.
    for (final vlan in vlans.where((v) => v.kind == VlanKind.switchVlan)) {
      for (final member in vlan.ports) {
        if (!ports.any(
          (p) => p.switchName == vlan.device && p.name == member.port,
        )) {
          ports.add(
            VlanPortInfo(
              name: member.port,
              label: 'Port ${member.port}',
              kind: 'Switch port',
              switchName: vlan.device,
            ),
          );
        }
      }
    }
    vlans.sort((a, b) {
      final parent = a.device.compareTo(b.device);
      return parent != 0
          ? parent
          : (int.tryParse(a.id) ?? -1).compareTo(int.tryParse(b.id) ?? -1);
    });
    ports.sort(
      (a, b) => '${a.switchName ?? ''}/${a.name}'.compareTo(
        '${b.switchName ?? ''}/${b.name}',
      ),
    );
    return VlanTopology(
      vlans: vlans,
      bridges: bridges,
      ports: ports,
      warnings: warnings,
    );
  }
}
