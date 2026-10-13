import 'dart:convert';

import 'package:openwalla/services/secure_storage_service.dart';

class OpenwallaServerSettings {
  final String serverUrl;
  final String apiToken;

  const OpenwallaServerSettings({this.serverUrl = '', this.apiToken = ''});

  Uri get statusUri => endpoint('/api/v1/tunnel/status');

  Uri endpoint(String path) {
    final base = Uri.tryParse(serverUrl.trim());
    if (base == null ||
        !const ['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException('Enter a valid HTTP or HTTPS server URL.');
    }
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}$path',
    );
  }
}

class OpenwallaServerSettingsStore {
  final SecureStorageService _storage;

  OpenwallaServerSettingsStore({SecureStorageService? storage})
    : _storage = storage ?? SecureStorageService();

  String _key(String routerId) => 'openwalla_server:$routerId';

  Future<OpenwallaServerSettings> load(
    String routerId, {
    String legacyServerUrl = '',
  }) async {
    final saved = await _storage.readValue(_key(routerId));
    if (saved != null) return _decode(saved);

    // Prefer the explicitly saved Tunnel connection over older router UCI data.
    final tunnel = await _storage.readValue('tunnelMonitor:$routerId');
    if (tunnel != null) {
      final settings = _decode(tunnel);
      await save(routerId, settings);
      return settings;
    }
    final token =
        await _storage.readValue('netify_server_token:$routerId') ?? '';
    final settings = OpenwallaServerSettings(
      serverUrl: legacyServerUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      apiToken: token,
    );
    if (settings.serverUrl.isNotEmpty) await save(routerId, settings);
    return settings;
  }

  OpenwallaServerSettings _decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    return OpenwallaServerSettings(
      serverUrl: data['serverUrl'] as String? ?? '',
      apiToken: data['apiToken'] as String? ?? '',
    );
  }

  Future<void> save(String routerId, OpenwallaServerSettings settings) async {
    if (settings.serverUrl.trim().isNotEmpty) settings.statusUri;
    await _storage.writeValue(
      _key(routerId),
      jsonEncode({
        'serverUrl': settings.serverUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        'apiToken': settings.apiToken.trim(),
      }),
    );
  }
}
