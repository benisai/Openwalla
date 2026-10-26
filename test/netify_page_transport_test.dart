import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Router;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/router.dart';
import 'package:openwalla/services/interfaces/api_service_interface.dart';
import 'package:openwalla/services/interfaces/auth_service_interface.dart';
import 'package:openwalla/services/router_service.dart';
import 'package:openwalla/services/router_snapshot_cache.dart';
import 'package:openwalla/state/app_state.dart';

class _Auth implements IAuthService {
  @override
  String get sysauth => 'token';
  @override
  bool get isAuthenticated => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements IApiService {
  int rows = 2000;
  int maxResponseRows = 80;
  bool fail = false;
  bool corrupt = false;
  final requests = <({int limit, int offset})>[];

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
    if (object == 'uci') return {'values': <String, dynamic>{}};
    final command = (params?['params'] as List?)?.last.toString() ?? '';
    final match = RegExp(
      r'ORDER BY id DESC LIMIT (\d+) OFFSET (\d+)',
    ).firstMatch(command);
    if (match == null) return {'code': 0, 'stdout': ''};
    final limit = int.parse(match[1]!);
    final offset = int.parse(match[2]!);
    requests.add((limit: limit, offset: offset));
    if (fail) return {'code': 1, 'stderr': 'database is locked'};
    final lines = <String>[];
    for (var i = offset; i < offset + limit && i < rows; i++) {
      lines.add(
        corrupt
            ? 'broken JSON'
            : jsonEncode({
                'type': 'flow',
                'flow': {
                  'local_port': '$i',
                  'host_server_name': 'flow-$i.example',
                },
              }),
      );
      // Simulate rpcd truncation exactly between valid JSON rows.
      if (lines.length >= maxResponseRows) {
        return {'code': 0, 'stdout': lines.join('\n')};
      }
    }
    lines.add('__OPENWALLA_FLOW_PAGE_END__');
    return {'code': 0, 'stdout': '${lines.join('\n')}\n'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppState state;
  late _Api api;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('netify-page-');
    final routers = RouterService();
    await routers.addRouter(
      Router(
        id: 'test-router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: '',
        useHttps: false,
      ),
    );
    api = _Api();
    state = AppState.withServices(
      cache: RouterSnapshotCache(directory: () async => directory),
      routerService: routers,
      apiService: api,
      authService: _Auth(),
    );
    await state.initialized;
  });
  tearDown(() async {
    state.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'truncated responses are split without losing or repeating rows',
    () async {
      final flows = await state.fetchNetifyFlows(limit: 250, offset: 250);
      expect(
        flows.map((flow) => flow.localPort),
        orderedEquals(List.generate(250, (i) => '${250 + i}')),
      );
      expect(api.requests.first, (limit: 250, offset: 250));
      expect(api.requests.any((r) => r.limit < 80), isTrue);
    },
  );

  test('complete short and empty pages mean end of history', () async {
    api.rows = 263;
    expect(
      await state.fetchNetifyFlows(limit: 250, offset: 250),
      hasLength(13),
    );
    expect(await state.fetchNetifyFlows(limit: 250, offset: 263), isEmpty);
  });

  test(
    'RPC command failures propagate instead of becoming empty history',
    () async {
      api.fail = true;
      await expectLater(state.fetchNetifyFlows(limit: 250), throwsStateError);
      expect(api.requests, hasLength(1));
    },
  );

  test(
    'unreadable single rows fail explicitly rather than shortening a page',
    () async {
      api.corrupt = true;
      await expectLater(
        state.fetchNetifyFlows(limit: 250),
        throwsFormatException,
      );
    },
  );
}
