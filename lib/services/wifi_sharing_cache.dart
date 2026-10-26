import 'dart:convert';

import 'secure_storage_service.dart';

/// Wi-Fi credentials belong in secure storage, never the display JSON snapshot.
class WifiSharingCache {
  WifiSharingCache({SecureStorageService? storage})
    : _storage = storage ?? SecureStorageService();
  final SecureStorageService _storage;
  String _key(String id) => 'wifi_sharing:$id';

  Map? _sections(Object? config) => config is Map
      ? (config['values'] is Map ? config['values'] as Map : config)
      : null;

  Future<void> save(
    String id,
    String? fingerprint,
    Object? wirelessConfig,
  ) async {
    final sections = _sections(wirelessConfig);
    if (sections == null) return;
    final networks = <String, dynamic>{};
    for (final entry in sections.entries) {
      final config = entry.value;
      if (config is! Map ||
          config['.type'] != 'wifi-iface' ||
          config['mode'] != 'ap') {
        continue;
      }
      final ssid = config['ssid']?.toString() ?? '';
      final encryption = config['encryption']?.toString() ?? '';
      if (ssid.isEmpty || encryption.isEmpty) continue;
      final password = config['key']?.toString() ?? '';
      if (encryption != 'none' && encryption != 'nopass' && password.isEmpty) {
        continue;
      }
      networks[entry.key.toString()] = {
        'ssid': ssid,
        'encryption': encryption,
        'password': password,
      };
    }
    await _storage.writeValue(
      _key(id),
      jsonEncode({
        'version': 1,
        'fingerprint': fingerprint,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'networks': networks,
      }),
    );
  }

  Future<void> restoreInto(
    String id,
    String? fingerprint,
    Object? wirelessConfig,
  ) async {
    final sections = _sections(wirelessConfig);
    if (sections == null) return;
    final saved = await _storage.readValue(_key(id));
    if (saved == null) return;
    try {
      final data = jsonDecode(saved);
      if (data is! Map ||
          data['version'] != 1 ||
          data['fingerprint'] != fingerprint ||
          data['networks'] is! Map) {
        return;
      }
      final networks = data['networks'] as Map;
      for (final entry in sections.entries) {
        final config = entry.value;
        final network = networks[entry.key];
        if (config is! Map || config['mode'] != 'ap' || network is! Map) {
          continue;
        }
        if (config['ssid'] == network['ssid'] &&
            config['encryption'] == network['encryption'] &&
            network['password'] is String) {
          config['key'] = network['password'];
        }
      }
    } on FormatException {
      // An incompatible or damaged credential cache must not prevent offline viewing.
    }
  }
}
