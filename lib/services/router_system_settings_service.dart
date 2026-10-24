Map<String, dynamic> boardInfoWithHostname(Map boardInfo, String hostname) =>
    <String, dynamic>{
      ...Map<String, dynamic>.from(boardInfo),
      'hostname': hostname.trim(),
    };

class RouterSystemSettings {
  final String section;
  final String hostname;
  final String zoneName;

  const RouterSystemSettings({
    required this.section,
    required this.hostname,
    required this.zoneName,
  });
}

class RouterSystemSettingsService {
  final Future<dynamic> Function(
    String object,
    String method,
    Map<String, dynamic> params,
  )
  call;

  RouterSystemSettingsService({required this.call});

  Map _data(dynamic result) {
    if (result is! List || result.isEmpty || result.first != 0) {
      throw StateError('The router rejected the system settings request.');
    }
    return result.length > 1 && result[1] is Map ? result[1] as Map : {};
  }

  Future<RouterSystemSettings> load() async {
    final values = _data(
      await call('uci', 'get', {'config': 'system'}),
    )['values'];
    if (values is Map) {
      for (final entry in values.entries) {
        final value = entry.value;
        if (value is Map && value['.type'] == 'system') {
          return RouterSystemSettings(
            section: entry.key.toString(),
            hostname: value['hostname']?.toString() ?? '',
            zoneName: value['zonename']?.toString() ?? 'UTC',
          );
        }
      }
    }
    throw StateError('The router has no system configuration section.');
  }

  Future<Map<String, String>> timezones() async {
    final data = _data(await call('luci', 'getTimezones', {}));
    final zones = <String, String>{'UTC': 'UTC0'};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is Map && value['tzstring'] is String) {
        zones[entry.key.toString()] = value['tzstring'] as String;
      }
    }
    return zones;
  }

  static bool validHostname(String value) {
    if (value.isEmpty || value.length > 253) return false;
    return value
        .split('.')
        .every(
          (label) =>
              label.isNotEmpty &&
              label.length <= 63 &&
              RegExp(
                r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$',
              ).hasMatch(label),
        );
  }

  Future<void> saveHostname(String hostname) async {
    final clean = hostname.trim();
    if (!validHostname(clean)) {
      throw ArgumentError(
        'Enter a valid hostname using letters, numbers, and hyphens.',
      );
    }
    await _save({'hostname': clean});
  }

  Future<void> saveTimezone(String zoneName) async {
    final zones = await timezones();
    if (!zones.containsKey(zoneName)) {
      throw ArgumentError('Select a timezone supported by this router.');
    }
    await _save({'zonename': zoneName, 'timezone': zones[zoneName]!});
  }

  Future<void> _save(Map<String, String> values) async {
    final current = await load();
    _data(
      await call('uci', 'set', {
        'config': 'system',
        'section': current.section,
        'values': values,
      }),
    );
    // Like LuCI Save & Apply: rpcd commits and triggers config reloads.
    _data(await call('uci', 'apply', {'rollback': false}));
    final updated = _data(
      await call('uci', 'get', {'config': 'system'}),
    )['values'];
    final entry = updated is Map ? updated[current.section] : null;
    if (entry is! Map || values.entries.any((v) => entry[v.key] != v.value)) {
      throw StateError(
        'The router did not confirm the updated system settings.',
      );
    }
  }
}
