import 'package:dio/dio.dart';
import 'package:openwalla/services/secure_storage_service.dart';
import 'package:openwalla/services/openwalla_server_settings.dart';
import 'package:openwalla/utils/http_client_manager.dart';

typedef TunnelMonitorSettings = OpenwallaServerSettings;

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
  final OpenwallaServerSettingsStore _settings;
  final Dio? _client;

  TunnelMonitorService({SecureStorageService? storage, Dio? client})
    : _settings = OpenwallaServerSettingsStore(storage: storage),
      _client = client;

  Future<TunnelMonitorSettings> load(String routerId) =>
      _settings.load(routerId);

  Future<void> save(String routerId, TunnelMonitorSettings settings) async {
    settings.statusUri;
    await _settings.save(routerId, settings);
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
