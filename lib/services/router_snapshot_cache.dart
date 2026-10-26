import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:openwalla/models/client.dart';

/// One bounded, replaceable snapshot per saved router, never keyed by address.
class RouterSnapshotCache {
  RouterSnapshotCache({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;
  final Map<String, Future<void>> _writes = {};
  static const maxBytes = 8 * 1024 * 1024;

  Future<File> _file(String id) async {
    final name = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    final directory = Directory(
      '${(await _directory()).path}/router_snapshots',
    );
    await directory.create(recursive: true);
    return File('${directory.path}/$name.json');
  }

  Future<Map<String, dynamic>?> load(String id, String? fingerprint) async {
    try {
      final file = await _file(id);
      if (!await file.exists() || await file.length() > maxBytes) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic> ||
          data['version'] != 1 ||
          data['routerId'] != id ||
          data['sections'] is! Map) {
        return null;
      }
      if (fingerprint != null && data['fingerprint'] != fingerprint) {
        return null;
      }
      if ((data['sections'] as Map).values.any(
        (entry) =>
            entry is! Map ||
            !entry.containsKey('data') ||
            DateTime.tryParse(entry['savedAt']?.toString() ?? '') == null,
      )) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _serialize(String id, Future<void> Function() action) {
    final future = (_writes[id] ?? Future<void>.value()).then((_) => action());
    _writes[id] = future.catchError((Object _) {});
    return future;
  }

  Future<void> save(
    String id,
    String? fingerprint,
    String section,
    Object? value,
  ) {
    final safe = sanitize(value);
    return _serialize(id, () async {
      final data =
          await load(id, fingerprint) ??
          <String, dynamic>{
            'version': 1,
            'routerId': id,
            'fingerprint': fingerprint,
            'sections': {},
          };
      final sections = data['sections'] as Map;
      sections[section] = {
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'data': safe,
      };
      if (sections.length > 64) throw StateError('Too many cached sections');
      final encoded = jsonEncode(data);
      if (utf8.encode(encoded).length > maxBytes) {
        throw StateError('Snapshot too large');
      }
      final file = await _file(id);
      final temporary = File('${file.path}.new');
      await temporary.writeAsString(encoded, flush: true);
      await temporary.rename(file.path);
    });
  }

  Future<void> delete(String id) => _serialize(id, () async {
    final file = await _file(id);
    for (final path in [file.path, '${file.path}.new']) {
      final target = File(path);
      if (await target.exists()) await target.delete();
    }
  });

  static const _secretKeys = {
    'key',
    'key1',
    'key2',
    'key3',
    'key4',
    'dae_secret',
    'password',
    'passwd',
    'passphrase',
    'psk',
    'sae_password',
    'privatekey',
    'private_key',
    'presharedkey',
    'preshared_key',
    'token',
    'sysauth',
    'ubus_rpc_session',
    'secret',
    'auth_secret',
    'radius_secret',
    'acct_secret',
    'server_token',
    'api_key',
  };

  static Object? sanitize(Object? value) {
    if (value == null || value is String || value is bool || value is num) {
      return value;
    }
    if (value is Iterable) return value.map(sanitize).toList();
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (!_secretKeys.contains(entry.key.toString().toLowerCase()))
            entry.key.toString(): sanitize(entry.value),
      };
    }
    throw ArgumentError('Unsupported snapshot value: ${value.runtimeType}');
  }

  static Map<String, dynamic> encodeClient(Client c) => {
    'ipAddress': c.ipAddress,
    'macAddress': c.macAddress,
    'hostname': c.hostname,
    'hostId': c.hostId,
    'leaseTime': c.leaseTime,
    'vendor': c.vendor,
    'dnsName': c.dnsName,
    'clientId': c.clientId,
    'activeTime': c.activeTime,
    'expiresAt': c.expiresAt,
    'connectionType': c.connectionType.name,
    'ssid': c.ssid,
    'wirelessInterface': c.wirelessInterface,
    'wirelessBand': c.wirelessBand,
    'ipv6Addresses': c.ipv6Addresses,
    'isBlocked': c.isBlocked,
    'isQuarantined': c.isQuarantined,
    'totalUploadBytes': c.totalUploadBytes,
    'totalDownloadBytes': c.totalDownloadBytes,
    'staticIpAddress': c.staticIpAddress,
    'status': c.status,
    'deviceIcon': c.deviceIcon,
    'scheduledBlockUntil': c.scheduledBlockUntil,
  };

  static Client decodeClient(Map<String, dynamic> c) => Client(
    ipAddress: c['ipAddress'] as String,
    macAddress: c['macAddress'] as String,
    hostname: c['hostname'] as String,
    hostId: c['hostId'] as String?,
    leaseTime: c['leaseTime'] as int?,
    vendor: c['vendor'] as String?,
    dnsName: c['dnsName'] as String?,
    clientId: c['clientId'] as String?,
    activeTime: c['activeTime'] as int?,
    expiresAt: c['expiresAt'] as int?,
    connectionType: ConnectionType.values.firstWhere(
      (v) => v.name == c['connectionType'],
      orElse: () => ConnectionType.unknown,
    ),
    ssid: c['ssid'] as String?,
    wirelessInterface: c['wirelessInterface'] as String?,
    wirelessBand: c['wirelessBand'] as String?,
    ipv6Addresses: (c['ipv6Addresses'] as List?)?.cast<String>(),
    isBlocked: c['isBlocked'] == true,
    isQuarantined: c['isQuarantined'] == true,
    totalUploadBytes: c['totalUploadBytes'] as int? ?? 0,
    totalDownloadBytes: c['totalDownloadBytes'] as int? ?? 0,
    staticIpAddress: c['staticIpAddress'] as String?,
    status: c['status'] as String? ?? 'unknown',
    deviceIcon: c['deviceIcon'] as String?,
    scheduledBlockUntil: c['scheduledBlockUntil'] as String?,
  );
}
