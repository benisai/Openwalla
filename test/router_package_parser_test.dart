import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  test('parses and deduplicates APK command and database formats', () {
    const output = '''
__MANAGER__|apk
WARNING: opening from cache
busybox-1.36.1-r2
luci-mod-status-24.10.0-r1 aarch64 {openwrt_base} [installed]

P:busybox
V:1.36.1-r2
T:Size optimized toolbox

P:zlib
V:1.3.1-r2
''';

    final packages = parseInstalledRouterPackages(
      output,
      RouterPackageManager.apk,
    );

    expect(packages.map((package) => package.name), [
      'busybox',
      'luci-mod-status',
      'zlib',
    ]);
    expect(packages.first.version, '1.36.1-r2');
  });

  test('parses OPKG list and status database formats', () {
    const output = '''
__MANAGER__|opkg
base-files - 1563-r1

Package: luci-base
Version: git-26.210.44122
Status: install user installed

Package: removed-package
Version: 1-r1
Status: deinstall user not-installed
''';

    final packages = parseInstalledRouterPackages(
      output,
      RouterPackageManager.opkg,
    );

    expect(packages.map((package) => package.name), [
      'base-files',
      'luci-base',
    ]);
  });
}
