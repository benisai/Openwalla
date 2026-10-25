import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String db;
  late String functions;
  late Map<String, String> environment;

  String flow({
    int rx = 1000,
    int tx = 2000,
    String state = 'ESTABLISHED',
    int port = 1234,
  }) =>
      'ipv4 2 tcp 6 100 $state src=192.168.1.10 dst=8.8.8.8 '
      'sport=$port dport=443 packets=10 bytes=$tx '
      'src=8.8.8.8 dst=192.168.1.10 sport=443 dport=$port packets=20 bytes=$rx [ASSURED]\n';

  Future<String> sql(String query) async {
    final result = await Process.run('/usr/bin/sqlite3', [db, query]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return result.stdout.toString().trim();
  }

  Future<void> fixture(String name, String content) async {
    final path = '${root.path}/$name';
    await File(path).writeAsString(content);
    environment[name] = path;
  }

  Future<void> run(String steps) async {
    final result = await Process.run('/bin/sh', [
      '-c',
      '''
set -e
stats_sql_exec() { "\$SQLITE_BIN" "\$FLOW_STATS_DB" "\$1"; }
$functions
flow_stats_read_conntrack() { cat "\$FIXTURE"; }
flow_stats_write_neighbors() { printf '192.168.1.10\\taa:bb:cc:dd:ee:ff\\n'; }
FLOW_STATS_WARM=1
flow_stats_init_db
$steps
''',
    ], environment: environment);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openwalla-flow-test-');
    db = '${root.path}/stats.sqlite';
    final source = await File(
      'openwrt-setup/files/openwalla-netify-collector.sh',
    ).readAsString();
    functions = source.substring(
      source.indexOf('flow_stats_init_db()'),
      source.indexOf('escape_sed_replacement()'),
    );
    environment = {
      'SQLITE_BIN': '/usr/bin/sqlite3',
      'FLOW_STATS_DB': db,
      'FLOW_STATS_WORK_DIR': '${root.path}/work',
      'FLOW_STATS_BUCKET_SECONDS': '300',
      'FLOW_STATS_RETENTION_SECONDS': '2592000',
      'ROUTER_LAN_IPV4S': '192.168.1.1',
    };
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'startup baselines existing flows; new flows include initial bytes',
    () async {
      await fixture('FIRST', flow());
      await fixture('SECOND', flow() + flow(port: 2345, rx: 300, tx: 200));
      await run(r'''
FIXTURE=$FIRST; flow_stats_collect_once
FIXTURE=$SECOND; flow_stats_collect_once
flow_stats_collect_once
''');
      expect(
        await sql('SELECT rx_bytes,tx_bytes FROM flow_stats_totals;'),
        '300|200',
      );
    },
  );

  test(
    'growth and temporarily absent flows retain baselines without double counting',
    () async {
      await fixture('FIRST', flow());
      await fixture('SECOND', flow(rx: 1500, tx: 2600));
      await fixture('EMPTY', '');
      await fixture('THIRD', flow(rx: 1600, tx: 2700));
      await run(r'''
FIXTURE=$FIRST; flow_stats_collect_once
FIXTURE=$SECOND; flow_stats_collect_once
FIXTURE=$EMPTY; flow_stats_collect_once
FIXTURE=$THIRD; flow_stats_collect_once
''');
      expect(
        await sql('SELECT rx_bytes,tx_bytes FROM flow_stats_totals;'),
        '600|700',
      );
    },
  );

  test(
    'counter reset counts new counters and drops the prior application label',
    () async {
      await fixture('FIRST', flow());
      await fixture('SECOND', flow(rx: 20, tx: 10));
      await run(r'''
FIXTURE=$FIRST; flow_stats_collect_once
stats_sql_exec "INSERT INTO flow_stats_labels VALUES('tcp|192.168.1.10|8.8.8.8|1234|443','Old app','old.example',strftime('%s','now'));"
FIXTURE=$SECOND; flow_stats_collect_once
''');
      expect(
        await sql(
          'SELECT application,rx_bytes,tx_bytes FROM flow_stats_totals;',
        ),
        'Unknown|20|10',
      );
      expect(await sql('SELECT count(*) FROM flow_stats_labels;'), '0');
    },
  );

  test(
    'closing-to-active TCP tuple counts a new connection even with larger counters',
    () async {
      await fixture('FIRST', flow(rx: 10, tx: 20, state: 'TIME_WAIT'));
      await fixture('SECOND', flow(rx: 100, tx: 200));
      await run(r'''
FIXTURE=$FIRST; flow_stats_collect_once
FIXTURE=$SECOND; flow_stats_collect_once
''');
      expect(
        await sql('SELECT rx_bytes,tx_bytes FROM flow_stats_totals;'),
        '100|200',
      );
    },
  );

  test(
    'huge newly observed flows baseline instead of replaying historical bytes',
    () async {
      await fixture('EMPTY', '');
      await fixture('FIRST', flow(rx: 2147483648, tx: 100));
      await fixture('SECOND', flow(rx: 2147483748, tx: 150));
      await run(r'''
FIXTURE=$EMPTY; flow_stats_collect_once
FIXTURE=$FIRST; flow_stats_collect_once
FIXTURE=$SECOND; flow_stats_collect_once
''');
      expect(
        await sql('SELECT rx_bytes,tx_bytes FROM flow_stats_totals;'),
        '100|50',
      );
    },
  );

  test('failed reads do not advance the startup baseline', () async {
    await fixture('FIRST', flow());
    await run(r'''
flow_stats_read_conntrack() { return 1; }
if flow_stats_collect_once; then exit 2; fi
[ "$FLOW_STATS_WARM" = 1 ]
flow_stats_read_conntrack() { cat "$FIRST"; }
flow_stats_collect_once
''');
    expect(await sql('SELECT count(*) FROM flow_stats_totals;'), '0');
  });

  test(
    'old state schema migrates without deleting totals and startup rebases persisted state',
    () async {
      await sql(
        'CREATE TABLE flow_stats_state(flow_key TEXT PRIMARY KEY,rx_bytes INTEGER NOT NULL,tx_bytes INTEGER NOT NULL,updated_at INTEGER NOT NULL);'
        "INSERT INTO flow_stats_state VALUES('tcp|192.168.1.10|8.8.8.8|1234|443',100,200,strftime('%s','now'));"
        'CREATE TABLE flow_stats_totals(mac TEXT,application TEXT,destination TEXT,rx_bytes INTEGER,tx_bytes INTEGER,updated_at INTEGER,PRIMARY KEY(mac,application,destination));'
        "INSERT INTO flow_stats_totals VALUES('device','Saved','example',77,88,1);",
      );
      await fixture('FIRST', flow());
      await run(r'''
flow_stats_init_db
FIXTURE=$FIRST; flow_stats_collect_once
''');
      expect(
        await sql('SELECT rx_bytes,tx_bytes FROM flow_stats_totals;'),
        '77|88',
      );
      expect(
        await sql(
          "SELECT COUNT(*) FROM pragma_table_info('flow_stats_state') WHERE name='tcp_state';",
        ),
        '1',
      );
    },
  );
}
