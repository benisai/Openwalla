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
  @override
  String get sysauth => 'token';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements IApiService {
  final actions = <String>[];
  Map<String, String>? values;
  String? script;
  dynamic setResult = [0];
  dynamic commitResult = [0];
  dynamic applyResult = [
    0,
    {'code': 0, 'stdout': 'OPENWALLA_SQM_APPLIED\n'},
  ];

  @override
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  }) async {
    actions.add('set');
    this.values = values;
    return setResult;
  }

  @override
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    actions.add('commit');
    return commitResult;
  }

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
    expect(object, 'file');
    expect(method, 'exec');
    expect(params?['command'], '/bin/sh');
    actions.add('apply');
    script = (params!['params'] as List).last as String;
    return applyResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late _Api api;
  OpenwrtSqmQueue queue(bool enabled) => OpenwrtSqmQueue(
    section: 'queue',
    enabled: enabled,
    interfaceName: 'phy0-sta0',
    downloadKbps: 85000,
    uploadKbps: 10000,
    qdisc: 'cake',
    script: 'piece_of_cake.qos',
    debugLogging: false,
    verbosity: '5',
  );
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
    state = AppState.withServices(
      cache: _Cache(),
      routerService: routers,
      apiService: api,
      authService: _Auth(),
    );
    await state.initialized;
  });
  tearDown(() => state.dispose());

  test(
    'enable commits settings and enables/restarts SQM with confirmation',
    () async {
      await state.saveSqmQueue(queue(true));
      expect(api.actions, ['set', 'commit', 'apply']);
      expect(api.values?['enabled'], '1');
      expect(api.values?['interface'], 'phy0-sta0');
      expect(
        api.script,
        contains('/etc/init.d/sqm enable && /etc/init.d/sqm restart'),
      );
      expect(api.script, isNot(contains('|| true')));
    },
  );
  test(
    'disable only disables this queue without disabling the whole service',
    () async {
      await state.saveSqmQueue(queue(false));
      expect(api.values?['enabled'], '0');
      expect(api.script, isNot(contains('/etc/init.d/sqm disable')));
      expect(api.script, contains('/etc/init.d/sqm restart'));
    },
  );
  test('rejected UCI write never commits or restarts', () async {
    api.setResult = [6];
    await expectLater(state.saveSqmQueue(queue(true)), throwsStateError);
    expect(api.actions, ['set']);
  });
  test('commit failure never restarts', () async {
    api.commitResult = [6];
    await expectLater(state.saveSqmQueue(queue(true)), throwsStateError);
    expect(api.actions, ['set', 'commit']);
  });
  test(
    'restart failure or missing confirmation cannot report success',
    () async {
      for (final response in [
        [
          0,
          {'code': 1, 'stderr': 'restart failed'},
        ],
        [
          0,
          {'code': 0, 'stdout': ''},
        ],
        [6],
      ]) {
        api.applyResult = response;
        await expectLater(state.saveSqmQueue(queue(true)), throwsStateError);
      }
    },
  );
}
