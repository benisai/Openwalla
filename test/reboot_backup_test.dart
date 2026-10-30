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
  bool helperPresent = true;
  int checks = 0;
  dynamic checkResponse;
  dynamic legacyResponse = [
    0,
    {'code': 0, 'stdout': ''},
  ];
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
    if (params?['command'] == '/bin/sh') {
      checks++;
      expect(receiveTimeout, const Duration(seconds: 5));
      return checkResponse ??
          [
            0,
            {'code': 0, 'stdout': helperPresent ? 'PRESENT\n' : 'MISSING\n'},
          ];
    }
    expect(params?['command'], '/usr/bin/openwalla-state-sync');
    final action = (params?['params'] as List).single;
    expect(action, anyOf('save-for-reboot', 'save'));
    expect(receiveTimeout, const Duration(minutes: 5));
    calls.add(action == 'save' ? 'legacy-backup' : 'backup');
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return action == 'save' ? legacyResponse : response;
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
    'existing helper with old usage response saves before rebooting',
    () async {
      api.response = [
        0,
        {
          'code': 1,
          'stdout':
              'usage: /usr/bin/openwalla-state-sync {save|backup|restore|status|debug|save-if-due|sync-cron}\n',
        },
      ];
      expect(await state.reboot(), isTrue);
      expect(api.calls, ['backup', 'legacy-backup', 'reboot']);
      expect(state.rebootWarning, contains('Legacy State Sync'));
      expect(state.rebootError, isNull);
    },
  );

  test('legacy helper with usage on stderr also supports reboot', () async {
    api.response = [
      0,
      {
        'code': 1,
        'stderr':
            'usage: /usr/bin/openwalla-state-sync {save|backup|restore|status}',
      },
    ];
    expect(await state.reboot(), isTrue);
    expect(api.calls, ['backup', 'legacy-backup', 'reboot']);
  });

  test('legacy save failure still prevents reboot', () async {
    api.response = [
      0,
      {
        'code': 1,
        'stdout':
            'usage: /usr/bin/openwalla-state-sync {save|backup|restore|status}',
      },
    ];
    api.legacyResponse = [
      0,
      {'code': 1, 'stderr': 'No space left on device'},
    ];
    expect(await state.reboot(), isFalse);
    expect(api.calls, ['backup', 'legacy-backup']);
    expect(state.rebootError, contains('No space left'));
  });

  test('current helper failure never falls back to an unverified save', () async {
    api.response = [
      0,
      {
        'code': 1,
        'stdout':
            'usage: /usr/bin/openwalla-state-sync {save|backup|save-for-reboot|restore}',
        'stderr': 'backup failed',
      },
    ];
    expect(await state.reboot(), isFalse);
    expect(api.calls, ['backup']);
  });

  test(
    'missing State Sync allows normal reboot without calling backup',
    () async {
      api.helperPresent = false;
      expect(await state.reboot(), isTrue);
      expect(api.checks, 1);
      expect(api.calls, ['reboot']);
      expect(state.rebootError, isNull);
      expect(state.rebootWarning, contains('without a runtime data backup'));
    },
  );

  test(
    'availability check failure is not treated as a missing helper',
    () async {
      api.checkResponse = [
        6,
        {'code': 0, 'stdout': 'MISSING\n'},
      ];
      expect(await state.reboot(), isFalse);
      expect(api.calls, isEmpty);
      expect(state.rebootWarning, isNull);
    },
  );

  test('malformed availability response does not bypass backup', () async {
    api.checkResponse = [
      0,
      {'code': 0, 'stdout': ''},
    ];
    expect(await state.reboot(), isFalse);
    expect(api.calls, isEmpty);
  });

  test(
    'failed normal reboot does not claim a skipped backup completed',
    () async {
      api.helperPresent = false;
      api.rebootResult = false;
      expect(await state.reboot(), isFalse);
      expect(state.rebootError, 'The reboot command failed.');
    },
  );

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
