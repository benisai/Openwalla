import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/repeater_reconnect_service.dart';

void main() {
  final request = RequestOptions(path: '/cgi-bin/luci/admin/ubus');
  DioException offline([
    DioExceptionType type = DioExceptionType.connectionError,
  ]) => DioException(
    requestOptions: request,
    type: type,
    error: const SocketException('Network is unreachable'),
  );
  const uplink = [
    0,
    {
      'up': true,
      'l3_device': 'phy0-sta0',
      'ipv4-address': [
        {'address': '192.168.8.20', 'mask': 24},
      ],
    },
  ];
  const association = [
    0,
    {'ssid': 'upstream', 'bssid': 'AA:BB:CC:DD:EE:FF'},
  ];

  RepeaterReconnectService monitor(
    Future<dynamic> Function(String, String, Map<String, dynamic>) call, {
    int attempts = 4,
  }) => RepeaterReconnectService(
    call: call,
    maxAttempts: attempts,
    settleDelay: Duration.zero,
    pollInterval: Duration.zero,
  );

  test(
    'temporary radio-reload disconnection is retried then verified',
    () async {
      var probes = 0;
      final service = monitor((object, method, params) async {
        if (object == 'network.interface.wwan') {
          probes++;
          if (probes < 3) throw offline();
          return uplink;
        }
        expect(object, 'iwinfo');
        expect(params['device'], 'phy0-sta0');
        return association;
      });
      await service.wait(
        interface: 'wwan',
        ssid: 'upstream',
        bssid: 'aa:bb:cc:dd:ee:ff',
      );
      expect(probes, 3);
    },
  );

  test(
    'a reply or saved configuration alone is not connection success',
    () async {
      var associations = 0;
      final service = monitor((object, method, params) async {
        if (object.startsWith('network.interface.')) return uplink;
        associations++;
        return [
          0,
          {'ssid': associations < 3 ? 'old-network' : 'upstream'},
        ];
      });
      await service.wait(interface: 'wwan', ssid: 'upstream');
      expect(associations, 3);
    },
  );

  test('selected BSSID and acquired DHCP address must both match', () async {
    var probes = 0;
    var associations = 0;
    final service = monitor((object, method, params) async {
      if (object.startsWith('network.interface.')) {
        probes++;
        if (probes == 1) {
          return [
            0,
            {'up': false},
          ];
        }
        if (probes == 2) {
          return [
            0,
            {'up': true, 'ipv4-address': []},
          ];
        }
        return uplink;
      }
      associations++;
      return associations == 1
          ? [
              0,
              {'ssid': 'upstream', 'bssid': '00:00:00:00:00:00'},
            ]
          : association;
    }, attempts: 5);
    await service.wait(
      interface: 'wwan',
      ssid: 'upstream',
      bssid: 'aa:bb:cc:dd:ee:ff',
    );
    expect(probes, 4);
  });

  test(
    'an offline router produces reconnection guidance, not raw Dio errors',
    () async {
      var calls = 0;
      final service = monitor((object, method, params) async {
        calls++;
        throw offline();
      });
      await expectLater(
        service.wait(interface: 'wwan', ssid: 'upstream'),
        throwsA(
          isA<RepeaterReconnectException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Reconnect your phone'),
              isNot(contains('DioException')),
            ),
          ),
        ),
      );
      expect(calls, 4);
    },
  );

  test(
    'wrong password or unavailable upstream is not reported as success',
    () async {
      final service = monitor(
        (object, method, params) async => [
          0,
          {'up': false},
        ],
      );
      await expectLater(
        service.wait(interface: 'wwan', ssid: 'upstream'),
        throwsA(
          isA<RepeaterReconnectException>().having(
            (e) => e.message,
            'message',
            contains('Check the Wi-Fi password'),
          ),
        ),
      );
    },
  );

  test(
    'HTTP and authorization failures are not retried as radio restarts',
    () async {
      var calls = 0;
      final denied = DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: request, statusCode: 403),
      );
      final service = monitor((object, method, params) async {
        calls++;
        throw denied;
      });
      await expectLater(
        service.wait(interface: 'wwan', ssid: 'upstream'),
        throwsA(isA<RepeaterReconnectException>()),
      );
      expect(calls, 1);
      expect(isRepeaterTransportDisconnect(denied), isFalse);
      expect(
        isRepeaterTransportDisconnect(SSHAuthFailError('denied')),
        isFalse,
      );
      expect(
        isRepeaterTransportDisconnect(StateError('Access denied')),
        isFalse,
      );
    },
  );

  test('transport classifier covers connect, send and receive timeouts', () {
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      expect(isRepeaterTransportDisconnect(offline(type)), isTrue);
    }
    expect(isRepeaterTransportDisconnect(TimeoutException('offline')), isTrue);
    expect(
      isRepeaterTransportDisconnect(
        SSHSocketError(const SocketException('closed')),
      ),
      isTrue,
    );
    expect(
      isRepeaterTransportDisconnect(SSHDisconnectError(11, 'closed')),
      isTrue,
    );
  });

  test('an unresponsive probe cannot exceed the reconnect deadline', () async {
    final service = RepeaterReconnectService(
      call: (object, method, params) => Completer<dynamic>().future,
      timeout: const Duration(milliseconds: 20),
      settleDelay: Duration.zero,
      pollInterval: Duration.zero,
    );
    final clock = Stopwatch()..start();
    await expectLater(
      service.wait(interface: 'wwan', ssid: 'upstream'),
      throwsA(isA<RepeaterReconnectException>()),
    );
    expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test(
    'default reconnect budget is two 15-second windows, 30 seconds total',
    () {
      final service = RepeaterReconnectService(
        call: (object, method, params) async => null,
      );
      expect(service.timeout, const Duration(seconds: 15));
      expect(service.reconnectWindows, 2);
      expect(
        service.timeout * service.reconnectWindows,
        const Duration(seconds: 30),
      );
    },
  );

  test(
    'verification gets one more window after the first one times out',
    () async {
      var probes = 0;
      final service = RepeaterReconnectService(
        timeout: const Duration(milliseconds: 100),
        settleDelay: Duration.zero,
        pollInterval: Duration.zero,
        call: (object, method, params) async {
          if (object.startsWith('network.interface.')) {
            probes++;
            if (probes == 1) return Completer<dynamic>().future;
            return uplink;
          }
          return association;
        },
      );
      await service.wait(interface: 'wwan', ssid: 'upstream');
      expect(probes, 2);
    },
  );

  test(
    'SSH reload returns acknowledgement before touching the radio',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'repeater-reload-test-',
      );
      try {
        final bin = await Directory('${root.path}/bin').create();
        for (final name in ['wifi', 'network', 'firewall', 'ifup']) {
          final file = await File(
            '${bin.path}/$name',
          ).writeAsString('#!/bin/sh\necho $name >>"\$RELOAD_CALLS"\n');
          await Process.run('chmod', ['755', file.path]);
        }
        final reload = kRepeaterBackgroundReloadCommand
            .replaceAll('/tmp/openwalla', '${root.path}/runtime')
            .replaceAll('/etc/init.d/network', '${bin.path}/network')
            .replaceAll('/etc/init.d/firewall', '${bin.path}/firewall')
            .replaceFirst('sleep 2;', 'sleep 0.3;');
        final calls = File('${root.path}/calls');
        final result = await Process.run(
          'sh',
          ['-c', 'set -e; NET=wwan; SSID=upstream; $reload'],
          environment: {
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'RELOAD_CALLS': calls.path,
          },
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          result.stdout,
          contains('OPENWALLA_REPEATER_CONFIGURED upstream wwan'),
        );
        expect(calls.existsSync(), isFalse);
        for (var i = 0; i < 100; i++) {
          if (calls.existsSync() &&
              (await calls.readAsString()).contains('ifup')) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(await calls.readAsLines(), [
          'wifi',
          'network',
          'firewall',
          'ifup',
        ]);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
