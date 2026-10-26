import 'dart:io';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/client.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/screens/login_screen.dart';
import 'package:openwalla/services/api_service.dart';
import 'package:openwalla/services/interfaces/api_service_interface.dart';
import 'package:openwalla/services/interfaces/auth_service_interface.dart';
import 'package:openwalla/services/router_access_guard.dart';
import 'package:openwalla/services/router_service.dart';
import 'package:openwalla/services/router_snapshot_cache.dart';
import 'package:openwalla/services/ssh_service.dart';
import 'package:openwalla/state/app_state.dart';
import 'package:openwalla/widgets/offline_snapshot_banner.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _Auth implements IAuthService {
  String? token;
  @override
  String? get sysauth => token;
  @override
  bool get isAuthenticated => token != null;
  @override
  bool get useHttps => false;
  @override
  String? get ipAddress => '192.168.1.1';
  @override
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
    bool saveCredentials = true,
  }) async {
    token = null;
  }

  @override
  Future<void> logout() async {
    token = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements IApiService {
  int calls = 0;
  Object? response;
  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async {
    calls++;
    if (response != null) return response;
    throw StateError('Router unreachable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late RouterSnapshotCache cache;
  late RouterService routers;
  late AppState state;
  late _Auth auth;
  late _Api api;
  var providerOwnsState = false;

  setUp(() async {
    providerOwnsState = false;
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Openwalla',
      packageName: 'test.openwalla',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    RouterAccessGuard.offline = false;
    directory = await Directory.systemTemp.createTemp('openwalla-offline-');
    cache = RouterSnapshotCache(directory: () async => directory);
    routers = RouterService();
    await routers.addRouter(
      Router(
        id: 'uuid-a',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'saved-password',
        useHttps: false,
        fingerprint: 'serial:a',
      ),
    );
    await cache.save('uuid-a', 'serial:a', 'dashboard', {
      'boardInfo': {'hostname': 'Router A'},
      'sysInfo': {'uptime': 100},
      'interfaceDump': {
        'interface': [
          {'interface': 'lan', 'up': true},
        ],
      },
      'wireless': {
        'radio0': {'up': true},
      },
      'uciWirelessConfig': {
        'values': {
          'default_radio0': {
            '.type': 'wifi-iface',
            'ssid': 'Home',
            'encryption': 'psk2',
            'key': 'secret',
          },
        },
      },
      'flowProvider': 'netify',
      'netifyFlowCount': 3,
      'pingSamples': ['2026-10-25T12:00:00Z|1.1.1.1|OK|22|reply'],
    });
    await cache.save('uuid-a', 'serial:a', 'devices', [
      RouterSnapshotCache.encodeClient(
        Client(
          ipAddress: '192.168.1.4',
          macAddress: 'AA:BB:CC:DD:EE:FF',
          hostname: 'Phone',
        ),
      ),
    ]);
    await cache.save(
      'uuid-a',
      'serial:a',
      'ping-samples:$kOpenwallaPingTimelineSampleLimit',
      '2026-10-25T12:00:00Z|1.1.1.1|OK|22|reply',
    );
    await cache.save(
      'uuid-a',
      'serial:a',
      'speedtest-samples:30',
      '2026-10-25T12:00:00Z|OK|100|20|Server|done',
    );
    await cache.save('uuid-a', 'serial:a', 'performance-settings', {
      'target': '1.1.1.1',
      'thresholdMs': 200,
    });
    auth = _Auth();
    api = _Api();
    state = AppState.withServices(
      cache: cache,
      routerService: routers,
      apiService: api,
      authService: auth,
    );
    await state.initialized;
  });
  tearDown(() async {
    if (!providerOwnsState) state.dispose();
    RouterAccessGuard.offline = false;
    await directory.delete(recursive: true);
  });

  test(
    'opens saved dashboard, network, Wi-Fi and devices without authenticating',
    () async {
      expect(state.hasOfflineSnapshot, isTrue);
      expect(await state.openOfflineSnapshot(), isTrue);
      expect(state.offlineViewing, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(state.dashboardData!['boardInfo'], isA<Map<String, dynamic>>());
      expect(
        state.dashboardData!['flowProvider'],
        OpenwallaFlowProvider.netify,
      );
      expect(
        (state.dashboardData!['pingSamples'] as List<PingMonitorSample>)
            .single
            .latencyMs,
        22,
      );
      expect(
        state.dashboardData!['uciWirelessConfig']['values']['default_radio0']
            .containsKey('key'),
        isFalse,
      );
      expect(
        (await state.fetchClientsForSelectedRouter()).single.hostname,
        'Phone',
      );
      await state.fetchDashboardData();
      expect(api.calls, 0);
    },
  );

  test(
    'network performance restores history and threshold without network calls',
    () async {
      await state.openOfflineSnapshot();
      expect((await state.fetchPingMonitorSamples()).single.latencyMs, 22);
      expect(
        (await state.fetchSpeedtestMonitorSamples()).single.downloadMbps,
        100,
      );
      expect((await state.fetchNetworkMonitorSettings()).thresholdMs, 200);
      expect(await state.hasNetworkPerformanceSupport(), isTrue);
      expect(api.calls, 0);
    },
  );

  test(
    'live reads update snapshots, failed reads preserve the last good value',
    () async {
      auth.token = 'live-token';
      api.response = [
        0,
        {'code': 0, 'stdout': '2026-10-25T13:00:00Z|1.1.1.1|OK|30|reply'},
      ];
      expect((await state.fetchPingMonitorSamples()).single.latencyMs, 30);
      api.response = [
        0,
        {'code': 1, 'stderr': 'permission denied'},
      ];
      expect((await state.fetchPingMonitorSamples()).single.latencyMs, 30);
      expect(state.showingSavedData, isTrue);
      final saved = await state.readSnapshotSection(
        'ping-samples:$kOpenwallaPingTimelineSampleLimit',
      );
      expect(saved, contains('|30|'));
      api.response = [
        0,
        {'code': 0, 'stdout': '2026-10-25T14:00:00Z|1.1.1.1|OK|40|reply'},
      ];
      expect((await state.fetchPingMonitorSamples()).single.latencyMs, 40);
      expect(state.showingSavedData, isFalse);
    },
  );

  test('offline reconnect failure preserves saved dashboard', () async {
    await state.openOfflineSnapshot();
    await state.retryDashboardConnection();
    expect(state.offlineViewing, isTrue);
    expect(state.dashboardData!['boardInfo']['hostname'], 'Router A');
    expect(auth.isAuthenticated, isFalse);
  });

  test(
    'different fingerprint cannot open the previous router snapshot',
    () async {
      await routers.updateRouter(
        routers.selectedRouter!.copyWith(fingerprint: 'serial:different'),
      );
      expect(await state.openOfflineSnapshot(), isFalse);
    },
  );

  test('profile deletion also deletes the snapshot', () async {
    await state.openOfflineSnapshot();
    await state.removeSavedRouterProfile('uuid-a');
    expect(await cache.load('uuid-a', 'serial:a'), isNull);
    expect(state.offlineViewing, isFalse);
    expect(RouterAccessGuard.offline, isFalse);
  });

  test(
    'login profile selection opens only that router snapshot at the same IP',
    () async {
      await routers.addRouter(
        Router(
          id: 'uuid-b',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'other-password',
          useHttps: false,
          fingerprint: 'serial:b',
        ),
      );
      await cache.save('uuid-b', 'serial:b', 'dashboard', {
        'boardInfo': {'hostname': 'Router B'},
        'flowProvider': 'none',
        'pingSamples': [],
      });
      await state.selectSavedRouterForLogin('uuid-b');
      expect(state.hasOfflineSnapshot, isTrue);
      expect(await state.openOfflineSnapshot(), isTrue);
      expect(state.dashboardData!['boardInfo']['hostname'], 'Router B');
      expect(await state.fetchClientsForSelectedRouter(), isEmpty);
      expect(api.calls, 0);
    },
  );

  test(
    'offline guard rejects RPC and SSH commands before any connection',
    () async {
      await state.openOfflineSnapshot();
      await expectLater(
        RealApiService().call(
          '192.168.1.1',
          'stale',
          false,
          object: 'uci',
          method: 'set',
        ),
        throwsStateError,
      );
      await expectLater(
        RealApiService().call(
          '192.168.1.1',
          'stale',
          false,
          object: 'file',
          method: 'exec',
        ),
        throwsStateError,
      );
      await expectLater(
        SshService().runCommand(
          host: '192.168.1.1',
          username: 'root',
          password: '',
          command: 'reboot',
        ),
        throwsStateError,
      );
      await expectLater(
        SshService().connectShell(
          host: '192.168.1.1',
          username: 'root',
          password: '',
        ),
        throwsStateError,
      );
    },
  );

  testWidgets('failed login offers Offline beside Connect', (tester) async {
    providerOwnsState = true;
    tester.view.physicalSize = const Size(360, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: LoginScreen(), routes: {}),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    final connect = tester.getCenter(find.text('Connect'));
    final offline = tester.getCenter(find.text('Offline'));
    expect((connect.dy - offline.dy).abs(), lessThan(5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('offline banner fits mobile and desktop and offers reconnect', (
    tester,
  ) async {
    var reconnects = 0;
    for (final width in [320.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineSnapshotBanner(
              savedAt: DateTime(2026, 10, 25, 12),
              reconnecting: false,
              onReconnect: () => reconnects++,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Reconnect to router'));
    }
    expect(reconnects, 2);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
