import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/services/interfaces/api_service_interface.dart';
import 'package:openwalla/services/interfaces/auth_service_interface.dart';
import 'package:openwalla/services/router_service.dart';
import 'package:openwalla/services/router_snapshot_cache.dart';
import 'package:openwalla/services/router_access_guard.dart';
import 'package:openwalla/state/app_state.dart';

class _SlowCache extends RouterSnapshotCache {
  final gate = Completer<void>();
  final started = <String>[];
  final saved = <String, Object?>{};
  final writes = <Future<void>>[];
  bool fail = false;

  @override
  Future<Map<String, dynamic>?> load(String id, String? fingerprint) async =>
      null;

  @override
  Future<void> save(
    String id,
    String? fingerprint,
    String section,
    Object? value,
  ) {
    started.add('$id:$section');
    final write = gate.future.then((_) {
      if (fail) throw StateError('Disk unavailable');
      saved['$id:$section'] = RouterSnapshotCache.sanitize(value);
    });
    writes.add(write.catchError((Object _) {}));
    return write;
  }
}

class _Auth implements IAuthService {
  bool authenticated = true;
  @override
  bool get useHttps => false;
  @override
  String? get sysauth => authenticated ? 'token' : null;
  @override
  bool get isAuthenticated => authenticated;
  @override
  Future<void> logout() async {
    authenticated = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements IApiService {
  final commands = <String>[];
  Object? infoFailure;
  bool probeFails = false;
  int probes = 0;
  int boardReads = 0;
  Completer<void>? boardGate;
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
    if (object == 'system' && method == 'board') {
      if (receiveTimeout == const Duration(seconds: 3)) {
        probes++;
        if (probeFails) throw const SocketException('Network unreachable');
      } else {
        boardReads++;
        if (boardGate != null) await boardGate!.future;
      }
    }
    if (object == 'system' && method == 'info' && infoFailure != null) {
      throw infoFailure!;
    }
    if (object == 'uci') {
      return {
        'values': {
          'ping_monitor': {'target': '1.1.1.1', 'threshold': '200'},
        },
      };
    }
    if (object == 'network.interface') return {'interface': <dynamic>[]};
    if (object == 'file') {
      if (method == 'read') return {'data': '0'};
      final command = (params?['params'] as List?)?.last.toString() ?? '';
      commands.add(command);
      return {
        'code': 0,
        'stdout': command.contains('tail -n')
            ? '2026-10-27T12:00:00Z|1.1.1.1|OK|22|reply'
            : '',
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late _SlowCache cache;
  late RouterService routers;
  late _Api api;
  setUp(() async {
    RouterAccessGuard.offline = false;
    FlutterSecureStorage.setMockInitialValues({});
    routers = RouterService();
    await routers.addRouter(
      Router(
        id: 'router-a',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: '',
        useHttps: false,
      ),
    );
    cache = _SlowCache();
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
    if (!cache.gate.isCompleted) cache.gate.complete();
    await Future.wait(cache.writes);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    state.dispose();
    RouterAccessGuard.offline = false;
  });

  test(
    'non-network dashboard errors never enable global offline guard',
    () async {
      cache.gate.complete();
      await state.fetchDashboardData();
      api.infoFailure = const FormatException('Unexpected optional data');
      await state.fetchDashboardData();
      expect(state.showingSavedData, isTrue);
      expect(state.offlineViewing, isFalse);
      expect(state.routerConnectionLost, isFalse);
      expect(RouterAccessGuard.offline, isFalse);
      expect(api.probes, 0);
    },
  );

  test(
    'one network failure with a healthy probe stays live and can refresh',
    () async {
      cache.gate.complete();
      await state.fetchDashboardData();
      api.infoFailure = const SocketException('Temporary disconnect');
      await state.fetchDashboardData();
      expect(api.probes, 1);
      expect(state.routerConnectionLost, isFalse);
      expect(RouterAccessGuard.offline, isFalse);
      api.infoFailure = null;
      await state.fetchDashboardData();
      expect(state.showingSavedData, isFalse);
    },
  );

  test(
    'confirmed connection loss recovers automatically without entering explicit offline mode',
    () async {
      cache.gate.complete();
      await state.fetchDashboardData();
      api.infoFailure = const SocketException('Disconnected');
      api.probeFails = true;
      await state.fetchDashboardData();
      expect(state.offlineViewing, isFalse);
      expect(state.routerConnectionLost, isTrue);
      expect(RouterAccessGuard.offline, isTrue);
      api.infoFailure = null;
      api.probeFails = false;
      await Future<void>.delayed(const Duration(seconds: 11));
      expect(api.probes, greaterThanOrEqualTo(2));
      expect(state.routerConnectionLost, isFalse);
      expect(state.showingSavedData, isFalse);
      expect(RouterAccessGuard.offline, isFalse);
    },
  );

  test('overlapping dashboard refreshes share a single request', () async {
    cache.gate.complete();
    final gate = Completer<void>();
    api.boardGate = gate;
    final first = state.fetchDashboardData();
    final second = state.fetchDashboardData();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(api.boardReads, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(state.dashboardData, isNotNull);
  });

  test(
    'normal refresh can recover confirmed loss without a new login',
    () async {
      cache.gate.complete();
      await state.fetchDashboardData();
      api.infoFailure = const SocketException('Disconnected');
      api.probeFails = true;
      await state.fetchDashboardData();
      expect(RouterAccessGuard.offline, isTrue);
      api.infoFailure = null;
      api.probeFails = false;
      await state.fetchDashboardData();
      expect(RouterAccessGuard.offline, isFalse);
      expect(state.showingSavedData, isFalse);
    },
  );

  test(
    'a late failed refresh cannot switch the app offline after logout',
    () async {
      cache.gate.complete();
      await state.fetchDashboardData();
      final gate = Completer<void>();
      api.boardGate = gate;
      api.infoFailure = const SocketException('Disconnected');
      final pending = state.fetchDashboardData();
      await Future<void>.delayed(Duration.zero);
      await state.logout();
      gate.complete();
      await pending;
      expect(state.dashboardData, isNull);
      expect(state.offlineViewing, isFalse);
      expect(state.routerConnectionLost, isFalse);
      expect(RouterAccessGuard.offline, isFalse);
    },
  );

  test(
    'ping and settings return live values while disk saves are blocked',
    () async {
      final ping = await state.fetchPingMonitorSamples().timeout(
        const Duration(seconds: 2),
      );
      final settings = await state.fetchNetworkMonitorSettings().timeout(
        const Duration(seconds: 2),
      );
      expect(ping.single.latencyMs, 22);
      expect(settings.thresholdMs, 200);
      expect(cache.started, contains('router-a:performance-settings'));
      expect(cache.gate.isCompleted, isFalse);
      expect(cache.saved, isEmpty);
      cache.gate.complete();
      await Future.wait(cache.writes);
      expect(cache.saved.keys, contains('router-a:performance-settings'));
    },
  );

  test('warmup shares page reads without marking notifications seen', () async {
    cache.gate.complete();
    state.warmDeviceAndNotificationPages();
    await Future.wait([state.loadDevicesPage(), state.loadNotificationsPage()]);
    expect(state.devicesPageData(), isNotNull);
    expect(state.notificationsPageData, isNotNull);
    expect(
      api.commands.where(
        (command) => command.contains('FROM notifications WHERE'),
      ),
      hasLength(1),
    );
    expect(
      api.commands.any(
        (command) => command.contains('UPDATE notifications SET'),
      ),
      isFalse,
    );
    final count = api.commands.length;
    await state.loadNotificationsPage();
    await state.loadDevicesPage();
    expect(api.commands, hasLength(count));
    state.invalidateNotificationsPageData();
    expect(state.notificationsPageData, isNull);
    await state.loadNotificationsPage();
    expect(api.commands.length, greaterThan(count));
  });

  test('dashboard completion does not wait for snapshot persistence', () async {
    await state.fetchDashboardData().timeout(const Duration(seconds: 2));
    expect(state.dashboardData, isNotNull);
    expect(state.isDashboardLoading, isFalse);
    expect(cache.started, contains('router-a:dashboard'));
    expect(cache.saved, isEmpty);
    cache.gate.complete();
    await Future.wait(cache.writes);
    expect(cache.saved['router-a:dashboard'], isA<Map>());
  });

  test(
    'queued data stays attached to the router captured at fetch time',
    () async {
      await state.fetchDashboardData().timeout(const Duration(seconds: 2));
      await routers.addRouter(
        Router(
          id: 'router-b',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: '',
          useHttps: false,
        ),
      );
      await routers.setSelectedRouter('router-b');
      cache.gate.complete();
      await Future.wait(cache.writes);
      expect(cache.saved, contains('router-a:dashboard'));
      expect(
        cache.saved.keys.any((key) => key.startsWith('router-b:')),
        isFalse,
      );
    },
  );

  test(
    'background save failure does not replace live data with an error',
    () async {
      cache.fail = true;
      await state.fetchDashboardData().timeout(const Duration(seconds: 2));
      cache.gate.complete();
      await Future.wait(cache.writes);
      expect(state.dashboardData, isNotNull);
      expect(state.showingSavedData, isFalse);
      expect(state.dashboardError, isNull);
    },
  );
}
