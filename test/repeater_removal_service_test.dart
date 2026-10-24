import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/repeater_removal_service.dart';

void main() {
  const sta = 'owrt_sta_radio0';
  const before = [
    0,
    {
      'values': {
        sta: {'.type': 'wifi-iface', 'mode': 'sta'},
        'default_radio0': {'.type': 'wifi-iface', 'mode': 'ap'},
      },
    },
  ];
  const after = [
    0,
    {
      'values': {
        'default_radio0': {'.type': 'wifi-iface', 'mode': 'ap'},
      },
    },
  ];
  const clean = [
    0,
    {'changes': {}},
  ];

  test('deletes only the selected station then applies and verifies', () async {
    final calls = <String>[];
    var reads = 0;
    await RepeaterRemovalService(
      call: (object, method, params) async {
        calls.add(method);
        expect(object, 'uci');
        if (method != 'apply') expect(params['config'], 'wireless');
        switch (method) {
          case 'get':
            return reads++ == 0 ? before : after;
          case 'delete':
            expect(params, {'config': 'wireless', 'section': sta});
            return [0];
          case 'apply':
            expect(params, {'rollback': false});
            return [0];
          case 'changes':
            return clean;
        }
        fail('Unexpected $method');
      },
    ).remove(sta);
    expect(calls, ['get', 'delete', 'apply', 'changes', 'get']);
  });

  for (final section in ['default_radio0', 'radio0', 'missing']) {
    test('refuses AP, radio, or missing section: $section', () async {
      final calls = <String>[];
      final service = RepeaterRemovalService(
        call: (object, method, params) async {
          calls.add(method);
          return before;
        },
      );
      await expectLater(service.remove(section), throwsStateError);
      expect(calls, ['get']);
    });
  }

  test('rejects invalid section before any request', () async {
    final service = RepeaterRemovalService(
      call: (_, _, _) async => fail('Must not call router'),
    );
    await expectLater(service.remove('radio0; reboot'), throwsArgumentError);
  });

  for (final rejected in ['get', 'delete', 'apply']) {
    test('does not report success after rejected $rejected', () async {
      final calls = <String>[];
      final service = RepeaterRemovalService(
        call: (_, method, _) async {
          calls.add(method);
          if (method == rejected) return [6];
          return method == 'get' ? before : [0];
        },
      );
      await expectLater(service.remove(sta), throwsStateError);
      expect(calls.last, rejected);
    });
  }

  test(
    'retries verification after apply disconnect without deleting again',
    () async {
      var reads = 0;
      var checks = 0;
      var deletes = 0;
      var applies = 0;
      await RepeaterRemovalService(
        pollInterval: Duration.zero,
        call: (_, method, _) async {
          switch (method) {
            case 'get':
              return reads++ == 0 ? before : after;
            case 'delete':
              deletes++;
              return [0];
            case 'apply':
              applies++;
              throw const SocketException('Restarting');
            case 'changes':
              if (checks++ == 0) throw const SocketException('Restarting');
              return clean;
          }
          fail('Unexpected method');
        },
      ).remove(sta);
      expect(deletes, 1);
      expect(applies, 1);
      expect(checks, 2);
    },
  );

  for (final pending in [true, false]) {
    test(
      'uncommitted deletion or still-present station is not success: $pending',
      () async {
        var reads = 0;
        final service = RepeaterRemovalService(
          timeout: const Duration(milliseconds: 10),
          pollInterval: const Duration(milliseconds: 2),
          call: (_, method, _) async {
            if (method == 'get') {
              return reads++ == 0 || !pending ? before : after;
            }
            if (method == 'changes') {
              return pending
                  ? [
                      0,
                      {
                        'changes': {
                          'wireless': [
                            ['remove', sta],
                          ],
                        },
                      },
                    ]
                  : clean;
            }
            return [0];
          },
        );
        await expectLater(service.remove(sta), throwsStateError);
      },
    );
  }

  test('write-stage disconnect is not mistaken for successful apply', () async {
    final calls = <String>[];
    final service = RepeaterRemovalService(
      call: (_, method, _) async {
        calls.add(method);
        if (method == 'delete') throw const SocketException('Disconnected');
        return before;
      },
    );
    await expectLater(service.remove(sta), throwsA(isA<SocketException>()));
    expect(calls, ['get', 'delete']);
  });
}
