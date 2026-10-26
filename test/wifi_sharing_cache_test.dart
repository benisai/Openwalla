import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/router_snapshot_cache.dart';
import 'package:openwalla/services/secure_storage_service.dart';
import 'package:openwalla/services/wifi_sharing_cache.dart';

Map<String, dynamic> config({
  String ssid = 'Home',
  String password = 'wifi-password',
  String encryption = 'psk2',
  String mode = 'ap',
}) => {
  'values': {
    'default_radio0': {
      '.type': 'wifi-iface',
      'mode': mode,
      'ssid': ssid,
      'encryption': encryption,
      'key': password,
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<Map<String, dynamic>> restored(
    WifiSharingCache cache, {
    String id = 'router-a',
    String? fingerprint = 'fp-a',
    String ssid = 'Home',
  }) async {
    final result =
        RouterSnapshotCache.sanitize(config(ssid: ssid))
            as Map<String, dynamic>;
    await cache.restoreInto(id, fingerprint, result);
    return result;
  }

  test(
    'restores password securely without persisting it in display JSON',
    () async {
      await WifiSharingCache().save('router-a', 'fp-a', config());
      final result = await restored(WifiSharingCache());
      expect(result['values']['default_radio0']['key'], 'wifi-password');
      expect(
        jsonEncode(RouterSnapshotCache.sanitize(result)),
        isNot(contains('wifi-password')),
      );
    },
  );

  test(
    'router identity, fingerprint, SSID and encryption must match',
    () async {
      final cache = WifiSharingCache();
      await cache.save('router-a', 'fp-a', config());
      for (final result in [
        await restored(cache, id: 'router-b'),
        await restored(cache, fingerprint: 'fp-b'),
        await restored(cache, ssid: 'Other'),
      ]) {
        expect(result['values']['default_radio0'].containsKey('key'), isFalse);
      }
      final changed =
          RouterSnapshotCache.sanitize(config(encryption: 'sae'))
              as Map<String, dynamic>;
      await cache.restoreInto('router-a', 'fp-a', changed);
      expect(changed['values']['default_radio0'].containsKey('key'), isFalse);
    },
  );

  test('refresh replaces previous password and removes deleted APs', () async {
    final cache = WifiSharingCache();
    await cache.save('router-a', 'fp-a', config());
    await cache.save('router-a', 'fp-a', config(password: 'new-password'));
    expect(
      (await restored(cache))['values']['default_radio0']['key'],
      'new-password',
    );
    await cache.save('router-a', 'fp-a', {'values': <String, dynamic>{}});
    expect(
      (await restored(cache))['values']['default_radio0'].containsKey('key'),
      isFalse,
    );
  });

  test('station/repeater credentials are not stored for sharing', () async {
    await WifiSharingCache().save('router-a', 'fp-a', config(mode: 'sta'));
    final raw = await SecureStorageService().readValue('wifi_sharing:router-a');
    expect(raw, isNot(contains('wifi-password')));
  });

  test('open networks restore an empty password correctly', () async {
    final cache = WifiSharingCache();
    final open = config(password: '', encryption: 'none');
    await cache.save('router-a', 'fp-a', open);
    final result = RouterSnapshotCache.sanitize(open) as Map<String, dynamic>;
    await cache.restoreInto('router-a', 'fp-a', result);
    expect(result['values']['default_radio0']['key'], '');
  });

  test(
    'failed config reads preserve credentials and malformed cache is ignored',
    () async {
      final cache = WifiSharingCache();
      await cache.save('router-a', 'fp-a', config());
      await cache.save('router-a', 'fp-a', null);
      expect(
        (await restored(cache))['values']['default_radio0']['key'],
        'wifi-password',
      );
      await SecureStorageService().writeValue(
        'wifi_sharing:router-a',
        'broken',
      );
      expect(
        (await restored(cache))['values']['default_radio0'].containsKey('key'),
        isFalse,
      );
    },
  );

  test('profile deletion removes only that router credentials', () async {
    final cache = WifiSharingCache();
    await cache.save('router-a', 'fp-a', config());
    await cache.save('router-b', 'fp-b', config(password: 'other-password'));
    await SecureStorageService().deleteRouterScopedValues('router-a');
    expect(
      (await restored(cache))['values']['default_radio0'].containsKey('key'),
      isFalse,
    );
    expect(
      (await restored(
        cache,
        id: 'router-b',
        fingerprint: 'fp-b',
      ))['values']['default_radio0']['key'],
      'other-password',
    );
  });
}
