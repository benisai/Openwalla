class GeoBlockingInputException implements Exception {
  final String message;

  const GeoBlockingInputException(this.message);

  @override
  String toString() => message;
}

String normalizeGeoCountryCodes(String value) {
  final codes = value
      .toUpperCase()
      .split(RegExp(r'[\s,;]+'))
      .where((code) => code.isNotEmpty)
      .toSet()
      .toList();
  if (codes.isEmpty) {
    throw const GeoBlockingInputException(
      'Enter at least one two-letter country code.',
    );
  }
  final invalid = codes.where((code) => !RegExp(r'^[A-Z]{2}$').hasMatch(code));
  if (invalid.isNotEmpty) {
    throw GeoBlockingInputException(
      'Invalid country code${invalid.length == 1 ? '' : 's'}: ${invalid.join(', ')}',
    );
  }
  codes.sort();
  return codes.join(' ');
}

String sanitizeGeoBlockingStatus(String value) {
  return value.replaceAll(RegExp('\u001b\\[[0-9;]*m'), '').trim();
}

String? countryCodesFromGeoBlockingStatus(String value) {
  final clean = sanitizeGeoBlockingStatus(value);
  final match = RegExp(
    r'^\s*Country codes:\s*([A-Za-z]{2}(?:\s+[A-Za-z]{2})*)\s*$',
    multiLine: true,
  ).firstMatch(clean);
  return match == null ? null : normalizeGeoCountryCodes(match.group(1)!);
}

bool geoBlockingStatusIsEnabled(String value) {
  final normalized = sanitizeGeoBlockingStatus(value).toLowerCase();
  return RegExp(
    r'^geo-blocking:\s*enabled\s*$',
    multiLine: true,
  ).hasMatch(normalized);
}
