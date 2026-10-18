class DhcpHostIdentity {
  final String section;
  final String name;

  const DhcpHostIdentity({required this.section, required this.name});
}

String normalizeDeviceMac(String value) =>
    value.trim().toUpperCase().replaceAll('-', ':');

DhcpHostIdentity? findDhcpHostIdentity(dynamic response, String mac) {
  final data = response is List && response.length > 1
      ? (response[0] == 0 ? response[1] : null)
      : response;
  if (data is! Map) return null;

  final rawValues = data['values'] is Map ? data['values'] as Map : data;
  final expectedMac = normalizeDeviceMac(mac);
  for (final entry in rawValues.entries) {
    final value = entry.value;
    if (value is! Map || value['.type']?.toString() != 'host') continue;
    final rawMacs = value['mac'];
    final macs = rawMacs is Iterable && rawMacs is! String
        ? rawMacs
        : (rawMacs?.toString() ?? '').split(RegExp(r'[\s,]+'));
    if (!macs.any(
      (candidate) => normalizeDeviceMac(candidate.toString()) == expectedMac,
    )) {
      continue;
    }
    return DhcpHostIdentity(
      section: entry.key.toString(),
      name: value['name']?.toString().trim() ?? '',
    );
  }
  return null;
}

bool dhcpHostIdentityMatches(
  dynamic response, {
  required String mac,
  required String name,
}) {
  final identity = findDhcpHostIdentity(response, mac);
  return identity != null && identity.name == name.trim();
}
