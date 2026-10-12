import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/utils/quarantine_release.dart';

void main() {
  const mac = 'AA:BB:CC:DD:EE:FF';
  late List<String> deleted;
  late List<String> methods;
  late int fallbackCount;
  late String? reject;

  Future<dynamic> call(
    String object,
    String method,
    Map<String, dynamic> params,
  ) async {
    methods.add(method);
    if (method == reject) return [6];
    if (method == 'get') {
      return [
        0,
        {
          'values': {
            'lan': {
              '.type': 'rule',
              'name': 'openwalla_quarantine_phone_lan',
              'src_mac': mac.toLowerCase(),
            },
            'wan': {
              '.type': 'rule',
              'name': 'openwalla_quarantine_phone_wan',
              'src_mac': [mac],
            },
            'router': {
              '.type': 'rule',
              'name': 'openwalla_quarantine_phone_router',
              'src_mac_address': mac,
            },
            'other_device': {
              '.type': 'rule',
              'name': 'openwalla_quarantine_other',
              'src_mac': '11:22:33:44:55:66',
            },
            'unrelated': {
              '.type': 'rule',
              'name': 'custom_rule',
              'src_mac': mac,
            },
          },
        },
      ];
    }
    if (method == 'delete') deleted.add(params['section'] as String);
    return [0];
  }

  Future<void> release({bool reloadFails = false}) => releaseQuarantineRules(
    mac: mac,
    call: call,
    reloadFirewall: () async {
      fallbackCount++;
      if (reloadFails) throw StateError('reload failed');
    },
  );

  setUp(() {
    deleted = [];
    methods = [];
    fallbackCount = 0;
    reject = null;
  });

  test(
    'removes all matching quarantine rules and applies through native UCI',
    () async {
      await release();
      expect(deleted, ['lan', 'wan', 'router']);
      expect(methods, ['get', 'delete', 'delete', 'delete', 'commit', 'apply']);
      expect(fallbackCount, 0);
    },
  );

  for (final method in ['get', 'delete', 'commit']) {
    test(
      'RPC access denial during $method is reported instead of success',
      () async {
        reject = method;
        await expectLater(release(), throwsStateError);
        expect(methods, isNot(contains('apply')));
        expect(fallbackCount, 0);
      },
    );
  }

  test('falls forward to reload when native apply is unavailable', () async {
    reject = 'apply';
    await release();
    expect(fallbackCount, 1);
  });

  test('does not report success when both apply and reload fail', () async {
    reject = 'apply';
    await expectLater(release(reloadFails: true), throwsStateError);
  });
}
