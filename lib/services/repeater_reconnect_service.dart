import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:dio/dio.dart';

import '../utils/router_identity.dart';

const kRepeaterBackgroundReloadCommand = r'''
mkdir -p /tmp/openwalla;
(trap '' HUP; sleep 2;
wifi reload || /sbin/wifi reload;
/etc/init.d/network reload;
/etc/init.d/firewall reload || true;
ifup "$NET" || true) </dev/null >/tmp/openwalla/openwalla-repeater-reload.log 2>&1 &
echo "OPENWALLA_REPEATER_CONFIGURED $SSID $NET"
''';

bool isRepeaterTransportDisconnect(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is SSHSocketError ||
      error is SSHDisconnectError ||
      error is SSHStateError) {
    return true;
  }
  return error is DioException &&
      error.response == null &&
      const {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.unknown,
      }.contains(error.type);
}

class RepeaterReconnectException implements Exception {
  const RepeaterReconnectException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RepeaterReconnectService {
  RepeaterReconnectService({
    required this.call,
    this.timeout = const Duration(seconds: 90),
    this.pollInterval = const Duration(seconds: 2),
    this.maxAttempts = 45,
    this.settleDelay = const Duration(seconds: 3),
  });

  final Future<dynamic> Function(
    String object,
    String method,
    Map<String, dynamic> params,
  )
  call;
  final Duration timeout;
  final Duration pollInterval;
  final int maxAttempts;
  final Duration settleDelay;
  bool _routerReached = false;

  Future<bool> _connected(String interface, String ssid, String bssid) async {
    final status = rpcDataMap(
      await call('network.interface.$interface', 'status', const {}),
    );
    if (status == null) return false;
    _routerReached = true;
    if (status['up'] != true ||
        (status['ipv4-address'] is! List) ||
        !(status['ipv4-address'] as List).whereType<Map>().any(
          (address) =>
              (address['address']?.toString() ?? '').isNotEmpty &&
              address['address'] != '0.0.0.0',
        )) {
      return false;
    }
    final device = (status['l3_device'] ?? status['device'])?.toString() ?? '';
    if (device.isEmpty) return false;
    final wireless = rpcDataMap(
      await call('iwinfo', 'info', {'device': device}),
    );
    return wireless != null &&
        wireless['ssid'] == ssid &&
        (bssid.isEmpty ||
            wireless['bssid']?.toString().toLowerCase() == bssid.toLowerCase());
  }

  Future<void> wait({
    required String interface,
    required String ssid,
    String bssid = '',
  }) async {
    _routerReached = false;
    final clock = Stopwatch()..start();
    await Future<void>.delayed(settleDelay);
    for (
      var attempt = 0;
      attempt < maxAttempts && clock.elapsed < timeout;
      attempt++
    ) {
      final remaining = timeout - clock.elapsed;
      try {
        if (await _connected(interface, ssid, bssid).timeout(
          remaining < const Duration(seconds: 8)
              ? remaining
              : const Duration(seconds: 8),
        )) {
          return;
        }
      } catch (error) {
        if (!isRepeaterTransportDisconnect(error)) {
          throw const RepeaterReconnectException(
            'Wi-Fi setup was sent, but the router could not verify the repeater status. Reconnect to the router and check its status before retrying.',
          );
        }
      }
      if (attempt + 1 < maxAttempts && clock.elapsed + pollInterval < timeout) {
        await Future<void>.delayed(pollInterval);
      }
    }
    throw RepeaterReconnectException(
      _routerReached
          ? 'The router is reachable, but the repeater has not connected to "$ssid" and received an IP address. Check the Wi-Fi password and upstream network, then retry.'
          : 'The router has not reconnected yet. Reconnect your phone to the router Wi-Fi, then refresh to check the repeater. The settings may already have been applied.',
    );
  }
}
