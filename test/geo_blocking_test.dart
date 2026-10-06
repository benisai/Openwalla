import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/data/geo_countries.dart';
import 'package:openwalla/utils/geo_blocking.dart';

void main() {
  test('bundled country picker data matches the accepted ISO code set', () {
    expect(geoCountries, hasLength(249));
    expect(geoCountries.map((country) => country.code).toSet(), hasLength(249));
    expect(
      geoCountries.every(
        (country) =>
            RegExp(r'^[A-Z]{2}$').hasMatch(country.code) &&
            country.name.isNotEmpty,
      ),
      isTrue,
    );
    expect(
      geoCountries.singleWhere((country) => country.code == 'US').name,
      'United States',
    );
  });

  test('normalizes, sorts, and de-duplicates country codes', () {
    expect(normalizeGeoCountryCodes('us, de US;ca'), 'CA DE US');
  });

  test('rejects empty and malformed country codes', () {
    expect(
      () => normalizeGeoCountryCodes(''),
      throwsA(isA<GeoBlockingInputException>()),
    );
    expect(
      () => normalizeGeoCountryCodes('USA DE'),
      throwsA(isA<GeoBlockingInputException>()),
    );
  });

  test('parses country codes and active state from router status', () {
    const status =
        '\u001b[34mGeo-blocking: enabled\u001b[0m\n'
        'Country codes: us de\n'
        'Direction: inbound and outbound';
    expect(countryCodesFromGeoBlockingStatus(status), 'DE US');
    expect(geoBlockingStatusIsEnabled(status), isTrue);
    expect(
      geoBlockingStatusIsEnabled(status.replaceFirst('enabled', 'disabled')),
      isFalse,
    );
  });

  test('parses wrapped banIP runtime fields', () {
    const status = '''
Geo-blocking: enabled
Country codes: cn ru
::: banIP runtime information
  + status         : running
  + frontend_ver   : 1.9.0-r1
  + element_count  : 120 (chains: 3, sets: 2, rules: 4)
  + run_flags      : auto: ✔, proto (4/6): ✔/✘,
                     split: ✔, debug: ✘
  + system_info    : cores: 2, OpenWrt 25.12.5
''';
    expect(banIpRuntimeFields(status), containsPair('status', 'running'));
    expect(banIpRuntimeFields(status)['run_flags'], contains('split: ✔'));
    expect(banIpRuntimeFields(status)['element_count'], contains('sets: 2'));
  });
}
