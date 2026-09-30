import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/screens/router_components_screen.dart';

void main() {
  test('uses the repository-provided component version', () {
    final status = RouterComponentStatus.parse('''
AVAILABLE_VERSION|2026.09.28.4
INSTALLED_VERSION|2026.09.28.3
OUTDATED|/usr/bin/openwalla-network-monitor
SUMMARY|managed=12|current=11|updated=0|failed=0
''');

    expect(status.availableVersion, '2026.09.28.4');
    expect(status.installedVersion, '2026.09.28.3');
    expect(status.managedCount, 12);
    expect(status.isCurrent, isFalse);
  });

  test('is current when repository and installed versions match', () {
    final status = RouterComponentStatus.parse('''
AVAILABLE_VERSION|2026.09.28.4
INSTALLED_VERSION|2026.09.28.4
SUMMARY|managed=12|current=12|updated=0|failed=0
''');

    expect(status.isCurrent, isTrue);
  });
}
