import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/utils/router_setup_commands.dart';

void main() {
  test('router setup preflight reports both internet outcomes', () {
    expect(
      kOpenwallaInternetPreflightCommand,
      contains('Internet connection: available.'),
    );
    expect(
      kOpenwallaInternetPreflightCommand,
      contains('Internet connection: unavailable.'),
    );
    expect(
      kOpenwallaInternetPreflightCommand,
      contains('setup-openwrt-router.sh'),
    );
    expect(kOpenwallaInternetPreflightCommand, contains('exit 20'));
  });

  test('router setup preflight can be safely chained in ash', () {
    final command = [
      openwallaInternetPreflightShellBlock,
      'echo next',
    ].join(' && ');

    expect(command, startsWith('{\n'));
    expect(command, contains('\n} && echo next'));
    expect(command, isNot(contains('\n &&')));
  });
}
