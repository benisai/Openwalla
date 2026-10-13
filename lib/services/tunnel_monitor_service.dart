import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:openwalla/services/secure_storage_service.dart';
import 'package:openwalla/utils/http_client_manager.dart';

class TunnelMonitorSettings {
  final String serverUrl;
  final String apiToken;

  const TunnelMonitorSettings({this.serverUrl = '', this.apiToken = ''});

  Uri get statusUri {
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
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/api/v1/tunnel/status',
    );
  }
}

class TunnelMonitorStatus {
  final String host;
  final bool luciAvailable;
  final int luciPort;
  final bool sshAvailable;
  final int sshPort;

  const TunnelMonitorStatus({
    required this.host,
    required this.luciAvailable,
    required this.luciPort,
    required this.sshAvailable,
    required this.sshPort,
  });

  factory TunnelMonitorStatus.fromJson(dynamic data) {
    if (data is! Map ||
        data['host'] is! String ||
        data['luci'] is! Map ||
        data['ssh'] is! Map) {
      throw const FormatException('Unexpected tunnel status response.');
    }
    final luci = data['luci'] as Map;
    final ssh = data['ssh'] as Map;
    if (luci['available'] is! bool ||
        ssh['available'] is! bool ||
        luci['port'] is! int ||
        ssh['port'] is! int) {
      throw const FormatException('Unexpected tunnel endpoint response.');
    }
    return TunnelMonitorStatus(
      host: data['host'] as String,
      luciAvailable: luci['available'] as bool,
      luciPort: luci['port'] as int,
      sshAvailable: ssh['available'] as bool,
      sshPort: ssh['port'] as int,
    );
  }
}

class TunnelMonitorService {
  final SecureStorageService _storage;
  final Dio? _client;

  TunnelMonitorService({SecureStorageService? storage, Dio? client})
    : _storage = storage ?? SecureStorageService(),
      _client = client;

  String _key(String routerId) => 'tunnelMonitor:$routerId';

  Future<TunnelMonitorSettings> load(String routerId) async {
    final saved = await _storage.readValue(_key(routerId));
    if (saved == null) return const TunnelMonitorSettings();
    final data = jsonDecode(saved) as Map<String, dynamic>;
    return TunnelMonitorSettings(
      serverUrl: data['serverUrl'] as String? ?? '',
      apiToken: data['apiToken'] as String? ?? '',
    );
  }

  Future<void> save(String routerId, TunnelMonitorSettings settings) async {
    settings.statusUri;
    await _storage.writeValue(
      _key(routerId),
      jsonEncode({
        'serverUrl': settings.serverUrl.trim(),
        'apiToken': settings.apiToken.trim(),
      }),
    );
  }

  Future<TunnelMonitorStatus> fetch(
    TunnelMonitorSettings settings, {
    CancelToken? cancelToken,
  }) async {
    final uri = settings.statusUri;
    final client =
        _client ??
        HttpClientManager().getClient(uri.authority, uri.scheme == 'https');
    final response = await client.getUri<dynamic>(
      uri,
      cancelToken: cancelToken,
      options: Options(
        followRedirects: false,
        headers: settings.apiToken.trim().isEmpty
            ? null
            : {'Authorization': 'Bearer ${settings.apiToken.trim()}'},
      ),
    );
    return TunnelMonitorStatus.fromJson(response.data);
  }
}
