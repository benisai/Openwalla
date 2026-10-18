class DeviceFirewallState {
  const DeviceFirewallState({
    this.available = true,
    this.blockedMacs = const <String>{},
    this.quarantinedMacs = const <String>{},
    this.pausedMacs = const <String>{},
  });

  final bool available;
  final Set<String> blockedMacs;
  final Set<String> quarantinedMacs;
  final Set<String> pausedMacs;

  DeviceFirewallState merge(DeviceFirewallState other) => DeviceFirewallState(
    available: available && other.available,
    blockedMacs: {...blockedMacs, ...other.blockedMacs},
    quarantinedMacs: {...quarantinedMacs, ...other.quarantinedMacs},
    pausedMacs: {...pausedMacs, ...other.pausedMacs},
  );
}

class DeviceFirewallDisposition {
  const DeviceFirewallDisposition({
    required this.blocked,
    required this.quarantined,
  });

  final bool blocked;
  final bool quarantined;
}

DeviceFirewallDisposition resolveDeviceFirewallDisposition({
  required DeviceFirewallState state,
  required String mac,
  required bool cachedBlocked,
  required bool cachedQuarantined,
}) {
  if (!state.available) {
    return DeviceFirewallDisposition(
      blocked: cachedBlocked,
      quarantined: cachedQuarantined,
    );
  }
  final normalized = _normalizeMac(mac);
  return DeviceFirewallDisposition(
    blocked: state.blockedMacs.contains(normalized),
    quarantined: state.quarantinedMacs.contains(normalized),
  );
}

const _automaticQuarantinePrefix = 'openwalla_quarantine_';
const _manualBlockPrefix = 'owrt_device_block_';
const _pausePrefix = 'owrt_pause_';
const _blockedRulePrefixes = <String>[
  'owrt_parental_',
  'openwalla_parental_',
  'moci_parental_',
  _automaticQuarantinePrefix,
  _manualBlockPrefix,
  'openwalla_schedule_',
];

String _normalizeMac(String value) =>
    value.trim().toUpperCase().replaceAll('-', ':');

Set<String> _ruleMacs(Map rule) {
  final values = <dynamic>[rule['src_mac'], rule['src_mac_address']];
  final macs = <String>{};
  for (final value in values) {
    final entries = value is Iterable
        ? value
        : (value?.toString() ?? '').split(RegExp(r'\s+'));
    for (final entry in entries) {
      final mac = _normalizeMac(entry.toString());
      if (RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac)) {
        macs.add(mac);
      }
    }
  }
  return macs;
}

DeviceFirewallState parseDeviceFirewallState(dynamic result) {
  dynamic data = result;
  if (result is List) {
    if (result.length <= 1 || result[0] != 0) {
      return const DeviceFirewallState(available: false);
    }
    data = result[1];
  }

  final values = data is Map ? data['values'] : null;
  final rules = values is Map
      ? values.values
      : data is Map
      ? data.values
      : const <dynamic>[];
  final enabledRules = rules.whereType<Map>().where(
    (rule) => (rule['enabled']?.toString() ?? '1') != '0',
  );

  final legacyManualMacs = <String>{};
  for (final rule in enabledRules) {
    final name = rule['name']?.toString() ?? '';
    if (name.startsWith(_automaticQuarantinePrefix) &&
        name.endsWith('_router')) {
      legacyManualMacs.addAll(_ruleMacs(rule));
    }
  }

  final blockedMacs = <String>{};
  final quarantinedMacs = <String>{};
  final pausedMacs = <String>{};
  for (final rule in enabledRules) {
    final name = rule['name']?.toString() ?? '';
    final macs = _ruleMacs(rule);
    if (_blockedRulePrefixes.any(name.startsWith)) {
      blockedMacs.addAll(macs);
    }
    if (name.startsWith(_automaticQuarantinePrefix)) {
      quarantinedMacs.addAll(macs);
    }
    if (name.startsWith(_pausePrefix)) {
      pausedMacs.addAll(macs);
    }
  }
  quarantinedMacs.removeAll(legacyManualMacs);

  return DeviceFirewallState(
    blockedMacs: blockedMacs,
    quarantinedMacs: quarantinedMacs,
    pausedMacs: pausedMacs,
  );
}
