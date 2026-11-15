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
  dynamic readResult = [
    0,
    {'code': 0, 'stdout': 'S|5|5|0|0|0'},
  ];
  final helperArgs = <List>[];
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
      expect(method, 'exec');
      if (params?['command'] == '/usr/bin/openwalla-adblock-reports') {
        final args = params?['params'] as List;
        helperArgs.add(args);
        if (args.first == 'query') return readResult;
        return [
          0,
          {'code': ready ? 0 : 1},
        ];
      }
      expect(params?['command'], '/bin/sh');
      return execute((params?['params'] as List).last as String);
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

  test(
    'queries SQLite with argv search and cursor, never report generation',
    () async {
      expect(
        (await state.fetchAdblockReport(
          search: "`test`'; drop",
          beforeId: 12,
        ))!.total,
        5,
      );
      expect(api.helperArgs.single, [
        'query',
        '--search',
        "`test`'; drop",
        '--before',
        '12',
        '--limit',
        '201',
      ]);
      expect(api.calls, ['file.exec']);
      expect(api.commands, isEmpty);
    },
  );
  test('missing helper, denied or corrupt result is an error', () async {
    for (final result in [
      [4],
      [6],
      [
        0,
        {'code': 1, 'stderr': 'missing'},
      ],
    ]) {
      api.readResult = result;
      await expectLater(state.fetchAdblockReport(), throwsStateError);
    }
    api.readResult = [
      0,
      {'code': 0, 'stdout': 'broken'},
    ];
    await expectLater(state.fetchAdblockReport(), throwsFormatException);
  });
  test('missing collector prevents enabling before changing AdBlock', () async {
    api.ready = false;
    await expectLater(
      state.setAdblockReportsEnabled(settings),
      throwsStateError,
    );
    expect(api.writes, isEmpty);
  });
  test(
    'enabling uses collector settings, never tcpdump or report gen',
    () async {
      await state.setAdblockReportsEnabled(settings);
      expect(api.helperArgs.single, ['check']);
      expect(api.writes.single['adb_report'], '0');
      expect(api.writes.single['adb_enabled'], '1');
      expect(
        api.commands.last,
        contains('openwalla-adblock-reports configure 1'),
      );
      expect(api.commands.join(), isNot(contains('tcpdump')));
      expect(api.calls, contains('uci.commit'));
    },
  );
  test(
    'normal AdBlock works with reports off and no helper installed',
    () async {
      api.ready = false;
      await state.setAdblockReportsEnabled(
        settings.copyWith(reportEnabled: false),
      );
      expect(api.helperArgs, isEmpty);
      expect(api.writes.single['adb_report'], '0');
      expect(api.writes.single['adb_enabled'], '1');
      expect(
        api.commands.last,
        contains('if [ -x /usr/bin/openwalla-adblock-reports ]'),
      );
      expect(api.commands.last, contains('configure 0'));
    },
  );
  test('router rejecting config aborts', () async {
    api.rejectSet = true;
    await expectLater(
      state.setAdblockReportsEnabled(settings),
      throwsStateError,
    );
    expect(api.calls, isNot(contains('uci.commit')));
  });
  test('feed command failure aborts before commit', () async {
    api.failFeed = true;
    await expectLater(state.saveAdblockSettings(settings), throwsStateError);
    expect(api.calls, isNot(contains('uci.commit')));
  });
  test('nonzero service result does not report success', () async {
    api.failService = true;
    await expectLater(state.saveAdblockSettings(settings), throwsStateError);
  });
}
