import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/services/router_service.dart';

void main() {
  test('existing dashboard preferences gain new VPN shortcuts', () {
    final preferences = DashboardPreferences.fromJson({
      'shortcutOrder': ['network', 'wifi'],
    });

    expect(preferences.showTorShortcut, isTrue);
    expect(preferences.shortcutOrder, contains('tor'));
    expect(preferences.showTailscaleShortcut, isTrue);
    expect(preferences.shortcutOrder, contains('tailscale'));
    expect(preferences.showQuarantineShortcut, isTrue);
    expect(preferences.shortcutOrder, contains('quarantine'));
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'router profiles retain custom ports and credentials through JSON',
    () async {
      final source = RouterService();
      await source.addRouter(
        Router(
          id: 'router-1',
          ipAddress: 'router.example:8443',
          username: 'root',
          password: 'secret',
          useHttps: true,
          lastKnownHostname: 'OpenWrt Lab',
        ),
      );
      final exported = source.exportRoutersAsJson();
      expect(
        (jsonDecode(exported) as Map<String, dynamic>)['app'],
        'Openwalla',
      );

      FlutterSecureStorage.setMockInitialValues({});
      final restored = RouterService();
      final result = await restored.importRoutersFromJson(exported);

      expect(result.success, isTrue);
      expect(restored.routers.single.ipAddress, 'router.example:8443');
      expect(restored.routers.single.useHttps, isTrue);
      expect(restored.routers.single.password, 'secret');
      expect(restored.routers.single.lastKnownHostname, 'OpenWrt Lab');
    },
  );

  test('router profile import rejects unrelated JSON', () async {
    final result = await RouterService().importRoutersFromJson(
      '{"hello":"world"}',
    );
    expect(result.success, isFalse);
    expect(result.errorMessage, contains('Expected'));
  });
}
