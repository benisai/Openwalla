import 'dart:math';

final Random _secureRandom = Random.secure();

String generateRouterProfileId() {
  final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

Map<String, dynamic>? rpcDataMap(dynamic result) {
  if (result is List && result.length > 1 && result.first == 0) {
    final data = result[1];
    if (data is Map) return Map<String, dynamic>.from(data);
  }
  if (result is Map) return Map<String, dynamic>.from(result);
  return null;
}

String? routerSerialFingerprint(dynamic boardResult) {
  final board = rpcDataMap(boardResult);
  if (board == null) return null;
  for (final key in const [
    'serial',
    'serial_number',
    'serialNumber',
    'board_serial',
  ]) {
    final value = board[key]?.toString().trim();
    if (value != null && value.isNotEmpty && value != '0') {
      return 'serial:${value.toLowerCase()}';
    }
  }
  return null;
}

String? routerMacFingerprint(dynamic deviceResult) {
  final device = rpcDataMap(deviceResult);
  if (device == null) return null;
  final raw = (device['macaddr'] ?? device['mac'])?.toString().trim() ?? '';
  final normalized = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toLowerCase();
  if (normalized.length != 12 || normalized == '000000000000') return null;
  return 'lan-mac:$normalized';
}

String? routerInterfaceDeviceName(dynamic interfaceResult) {
  final interface = rpcDataMap(interfaceResult);
  if (interface == null) return null;
  for (final key in const ['l3_device', 'device']) {
    final value = interface[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}
