import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/netify_flow_storage.dart';
import 'package:openwalla/state/app_state.dart';

const legacySchema = '''
CREATE TABLE flow_raw (
 id INTEGER PRIMARY KEY AUTOINCREMENT, timeinsert INTEGER NOT NULL,
 local_ip TEXT, local_mac TEXT, fqdn TEXT, dest_ip TEXT, dest_port INTEGER,
 dest_type TEXT, detected_protocol_name TEXT, detected_app_name TEXT,
 interface TEXT, internal INTEGER, ndpi_risk_score INTEGER,
 ndpi_risk_score_client INTEGER, ndpi_risk_score_server INTEGER, client_sni TEXT,
 category_application INTEGER, category_domain INTEGER, category_protocol INTEGER,
 detected_application INTEGER, detected_protocol INTEGER, detection_guessed INTEGER,
 dns_host_name TEXT, host_server_name TEXT, digest TEXT, json TEXT NOT NULL);
CREATE INDEX idx_flow_raw_time ON flow_raw(timeinsert);
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late String db;
  late Map<String, String> environment;

  final payload = {
    'type': 'flow',
    'interface': 'wan',
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

  Future<void> legacy({String? raw}) async {
    final json = (raw ?? jsonEncode(payload)).replaceAll("'", "''");
    await sql('''$legacySchema
INSERT INTO flow_raw VALUES (
 41,1793333362,'192.168.8.231','aa:bb:cc:dd:ee:ff','example.com',
 '1.2.3.4',443,'remote','HTTP/S','Example''s App','wan',0,
 10,5,5,'example.com',0,0,22,0,196,0,'example.com','example.com','digest','$json');
UPDATE sqlite_sequence SET seq=100 WHERE name='flow_raw';
''');
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
    'migrates history without JSON and preserves every displayed field and IDs',
    () async {
      await legacy();
      final before = (await readPage()).single;
      await run('$setup\ninit_db\ninit_db');
      expect(
        await sql(
          "SELECT count(*) FROM pragma_table_info('flow_raw') WHERE name='json';",
        ),
        '0',
      );
      expect(
        await sql('SELECT id,ndpi_risk_score,digest FROM flow_raw;'),
        '41|10|digest',
      );
      expect(
        await sql("SELECT seq FROM sqlite_sequence WHERE name='flow_raw';"),
        '100',
      );
      final after = (await readPage()).single;
      expect(details(after), details(before));
      expect(after.rawJson.length, lessThan(before.rawJson.length));
      expect(await readPage(offset: 1), isEmpty);
    },
  );

  test(
    'fresh collector inserts columns, no stored JSON, and survives restart',
    () async {
      await run(
        '$setup\ninit_db\ninsert_flow "\$PAYLOAD"\ninit_db\ninsert_flow "\$PAYLOAD"',
      );
      expect(await sql('SELECT count(*) FROM flow_raw;'), '2');
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
    'malformed legacy JSON cancels migration without losing original rows',
    () async {
      await legacy(raw: 'not json');
      final result = await shell('$setup\ninit_db');
      expect(result.exitCode, isNot(0));
      expect(await sql('SELECT json FROM flow_raw;'), 'not json');
      expect(
        await sql(
          "SELECT count(*) FROM sqlite_master WHERE name='flow_raw_compact';",
        ),
        '0',
      );
    },
  );

  test(
    'explicit compaction shrinks migrated storage and preserves flow data',
    () async {
      await legacy();
      await sql(
        "INSERT INTO flow_raw SELECT NULL,timeinsert,local_ip,local_mac,fqdn,dest_ip,dest_port,dest_type,detected_protocol_name,detected_app_name,interface,internal,ndpi_risk_score,ndpi_risk_score_client,ndpi_risk_score_server,client_sni,category_application,category_domain,category_protocol,detected_application,detected_protocol,detection_guessed,dns_host_name,host_server_name,digest,json FROM flow_raw;",
      );
      for (var i = 0; i < 5; i++) {
        await sql('''INSERT INTO flow_raw
SELECT NULL,timeinsert,local_ip,local_mac,fqdn,dest_ip,dest_port,dest_type,
detected_protocol_name,detected_app_name,interface,internal,ndpi_risk_score,
ndpi_risk_score_client,ndpi_risk_score_server,client_sni,category_application,
category_domain,category_protocol,detected_application,detected_protocol,
detection_guessed,dns_host_name,host_server_name,digest,json FROM flow_raw;''');
      }
      final originalSize = await File(db).length();
      await run('$setup\ninit_db\ncompact_db');
      expect(await File(db).length(), lessThan(originalSize));
      expect(await sql('PRAGMA quick_check;'), 'ok');
      expect(await sql('SELECT count(*) FROM flow_raw;'), '64');
    },
  );

  test(
    'SQL failure mid migration rolls back the entire schema replacement',
    () async {
      await legacy();
      final result = await shell('''$setup
sql_exec() {
 query="\$(printf '%s' "\$1" | sed 's/DROP TABLE flow_raw;/SELECT missing_function(); DROP TABLE flow_raw;/')"
 "\$SQLITE_BIN" "\$NETIFY_DB" "\$query"
}
init_db
''');
      expect(result.exitCode, isNot(0));
      expect(await sql('SELECT count(*) FROM flow_raw;'), '1');
      expect(
        await sql(
          "SELECT count(*) FROM pragma_table_info('flow_raw') WHERE name='json';",
        ),
        '1',
      );
      expect(
        await sql(
          "SELECT count(*) FROM sqlite_master WHERE name='flow_raw_compact';",
        ),
        '0',
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

  test(
    'migration and ingestion preserve alternative Netify identity fields',
    () async {
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
      await legacy(raw: alternate);
      await run('$setup\ninit_db');
      final expected = details(NetifyFlow.fromJsonLine(alternate)!);
      // Legacy JSON parsing stringified MAC arrays; the column stores the MAC.
      expected[1] = 'AA:BB:CC:DD:EE:FF';
      expect(details((await readPage()).single), expected);
      environment['PAYLOAD'] = alternate;
      await run('$setup\ninit_db\ninsert_flow "\$PAYLOAD"');
      expect((await readPage()).map(details), everyElement(expected));
    },
  );
}
