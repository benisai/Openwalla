import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/netify_flow_storage.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String db;
  late Map<String, String> environment;

  final payload = {
    'type': 'flow',
    'interface': 'br-lan',
    'flow': {
      'local_ip': '192.168.8.231',
      'local_mac': 'aa:bb:cc:dd:ee:ff',
      'local_port': 12345,
      'fqdn': 'example.com',
      'other_ip': '1.2.3.4',
      'other_port': 443,
      'detected_protocol_name': 'HTTP/S',
      'detected_application_name': "Example's App",
      'first_seen_at': 1793333300.25,
      'last_seen_at': 1793333361.5,
      'other_bytes': 123456789,
      'local_bytes': 987654321,
      'total_bytes': 1111111110,
      'other_country_code': 'us',
      'other_country_name': 'United States',
      'direction': 'Inbound',
      'ssl': {'client_sni': 'example.com'},
      'unused': List.filled(100, 'large unused data'),
    },
  };

  Future<ProcessResult> shell(String steps) => Process.run('/bin/sh', [
    '-c',
    'set -e\n. "\$COLLECTOR"\n$steps',
  ], environment: environment);

  Future<void> run(String steps) async {
    final result = await shell(steps);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  Future<String> sql(String query) async {
    final result = await Process.run('/usr/bin/sqlite3', [db, query]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout.toString().trim();
  }

  Future<List<NetifyFlow>> readPage({int offset = 0, String where = ''}) async {
    final command = NetifyFlowStorage.pageCommand(
      dbExpression: db,
      where: where,
      limit: 10,
      offset: offset,
      endMarker: 'END',
    );
    final result = await Process.run('/bin/sh', ['-c', command]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final lines = result.stdout.toString().trim().split('\n');
    expect(lines.last, 'END');
    return lines.take(lines.length - 1).map((line) {
      final flow = NetifyFlow.fromJsonLine(line);
      expect(flow, isNotNull);
      return flow!;
    }).toList();
  }

  List<Object> details(NetifyFlow flow) => [
    flow.timestamp,
    flow.deviceMac,
    flow.localIp,
    flow.localPort,
    flow.destination,
    flow.application,
    flow.protocol,
    flow.destinationIp,
    flow.destinationPort,
    flow.interfaceName,
    flow.downloadedBytes,
    flow.uploadedBytes,
    flow.totalBytes,
    flow.countryCode,
    flow.region,
    flow.direction,
  ];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('netify-columns-');
    db = '${root.path}/flows.sqlite';
    environment = {
      'COLLECTOR': File(
        'openwrt-setup/files/openwalla-netify-collector.sh',
      ).absolute.path,
      'OPENWALLA_NETIFY_COLLECTOR_SOURCE_ONLY': '1',
      'SQLITE_BIN': '/usr/bin/sqlite3',
      'NETIFY_DB': db,
    };
    // Sourcing the collector sets defaults; override them after sourcing.
    environment['TEST_DB'] = db;
    environment['PAYLOAD'] = jsonEncode(payload);
  });
  tearDown(() => root.delete(recursive: true));

  const setup = r'NETIFY_DB="$TEST_DB"; SQLITE_BIN=/usr/bin/sqlite3';

  test(
    'fresh collector inserts columns, no stored JSON, and survives restart',
    () async {
      await run(
        '$setup\ninit_db\ninsert_flow "\$PAYLOAD"\ninit_db\ninsert_flow "\$PAYLOAD"',
      );
      expect(await sql('SELECT count(*) FROM flow_raw;'), '2');
      expect(await readPage(offset: 2), isEmpty);
      expect(
        await sql(
          "SELECT count(*) FROM pragma_table_info('flow_raw') WHERE name='json';",
        ),
        '0',
      );
      expect(
        details((await readPage()).first),
        details(NetifyFlow.fromJsonLine(jsonEncode(payload))!),
      );
      expect(
        await readPage(where: "WHERE detected_app_name='Example''s App'"),
        hasLength(2),
      );
      expect(
        await sql(
          "SELECT count(*) FROM sqlite_master WHERE type='index' AND tbl_name='flow_raw';",
        ),
        '4',
      );
    },
  );

  test(
    'unsupported database is rejected without migrating or deleting it',
    () async {
      await sql(
        "CREATE TABLE flow_raw(id INTEGER PRIMARY KEY,timeinsert INTEGER,json TEXT); INSERT INTO flow_raw VALUES(1,1,'saved');",
      );
      final result = await shell('$setup\ninit_db');
      expect(result.exitCode, isNot(0));
      expect(await sql('SELECT json FROM flow_raw;'), 'saved');
      final read = await Process.run('/bin/sh', [
        '-c',
        NetifyFlowStorage.pageCommand(
          dbExpression: db,
          where: '',
          limit: 10,
          offset: 0,
          endMarker: 'END',
        ),
      ]);
      expect(read.exitCode, isNot(0));
    },
  );

  test(
    'explicit compaction reclaims deleted pages and preserves flow data',
    () async {
      await run('$setup\ninit_db\ninsert_flow "\$PAYLOAD"');
      await sql('''WITH RECURSIVE numbers(n) AS (
 SELECT 1 UNION ALL SELECT n+1 FROM numbers WHERE n<2000
) INSERT INTO flow_raw(timeinsert,fqdn) SELECT 1,printf('%0500d',n) FROM numbers;
DELETE FROM flow_raw WHERE id>1;
PRAGMA wal_checkpoint(TRUNCATE);''');
      final originalSize = await File(db).length();
      await run('$setup\ninit_db\ncompact_db');
      expect(await File(db).length(), lessThan(originalSize));
      expect(await sql('PRAGMA quick_check;'), 'ok');
      expect(await sql('SELECT count(*) FROM flow_raw;'), '1');
      expect(
        details((await readPage()).single),
        details(NetifyFlow.fromJsonLine(jsonEncode(payload))!),
      );
    },
  );

  test(
    'missing optional values default, aliases preserve counters and millisecond timestamps',
    () async {
      environment['PAYLOAD'] = jsonEncode({
        'type': 'flow',
        'flow': {
          'first_seen_at': 1793333300250,
          'src_port': 54321,
          'download_bytes': 45,
          'upload_bytes': 67,
          'country_code': 'gb',
          'region': 'London',
        },
      });
      await run('$setup\ninit_db\ninsert_flow "\$PAYLOAD"');
      final flow = (await readPage()).single;
      expect(flow.downloadedBytes, 45);
      expect(flow.uploadedBytes, 67);
      expect(flow.totalBytes, 112);
      expect(flow.localPort, '54321');
      expect(flow.timestamp.millisecondsSinceEpoch, 1793333300250);
      expect(flow.countryCode, 'GB');
      expect(flow.region, 'London');
      expect(flow.direction, 'Outbound');
    },
  );

  test('ingestion preserves alternative Netify identity fields', () async {
    final alternate = jsonEncode({
      'type': 'flow',
      'flow': {
        'local_mac': ['', 'aa-bb-cc-dd-ee-ff'],
        'src_ip': '192.168.1.25',
        'src_port': 123,
        'remote_ip': '8.8.8.8',
        'remote_port': 8443,
        'tls': {'client_sni': 'tls.example'},
        'host_server_name': 'secondary.example',
        'application_name': 'Alternate App',
        'protocol_name': 'TLS',
        'local_interface': 'br-lan',
        'last_seen_at': 1793333361,
      },
    });
    final expected = details(NetifyFlow.fromJsonLine(alternate)!);
    // Legacy JSON parsing stringified MAC arrays; the column stores the MAC.
    expected[1] = 'AA:BB:CC:DD:EE:FF';
    environment['PAYLOAD'] = alternate;
    await run('$setup\ninit_db\ninsert_flow "\$PAYLOAD"');
    expect((await readPage()).map(details), everyElement(expected));
  });

  test(
    'WAN interface is excluded by default and configurable for new inserts',
    () async {
      environment['PAYLOAD'] = jsonEncode({...payload, 'interface': 'wan'});
      await run('$setup\ninit_db\ninsert_flow "\$PAYLOAD"');
      expect(await sql('SELECT count(*) FROM flow_raw;'), '0');
      await run(
        '$setup\ninit_db\nEXCLUDE_WAN_INTERFACE=0\ninsert_flow "\$PAYLOAD"',
      );
      expect(await sql('SELECT interface FROM flow_raw;'), 'wan');
      await run('$setup\ninit_db\ninsert_flow "\$PAYLOAD"');
      expect(await sql('SELECT count(*) FROM flow_raw;'), '1');
    },
  );

  test('WAN check uses resolved interface and exact name only', () async {
    final baseFlow = Map<String, dynamic>.from(payload['flow']! as Map);
    final cases = <({Map<String, dynamic> event, bool keep})>[
      (event: {...payload, 'interface': ' WAN '}, keep: false),
      (
        event: {
          'type': 'flow',
          'flow': {...baseFlow, 'interface': 'wan'},
        },
        keep: false,
      ),
      (
        event: {
          'type': 'flow',
          'flow': {...baseFlow, 'local_interface': 'wan'},
        },
        keep: false,
      ),
      (event: {...payload, 'interface': 'wan6'}, keep: true),
      (event: {...payload, 'interface': 'pppoe-wan'}, keep: true),
      (event: {'type': 'flow', 'flow': baseFlow}, keep: true),
      (
        event: {
          ...payload,
          'flow': {...baseFlow, 'interface': 'wan'},
        },
        keep: true,
      ),
    ];
    var count = 0;
    for (final item in cases) {
      environment['PAYLOAD'] = jsonEncode(item.event);
      await run('$setup\ninit_db\ninsert_flow "\$PAYLOAD"');
      if (item.keep) count++;
      expect(
        await sql('SELECT count(*) FROM flow_raw;'),
        '$count',
        reason: '${item.event}',
      );
    }
  });
}
