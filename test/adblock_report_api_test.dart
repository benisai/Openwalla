import 'package:flutter/material.dart' hide Router;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/models/adblock_report.dart';
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
  dynamic readResult = [
    0,
    {
      'data':
          '{"generated_at":1,"data":[{"total":"5","blocked":"1","requests":[]}]}',
    },
  ];
  bool ready = true;
  bool rejectSet = false;
  bool failService = false;
  bool failFeed = false;
  final calls = <String>[];
  final writes = <Map<String, String>>[];
  final commands = <String>[];
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
    calls.add('$object.$method');
    if (object == 'file') {
      if (method == 'exec') {
        expect(params?['command'], '/bin/sh');
        return execute((params?['params'] as List).last as String);
      }
      expect(method, 'read');
      expect(params, {'path': adblockReportPath});
      return readResult;
    }
    return [0];
  }

  dynamic execute(String command) {
    commands.add(command);
    if ((failService && command.startsWith('/etc/init.d/adblock')) ||
        (failFeed && command.startsWith('set -e'))) {
      return [
        0,
        {'code': 1, 'stderr': 'Failed'},
      ];
    }
    return [
      0,
      {'code': 0, 'stdout': ready ? 'OPENWALLA_REPORT_READY' : ''},
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
    writes.add(values);
    return [rejectSet ? 1 : 0];
  }

  @override
  Future<dynamic> uciCommit(
    String ip,
    String auth,
    bool https, {
    required String config,
    BuildContext? context,
  }) async {
    calls.add('uci.commit');
    return [0];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState state;
  late _Api api;
  const settings = OpenwrtAdblockSettings(
    section: 'global',
    installed: true,
    enabled: true,
    safeSearch: false,
    reportEnabled: true,
    triggerInterface: 'wan',
    dnsBackend: 'dnsmasq',
    selectedFeeds: ['adguard'],
    serviceStatus: 'enabled',
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

  test('reads only cached JSON, never invokes report generation', () async {
    expect((await state.fetchAdblockReport())!.total, 5);
    expect(api.calls, ['file.read']);
    expect(api.commands, isEmpty);
  });
  test(
    'missing cache returns no report; denied or corrupt cache throws',
    () async {
      api.readResult = [4];
      expect(await state.fetchAdblockReport(), isNull);
      api.readResult = [6];
      await expectLater(state.fetchAdblockReport(), throwsStateError);
      api.readResult = [
        0,
        {'data': 'bad json'},
      ];
      await expectLater(state.fetchAdblockReport(), throwsFormatException);
    },
  );
  test('missing capture or runner dependency prevents enabling', () async {
    api.ready = false;
    await expectLater(
      state.setAdblockReportsEnabled(settings),
      throwsStateError,
    );
    expect(api.writes, isEmpty);
  });
  test(
    'enabling configures bounded capture without reverse lookup or maps',
    () async {
      await state.setAdblockReportsEnabled(settings);
      expect(
        api.writes.first['adb_reportdir'],
        '/tmp/openwalla/adblock-report',
      );
      expect(api.writes.first['adb_repchunkcnt'], '5');
      expect(api.commands.first, contains('Openwalla-1min-run.sh'));
      expect(api.commands.first, contains('OPENWALLA_1MIN_RUN'));
      expect(api.writes.first['adb_repchunksize'], '1');
      expect(api.writes.first['adb_represolve'], '0');
      expect(api.writes.first['adb_map'], '0');
      expect(api.writes.last['adb_report'], '1');
      expect(api.writes.last['adb_enabled'], '1');
      expect(api.calls, contains('uci.commit'));
      expect(api.commands.last, contains('adblock reload'));
    },
  );
  test(
    'disabling works without capture dependency and preserves ad blocking',
    () async {
      api.ready = false;
      await state.setAdblockReportsEnabled(
        settings.copyWith(reportEnabled: false),
      );
      expect(api.writes.single['adb_report'], '0');
      expect(api.writes.single['adb_enabled'], '1');
      expect(api.commands, isNot(contains(contains('OPENWALLA_REPORT_READY'))));
    },
  );
  test(
    'router rejecting report config is an error, not false success',
    () async {
      api.rejectSet = true;
      await expectLater(
        state.setAdblockReportsEnabled(settings),
        throwsStateError,
      );
      expect(api.calls, isNot(contains('uci.commit')));
    },
  );
  test(
    'feed command failure aborts before commit or service restart',
    () async {
      api.failFeed = true;
      await expectLater(state.saveAdblockSettings(settings), throwsStateError);
      expect(api.calls, isNot(contains('uci.commit')));
    },
  );
  test('nonzero service result does not report success', () async {
    api.failService = true;
    await expectLater(state.saveAdblockSettings(settings), throwsStateError);
  });
}
