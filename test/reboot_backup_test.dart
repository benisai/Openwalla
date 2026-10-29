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

class _Cache extends RouterSnapshotCache {
  @override
  Future<Map<String, dynamic>?> load(String id, String? fingerprint) async =>
      null;
}

class _Auth implements IAuthService {
  String token = 'token';
  @override
  String get ipAddress => '192.168.1.1';
  @override
  String get sysauth => token;
  @override
  bool get useHttps => false;
  @override
  bool get isAuthenticated => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements IApiService {
  final calls = <String>[];
  dynamic response = [
    0,
    {'code': 0, 'stdout': 'OPENWALLA_STATE_SAVED\n'},
  ];
  Completer<void>? gate;
  Object? error;
  bool rebootResult = true;
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
    expect(params?['command'], '/usr/bin/openwalla-state-sync');
    expect(params?['params'], ['save-for-reboot']);
    expect(receiveTimeout, const Duration(minutes: 5));
    calls.add('backup');
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return response;
  }

  @override
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  }) async {
    calls.add('reboot');
    return rebootResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late AppState state;
  late _Auth auth;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    final routers = RouterService();
    await routers.addRouter(
      Router(
        id: 'router-a',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: '',
        useHttps: false,
      ),
    );
    api = _Api();
    auth = _Auth();
    state = AppState.withServices(
      cache: _Cache(),
      routerService: routers,
      apiService: api,
      authService: auth,
    );
    await state.initialized;
  });
  tearDown(() => state.dispose());

  test(
    'reboot waits for a verified backup before sending the command',
    () async {
      final gate = Completer<void>();
      api.gate = gate;
      final reboot = state.reboot();
      await Future<void>.delayed(Duration.zero);
      expect(api.calls, ['backup']);
      gate.complete();
      expect(await reboot, isTrue);
      expect(api.calls, ['backup', 'reboot']);
      expect(state.rebootError, isNull);
    },
  );

  for (final response in [
    [
      0,
      {'code': 1, 'stderr': 'No space left on device'},
    ],
    [
      6,
      {'code': 0, 'stdout': 'OPENWALLA_STATE_SAVED\n'},
    ],
    [
      0,
      {'code': 0, 'stdout': ''},
    ],
    [
      0,
      {'stdout': 'OPENWALLA_STATE_SAVED\n'},
    ],
  ]) {
    test('unverified backup $response prevents reboot', () async {
      api.response = response;
      expect(await state.reboot(), isFalse);
      expect(api.calls, ['backup']);
      expect(state.isRebooting, isFalse);
      expect(state.rebootError, contains('Reboot cancelled'));
    });
  }

  test('backup transport failure prevents reboot', () async {
    api.error = TimeoutException('Backup response timed out');
    expect(await state.reboot(), isFalse);
    expect(api.calls, ['backup']);
    expect(state.rebootError, contains('timed out'));
  });

  test(
    'a replaced router session cannot reboot after the old backup completes',
    () async {
      final gate = Completer<void>();
      api.gate = gate;
      final pending = state.reboot();
      await Future<void>.delayed(Duration.zero);
      auth.token = 'replacement-session';
      gate.complete();
      expect(await pending, isFalse);
      expect(api.calls, ['backup']);
      expect(state.rebootError, contains('connection changed'));
    },
  );

  test('verified backup in direct RPC map format is accepted', () async {
    api.response = {'code': 0, 'stdout': 'OPENWALLA_STATE_SAVED\n'};
    expect(await state.reboot(), isTrue);
  });

  test('failed reboot command is distinguished from failed backup', () async {
    api.rebootResult = false;
    expect(await state.reboot(), isFalse);
    expect(api.calls, ['backup', 'reboot']);
    expect(state.rebootError, contains('Backup completed'));
  });
}
