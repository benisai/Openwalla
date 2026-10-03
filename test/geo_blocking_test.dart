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
        '\u001b[34mInbound geoblocking:\u001b[0m\n'
        '  Mode: blacklist\n'
        '  Country codes: us de\n'
        'Outbound geoblocking:\n'
        '  Mode: blacklist\n'
        '  Country codes: us de';
    expect(countryCodesFromGeoBlockingStatus(status), 'DE US');
    expect(geoBlockingStatusIsEnabled(status), isTrue);
    expect(
      geoBlockingStatusIsEnabled('$status\n*Geoblocking inactive*'),
      isFalse,
    );
    expect(
      geoBlockingStatusIsEnabled(
        status.replaceFirst('Mode: blacklist', 'Mode: disable'),
      ),
      isFalse,
    );
  });
}
