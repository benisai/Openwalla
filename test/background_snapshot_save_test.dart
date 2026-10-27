import 'dart:async';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/services/interfaces/api_service_interface.dart';
import 'package:openwalla/services/interfaces/auth_service_interface.dart';
import 'package:openwalla/services/router_service.dart';
import 'package:openwalla/services/router_snapshot_cache.dart';
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
  @override
  String get sysauth => 'token';
  @override
  bool get isAuthenticated => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements IApiService {
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
  setUp(() async {
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
    state = AppState.withServices(
      cache: cache,
      routerService: routers,
      apiService: _Api(),
      authService: _Auth(),
    );
    await state.initialized;
  });
  tearDown(() async {
    if (!cache.gate.isCompleted) cache.gate.complete();
    await Future.wait(cache.writes);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    state.dispose();
  });

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
