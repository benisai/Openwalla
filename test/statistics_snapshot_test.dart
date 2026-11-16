import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/models/usage_chart_unit.dart';
import 'package:openwalla/services/interfaces/api_service_interface.dart';
import 'package:openwalla/services/interfaces/auth_service_interface.dart';
import 'package:openwalla/services/router_access_guard.dart';
import 'package:openwalla/services/router_service.dart';
import 'package:openwalla/services/router_snapshot_cache.dart';
import 'package:openwalla/state/app_state.dart';

class _Auth implements IAuthService {
  String? token = 'live-token';
  @override
  String? get sysauth => token;
  @override
  bool get isAuthenticated => token != null;
  @override
  Future<void> logout() async {
    token = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements IApiService {
  int calls = 0;
  Map<String, String>? savedSettings;
  bool fail = false;
  bool toolsMissing = false;
  @override
  Future<dynamic> call(
    String ip,
    String auth,
    bool https, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async {
    calls++;
    if (fail) throw StateError('Router unreachable');
    if (object == 'uci') {
      return [
        0,
        {
          'values': {
            'dashboard': {
              'month_start_day': '5',
              'vnstat_interface': 'wan',
              'monthly_limit_gb': '250',
              'usage_chart_unit': 'mb',
            },
          },
        },
      ];
    }
    final command =
        '${params?['command']} ${(params?['params'] as List?)?.join(' ')}';
    String output = '';
    if (command.contains('command -v vnstat')) {
      if (toolsMissing) {
        return [
          0,
          {'code': 1, 'stdout': ''},
        ];
      }
      output = 'OK';
    } else if (command.contains('nlbw -c csv -g mac')) {
      output = 'aa:bb:cc:dd:ee:ff|1024|512';
    } else if (command.contains('nlbw -c csv')) {
      output = 'https|2048|256';
    } else if (command.contains('SELECT mac, ip, hostname')) {
      output = 'aa:bb:cc:dd:ee:ff|192.168.1.20|Phone';
    } else if ('${params?['command']}'.contains('vnstat')) {
      output = jsonEncode({
        'jsonversion': '2',
        'vnstatversion': '2.13',
        'interfaces': [
          {
            'name': 'wan',
            'traffic': {
              'hour': [
                {
                  'date': {'year': 2026, 'month': 11, 'day': 14},
                  'time': {'hour': 10, 'minute': 0},
                  'rx': 4096,
                  'tx': 1024,
                },
              ],
            },
          },
        ],
      });
    }
    return [
      0,
      {'code': 0, 'stdout': output},
    ];
  }

  @override
  Future<dynamic> uciSet(
    String ip,
    String auth,
    bool https, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    savedSettings = values;
    return [0];
  }

  @override
  Future<dynamic> uciCommit(
    String ip,
    String auth,
    bool https, {
    required String config,
    BuildContext? context,
  }) async => [0];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late RouterSnapshotCache cache;
  late RouterService routers;
  late AppState state;
  late _Api api;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    RouterAccessGuard.offline = false;
    root = await Directory.systemTemp.createTemp('statistics-snapshot-');
    cache = RouterSnapshotCache(directory: () async => root);
    routers = RouterService();
    await routers.addRouter(
      Router(
        id: 'router-a',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: '',
        useHttps: false,
        fingerprint: 'serial:a',
      ),
    );
    await cache.save('router-a', 'serial:a', 'dashboard', {
      'boardInfo': {'hostname': 'Router A'},
      'sysInfo': {'uptime': 100},
      'interfaceDump': {'interface': []},
    });
    api = _Api();
    state = AppState.withServices(
      cache: cache,
      routerService: routers,
      apiService: api,
      authService: _Auth(),
    );
    await state.initialized;
  });
  tearDown(() async {
    state.dispose();
    RouterAccessGuard.offline = false;
    await root.delete(recursive: true);
  });

  Future<void> populate() async {
    expect(await state.hasStatisticsSupport(), isTrue);
    expect((await state.fetchMonthlyUsageSettings()).interfaceName, 'wan');
    expect((await state.fetchNlbwTopDevices()).single.label, 'Phone');
    expect((await state.fetchNlbwProtocolUsage()).single.protocol, 'https');
    expect(
      (await state.fetchVnstatUsageSamples(
        period: 'hourly',
        interfaceName: 'wan',
      )).single.downloadBytes,
      4096,
    );
    await cache.waitForPendingWrites('router-a');
  }

  test(
    'live Statistics survives offline login without router requests',
    () async {
      await populate();
      expect(await state.openOfflineSnapshot(), isTrue);
      api.calls = 0;
      expect(await state.hasStatisticsSupport(), isTrue);
      final settings = await state.fetchMonthlyUsageSettings();
      expect(settings.monthStartDay, 5);
      expect(settings.monthlyLimitGb, 250);
      expect(settings.interfaceName, 'wan');
      expect(settings.chartUnit, UsageChartUnit.mb);
      final device = (await state.fetchNlbwTopDevices()).single;
      expect(device.label, 'Phone');
      expect(device.totalBytes, 1536);
      final protocol = (await state.fetchNlbwProtocolUsage()).single;
      expect(protocol.protocol, 'https');
      expect(protocol.totalBytes, 2304);
      expect(
        (await state.fetchVnstatUsageSamples(
          period: 'hourly',
          interfaceName: 'wan',
        )).single.downloadBytes,
        4096,
      );
      expect(api.calls, 0);
    },
  );
  test('saving units writes UCI and retains the choice offline', () async {
    await state.saveMonthlyUsageSettings(
      const MonthlyUsageSettings(
        monthStartDay: 5,
        interfaceName: 'wan',
        monthlyLimitGb: 250,
        chartUnit: UsageChartUnit.tb,
      ),
    );
    expect(api.savedSettings?['usage_chart_unit'], 'tb');
    expect(api.savedSettings?['monthly_limit_gb'], '250');
    await cache.waitForPendingWrites('router-a');
    expect(await state.openOfflineSnapshot(), isTrue);
    expect(
      (await state.fetchMonthlyUsageSettings()).chartUnit,
      UsageChartUnit.tb,
    );
  });
  test(
    'connection failures preserve the last successful Statistics snapshots',
    () async {
      await populate();
      api.fail = true;
      expect(await state.hasStatisticsSupport(), isTrue);
      expect((await state.fetchMonthlyUsageSettings()).monthlyLimitGb, 250);
      expect((await state.fetchNlbwTopDevices()).single.label, 'Phone');
      expect((await state.fetchNlbwProtocolUsage()).single.protocol, 'https');
    },
  );
  test('confirmed missing tools still fail the live install check', () async {
    await populate();
    api.toolsMissing = true;
    expect(await state.hasStatisticsSupport(), isFalse);
  });
  test(
    'router profiles sharing an address never share saved Statistics',
    () async {
      await populate();
      await routers.addRouter(
        Router(
          id: 'router-b',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: '',
          useHttps: false,
          fingerprint: 'serial:b',
        ),
      );
      await cache.save('router-b', 'serial:b', 'dashboard', {
        'boardInfo': {'hostname': 'Router B'},
        'interfaceDump': {'interface': []},
      });
      await state.selectSavedRouterForLogin('router-b');
      expect(await state.openOfflineSnapshot(), isTrue);
      api.calls = 0;
      expect(await state.hasStatisticsSupport(), isFalse);
      expect(await state.fetchNlbwTopDevices(), isEmpty);
      expect(await state.fetchNlbwProtocolUsage(), isEmpty);
      expect((await state.fetchMonthlyUsageSettings()).monthlyLimitGb, 100);
      expect(
        await state.fetchVnstatUsageSamples(
          period: 'hourly',
          interfaceName: 'wan',
        ),
        isEmpty,
      );
      expect(api.calls, 0);
    },
  );
}
