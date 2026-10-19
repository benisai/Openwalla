import 'package:flutter/services.dart';
import '../utils/router_identity.dart';

enum DeviceBlockReason { manual, quarantine }

typedef DeviceAccessRpc = Future<dynamic> Function(List<String> args);
typedef DeviceAccessSsh =
    Future<String> Function(String script, List<String> args);

class DeviceAccessService {
  DeviceAccessService({required this.rpc, required this.ssh, this.loadScript});

  final DeviceAccessRpc rpc;
  final DeviceAccessSsh ssh;
  final Future<String> Function()? loadScript;

  Future<void> change({
    required String mac,
    required bool blocked,
    DeviceBlockReason? reason,
  }) async {
    final normalized = mac.trim().toLowerCase().replaceAll('-', ':');
    if (!RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$').hasMatch(normalized)) {
      throw ArgumentError('A valid device MAC address is required');
    }
    final source =
        await (loadScript?.call() ??
            rootBundle.loadString(
              'openwrt-setup/files/openwalla-device-access.sh',
            ));
    final script = '$source\nopenwalla_device_access "\$1" "\$2" "\$3" "\$4"\n';
    final args = [
      blocked ? 'block' : 'release',
      reason?.name ?? (blocked ? 'manual' : 'current'),
      normalized,
      generateRouterProfileId(),
    ];
    final expected = 'OPENWALLA_DEVICE_ACCESS_OK|${args.take(3).join('|')}';
    dynamic response;
    try {
      response = await rpc(['-c', script, 'openwalla-device-access', ...args]);
    } catch (_) {
      final output = await ssh(script, args);
      if (!output.split('\n').contains(expected)) {
        throw StateError('Router could not verify the device access change');
      }
      return;
    }
    if (response is! List || response.isEmpty || response[0] != 0) {
      final output = await ssh(script, args);
      if (!output.split('\n').contains(expected)) {
        throw StateError('Router could not verify the device access change');
      }
      return;
    }
    final data = response.length > 1 ? response[1] : null;
    if (data is! Map ||
        data['code'] != 0 ||
        !(data['stdout']?.toString().split('\n').contains(expected) ?? false)) {
      throw StateError(
        'Router could not verify the device access change. '
        '${data is Map ? data['stderr']?.toString().trim() ?? '' : ''}',
      );
    }
  }
}
