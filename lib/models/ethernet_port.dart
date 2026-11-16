class EthernetPort {
  const EthernetPort(this.name, this.label, this.up);

  final String name;
  final String label;
  final bool? up;

  Map<String, dynamic> toJson() => {'name': name, 'label': label, 'up': up};

  static bool? _flag(Object? value) => switch (value) {
    true || 1 || '1' => true,
    false || 0 || '0' => false,
    _ => null,
  };

  /// Hardware inventory is authoritative; logical interfaces never imply jacks.
  static List<EthernetPort>? discover({
    Object? devices,
    Object? board,
    Object? builtin,
  }) {
    final live = devices is Map ? devices : const {};
    final hardware = board is Map ? board : const {};
    final ports = <String, EthernetPort>{};
    final cpuDevices = <String>{};
    var known = builtin is List && builtin.isNotEmpty;

    void add(String name, String label) {
      if (name.isEmpty ||
          name == 'lo' ||
          name.contains('.') ||
          cpuDevices.contains(name)) {
        return;
      }
      final device = live[name] is Map ? live[name] as Map : const {};
      if (_flag(device['wireless']) == true ||
          _flag(device['bridge']) == true ||
          _flag(device['tunnel']) == true ||
          const [
            'bridge',
            'vlan',
            'bond',
            'macvlan',
            'macvtap',
            'veth',
            'vxlan',
            'wireguard',
            'wlan',
            'tun',
          ].contains(device['devtype']) ||
          name.startsWith('br-')) {
        return;
      }
      final link = device['link'];
      // Administrative `up` is not the state of a plugged-in Ethernet cable.
      final carrier = link is Map ? _flag(link['carrier']) : _flag(link);
      ports.putIfAbsent(
        name,
        () => EthernetPort(name, label, carrier ?? _flag(device['carrier'])),
      );
    }

    final switches = hardware['switch'];
    if (switches is Map) {
      for (final entry in switches.entries) {
        final layout = entry.value is Map ? entry.value['ports'] : null;
        if (layout is! List) continue;
        for (final port in layout.whereType<Map>()) {
          if (port['device'] != null) cpuDevices.add('${port['device']}');
        }
        for (final port in layout.whereType<Map>()) {
          if (port['device'] != null || port['num'] == null) continue;
          final role = '${port['role'] ?? ''}'.toLowerCase();
          if (role != 'lan' && role != 'wan') continue;
          known = true;
          final name = '${entry.key}:${port['num']}';
          final label = '${role.toUpperCase()} ${port['index'] ?? port['num']}';
          // Legacy switch PHYs have no individual netdev; don't borrow the CPU link.
          ports[name] = EthernetPort(name, label, null);
        }
      }
    }

    if (builtin is List) {
      for (final port in builtin.whereType<Map>()) {
        final name = '${port['device'] ?? ''}';
        final role = '${port['role'] ?? ''}'.toUpperCase();
        add(name, role.isEmpty || role == 'UNKNOWN' ? name : '$role ($name)');
      }
    }
    final network = hardware['network'];
    if (network is Map) {
      known = true;
      for (final role in ['lan', 'wan']) {
        final section = network[role];
        if (section is! Map) continue;
        final members = section['ports'];
        if (members is List) {
          for (final name in members.whereType<String>()) {
            add(name, '${role.toUpperCase()} ($name)');
          }
        } else if (section['device'] is String) {
          final name = section['device'] as String;
          add(name, '${role.toUpperCase()} ($name)');
        }
      }
    }
    // Confirmed DSA ports are safe even when older firmware lacks board inventory.
    for (final entry in live.entries) {
      if (entry.value is Map && entry.value['devtype'] == 'dsa') {
        known = true;
        add('${entry.key}', '${entry.key}');
      }
    }
    if (!known && ports.isEmpty) return null;
    return ports.values.toList();
  }
}
