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
  Map<String, String>? values;
  final actions = <String>[];
  bool rejectSet = false;
  bool rejectCommit = false;
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
    this.values = values;
    actions.add('set');
    return [rejectSet ? 1 : 0];
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
    return [rejectCommit ? 1 : 0];
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
    actions.add(method);
    return method == 'add'
        ? [
            0,
            {'section': 'new-forward'},
          ]
        : [0];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late _Api api;
  const forward = OpenwrtPortForward(
    section: 'old',
    name: 'Old',
    source: 'wan',
    wanPort: '8000-8010',
    protocol: 'tcp udp',
    destinationZone: 'lan',
    destinationIp: '192.168.1.10',
    destinationPort: '9000-9010',
    enabled: false,
  );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    final routers = RouterService();
    await routers.addRouter(
      Router(
        id: 'test',
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

  for (final enabled in [true, false]) {
    test(
      'immediate toggle writes only flags ($enabled) then commits/applies',
      () async {
        await state.setPortForwardEnabled(forward, enabled);
        expect(api.values, {'enabled': enabled ? '1' : '0', 'disabled': '0'});
        expect(api.actions, ['set', 'commit', 'apply']);
      },
    );
  }
  test('rejected toggle does not commit or apply', () async {
    api.rejectSet = true;
    await expectLater(
      state.setPortForwardEnabled(forward, true),
      throwsStateError,
    );
    expect(api.actions, ['set']);
  });
  test('failed toggle commit does not apply', () async {
    api.rejectCommit = true;
    await expectLater(
      state.setPortForwardEnabled(forward, true),
      throwsStateError,
    );
    expect(api.actions, ['set', 'commit']);
  });

  test(
    'new disabled rule persists the flag and port ranges, then commits/applies',
    () async {
      await state.addPortForward(
        name: 'New',
        sourceZone: 'wan',
        externalPort: '8000-8010',
        protocol: 'tcp udp',
        destinationZone: 'lan',
        destinationIp: '192.168.1.10',
        internalPort: '9000-9010',
        enabled: false,
      );
      expect(api.values?['enabled'], '0');
      expect(api.values?['src_dport'], '8000-8010');
      expect(api.values?['dest_port'], '9000-9010');
      expect(api.actions, ['add', 'set', 'commit', 'apply']);
    },
  );
  test(
    'enabling a legacy disabled redirect clears disabled and sets enabled',
    () async {
      await state.updatePortForward(
        forward,
        name: 'Edited',
        sourceZone: 'wan',
        externalPort: '8000-8010',
        protocol: 'tcp udp',
        destinationZone: 'lan',
        destinationIp: '192.168.1.10',
        internalPort: '9000-9010',
        enabled: true,
      );
      expect(api.values?['enabled'], '1');
      expect(api.values?['disabled'], '0');
      expect(api.actions, ['set', 'commit', 'apply']);
    },
  );
  test(
    'omitting optional enabled flag preserves existing redirect state',
    () async {
      await state.updatePortForward(
        forward,
        name: 'Edited',
        sourceZone: 'wan',
        externalPort: '8000-8010',
        protocol: 'tcp udp',
        destinationZone: 'lan',
        destinationIp: '192.168.1.10',
        internalPort: '9000-9010',
      );
      expect(api.values!.containsKey('enabled'), isFalse);
      expect(api.values!.containsKey('disabled'), isFalse);
    },
  );
}
