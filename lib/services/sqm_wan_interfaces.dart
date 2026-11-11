class SqmWanInterface {
  const SqmWanInterface({required this.name, this.device});

  final String name;
  final String? device;
  String get label => name.toUpperCase();
}

List<SqmWanInterface> parseSqmWanInterfaces({
  required Map network,
  required Map firewall,
  required Map interfaceDump,
}) {
  List<String> words(dynamic value) => value is List
      ? value.map((item) => item.toString()).toList()
      : (value?.toString() ?? '')
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
  String? device(dynamic value) {
    final values = words(value);
    if (values.length != 1 ||
        values.single.startsWith('@') ||
        values.single == 'lo') {
      return null;
    }
    return values.single;
  }

  final runtime = <String, Map>{
    for (final item in interfaceDump['interface'] as List? ?? const [])
      if (item is Map && item['interface'] is String)
        item['interface'] as String: item,
  };
  final wanNames = <String>{};
  final lanNames = <String>{'lan', 'loopback'};
  for (final zone in firewall.values.whereType<Map>()) {
    if (zone['.type'] != 'zone') continue;
    if (zone['name'] == 'wan') wanNames.addAll(words(zone['network']));
    if (zone['name'] == 'lan') lanNames.addAll(words(zone['network']));
  }
  for (final entry in runtime.entries) {
    final routes = entry.value['route'] as List? ?? const [];
    if (routes.whereType<Map>().any(
      (route) =>
          (route['target'] == '0.0.0.0' || route['target'] == '::') &&
          (route['mask'] == null || route['mask'].toString() == '0'),
    )) {
      wanNames.add(entry.key);
    }
  }
  for (final entry in network.entries) {
    if (entry.value is Map &&
        entry.value['.type'] == 'interface' &&
        RegExp(
          r'^(?:wan|wwan)(?:[0-9]+|_[A-Za-z0-9_]+)?$',
          caseSensitive: false,
        ).hasMatch(entry.key.toString())) {
      wanNames.add(entry.key.toString());
    }
  }
  wanNames.removeAll(lanNames);
  String? resolveDevice(String name) {
    final config = network[name] is Map ? network[name] as Map : const {};
    final l3 = device(runtime[name]?['l3_device']);
    if (l3 != null) return l3;
    // Never substitute a PPP/VPN parent Ethernet port for its tunnel device.
    if (const {
      'pppoe',
      'ppp',
      'pptp',
      'l2tp',
      'wireguard',
    }.contains(config['proto'])) {
      return null;
    }
    return device(runtime[name]?['device']) ??
        device(config['device']) ??
        device(config['ifname']);
  }

  return [
    for (final name in wanNames)
      if (network[name] is Map || runtime.containsKey(name))
        SqmWanInterface(name: name, device: resolveDevice(name)),
  ]..sort(
    (a, b) => a.name == 'wan'
        ? (b.name == 'wan' ? 0 : -1)
        : b.name == 'wan'
        ? 1
        : a.name.compareTo(b.name),
  );
}
