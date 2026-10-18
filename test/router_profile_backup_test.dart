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
    expect(preferences.showGeoBlockingShortcut, isTrue);
    expect(preferences.shortcutOrder, contains('geo_blocking'));
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

  test('new profiles use separate UUIDs for the same router address', () {
    final service = RouterService();
    final first = service.createRouter('192.168.1.1', 'root', 'one', false);
    final second = service.createRouter('192.168.1.1', 'root', 'two', false);

    expect(first.id, isNot(second.id));
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(first.id),
      isTrue,
    );
  });

  test('fingerprint locates a profile independently of its address', () async {
    final service = RouterService();
    final router = service
        .createRouter('192.168.1.1', 'root', 'secret', false)
        .copyWith(fingerprint: 'lan-mac:001122334455');
    await service.addRouter(router);

    expect(service.findByFingerprint('lan-mac:001122334455')?.id, router.id);
  });

  test('legacy profile migration keeps selected and scoped settings', () async {
    const oldId = '192.168.1.1-root';
    FlutterSecureStorage.setMockInitialValues({
      'routers': jsonEncode([
        {
          'id': oldId,
          'ipAddress': '192.168.1.1',
          'username': 'root',
          'password': 'secret',
          'useHttps': false,
        },
      ]),
      'selectedRouterId': oldId,
      'dashboard_preferences:$oldId': '{"showFlowsCard":true}',
    });

    final service = RouterService();
    await service.loadRouters();
    final migrated = service.routers.single;
    final storage = const FlutterSecureStorage();

    expect(migrated.id, isNot(oldId));
    expect(migrated.identityVersion, 2);
    expect(service.selectedRouter?.id, migrated.id);
    expect(
      await storage.read(key: 'dashboard_preferences:${migrated.id}'),
      '{"showFlowsCard":true}',
    );
    expect(await storage.read(key: 'dashboard_preferences:$oldId'), isNull);
  });
}
