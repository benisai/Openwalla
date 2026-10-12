import 'rpc_result.dart';

typedef QuarantineRpcCall =
    Future<dynamic> Function(
      String object,
      String method,
      Map<String, dynamic> params,
    );

const manualDeviceBlockPrefix = 'owrt_device_block_';

Future<void> releaseQuarantineRules({
  required String mac,
  required QuarantineRpcCall call,
  required Future<void> Function() reloadFirewall,
}) async {
  final normalizedMac = mac.toUpperCase().replaceAll('-', ':');
  if (!RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(normalizedMac)) {
    throw ArgumentError('A valid device MAC address is required');
  }

  dynamic checked(dynamic response, String action) {
    if (rpcUbusStatusCode(response) != 0) {
      final status = rpcUbusStatusCode(response);
      throw StateError(
        'Router rejected $action (RPC $status${status == 6 ? ': Access denied' : ''})',
      );
    }
    return response.length > 1 ? response[1] : null;
  }

  final data = checked(
    await call('uci', 'get', {'config': 'firewall'}),
    'reading quarantine rules',
  );
  if (data is! Map || data['values'] is! Map) {
    throw StateError('Router returned an invalid firewall configuration');
  }
  for (final entry in (data['values'] as Map).entries) {
    final rule = entry.value;
    if (rule is! Map || rule['.type'] != 'rule') continue;
    final name = rule['name']?.toString() ?? '';
    if (!name.startsWith('openwalla_quarantine_') &&
        !name.startsWith(manualDeviceBlockPrefix)) {
      continue;
    }
    final addresses = [rule['src_mac'], rule['src_mac_address']].expand((
      value,
    ) {
      return value is Iterable
          ? value
          : (value?.toString() ?? '').split(RegExp(r'\s+'));
    });
    if (!addresses.any(
      (value) =>
          value.toString().toUpperCase().replaceAll('-', ':') == normalizedMac,
    )) {
      continue;
    }
    checked(
      await call('uci', 'delete', {'config': 'firewall', 'section': entry.key}),
      'removing quarantine rule ${entry.key}',
    );
  }
  checked(
    await call('uci', 'commit', {'config': 'firewall'}),
    'saving quarantine release',
  );
  try {
    checked(
      await call('uci', 'apply', {'rollback': false}),
      'applying quarantine release',
    );
  } catch (_) {
    await reloadFirewall();
  }
}
