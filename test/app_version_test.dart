import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/app_version.dart';

void main() {
  test('parses the app version from pubspec yaml', () {
    final version = AppVersion.fromPubspec('''
name: openwalla
version: 1.0.400+302
''');

    expect(version?.version, '1.0.400');
    expect(version?.buildNumber, 302);
  });

  test('compares semantic parts before build number', () {
    const installed = AppVersion(version: '1.0.399', buildNumber: 999);
    const available = AppVersion(version: '1.0.400', buildNumber: 1);

    expect(available.compareTo(installed), greaterThan(0));
  });

  test('uses build number when semantic versions match', () {
    const installed = AppVersion(version: '1.0.400', buildNumber: 301);
    const available = AppVersion(version: '1.0.400', buildNumber: 302);

    expect(available.compareTo(installed), greaterThan(0));
  });
}
