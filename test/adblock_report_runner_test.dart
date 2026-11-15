// Log fixtures are concatenated in arrival order to make interleaving explicit.
// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Map<String, String> env;
  final helper = File(
    'openwrt-setup/files/openwalla-adblock-reports.sh',
  ).absolute.path;
  final parser = File(
    'openwrt-setup/files/openwalla-adblock-reports.awk',
  ).absolute.path;
  late String db;

  Future<ProcessResult> run(List<String> args) =>
      Process.run('/bin/sh', [helper, ...args], environment: env);
  Future<String> sql(String query) async {
    final result = await Process.run('/usr/bin/sqlite3', [
      '-noheader',
      '-list',
      db,
      query,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  Future<void> collect(
    String records, {
    int rows = 10000,
    int hours = 24,
  }) async {
    final awk = await Process.start('/usr/bin/awk', [
      '-v',
      'retention_rows=$rows',
      '-v',
      'retention_hours=$hours',
      '-f',
      parser,
    ]);
    final output = awk.stdout.transform(const SystemEncoding().decoder).join();
    final errors = awk.stderr.transform(const SystemEncoding().decoder).join();
    awk.stdin.write(records);
    await awk.stdin.close();
    expect(await awk.exitCode, 0, reason: await errors);
    final sqlite = await Process.start('/usr/bin/sqlite3', [
      '-batch',
      '-bail',
      db,
    ]);
    final result = sqlite.stdout.drain<void>();
    final sqliteErrors = sqlite.stderr
        .transform(const SystemEncoding().decoder)
        .join();
    sqlite.stdin.write(await output);
    await sqlite.stdin.close();
    expect(await sqlite.exitCode, 0, reason: await sqliteErrors);
    await result;
  }

  String query(
    int serial,
    String domain, {
    String client = '192.168.1.20',
    int time = 1001,
    int pid = 42,
    String type = 'A',
  }) =>
      'Fri Nov 14 [$time.000] daemon.info dnsmasq[$pid]: $serial $client/5000 query[$type] $domain from $client\n';
  String response(
    int serial,
    String domain, {
    String client = '192.168.1.20',
    int time = 1001,
    int pid = 42,
    String origin = 'config',
    String value = 'NXDOMAIN',
  }) =>
      'Fri Nov 14 [$time.001] daemon.info dnsmasq[$pid]: $serial $client/5000 $origin $domain is $value\n';
  String setup() =>
      '__TICK__ 1000\n__PID__ 42\n__POLICY__ ${root.path}/policy\n__IDENTITIES__ ${root.path}/identities\n';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('adblock-sqlite-');
    db = '${root.path}/report.sqlite';
    await Directory('${root.path}/bin').create();
    await File('${root.path}/bin/uci').writeAsString('''#!/bin/sh
case "\$*" in
 *openwalla.adblock_reports.db_path) printf '%s\\n' "\$REPORT_DB";;
 *adblock.global.adb_dns) echo dnsmasq;;
 *"show dhcp.@dnsmasq[0]") echo dhcp.cfg1=dnsmasq;;
 *) exit 1;;
esac
''');
    await Process.run('chmod', ['+x', '${root.path}/bin/uci']);
    env = {'PATH': '${root.path}/bin:/usr/bin:/bin', 'REPORT_DB': db};
    await File('${root.path}/policy').writeAsString(
      'local=/example.com/ads.test/\nlocal=/allowed.example.com/#\n'
      'address=/safe.example.com/216.239.38.120\nlocal=/safe.example.com/\n',
    );
    await File('${root.path}/identities').writeAsString(
      '192.168.1.20|aa:bb:cc:dd:ee:ff|Pixel\n2001:db8::1|aa:bb:cc:dd:ee:ff|Pixel\n',
    );
    final result = await run(['init-db']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'correlates interleaved clients and ignores upstream/cached/non-AdBlock negatives',
    () async {
      await collect(
        setup() +
            query(1, 'ads.test') +
            query(2, 'upstream.test') +
            response(2, 'upstream.test', origin: 'reply') +
            response(1, 'ads.test') +
            query(3, 'example.com') +
            response(3, 'example.com', origin: 'cached') +
            query(4, 'not-in-list.test') +
            response(4, 'not-in-list.test') +
            query(5, 'ads.test', pid: 99) +
            response(5, 'ads.test', pid: 99) +
            query(6, 'sub.example.com', client: '2001:db8::1', type: 'AAAA') +
            response(6, 'sub.example.com', client: '2001:db8::1') +
            response(6, 'sub.example.com', client: '2001:db8::1') +
            '__TICK__ 1005\n',
      );
      expect(await sql('SELECT count(*) FROM events;'), '2');
      expect(
        await sql(
          'SELECT domain,device_name,client_mac,matched_rule FROM events ORDER BY id;',
        ),
        'ads.test|Pixel|aa:bb:cc:dd:ee:ff|ads.test\nsub.example.com|Pixel|aa:bb:cc:dd:ee:ff|example.com',
      );
    },
  );

  test(
    'most specific allowlist and Safe Search rules prevent false blocks',
    () async {
      await collect(
        setup() +
            query(1, 'allowed.example.com') +
            response(1, 'allowed.example.com') +
            query(2, 'safe.example.com') +
            response(2, 'safe.example.com') +
            query(3, 'example.com') +
            response(3, 'example.com', value: '0.0.0.0') +
            '__TICK__ 1005\n',
      );
      expect(await sql('SELECT domain FROM events;'), 'example.com');
    },
  );

  test('identity remains tied to event, not subsequently reused IP', () async {
    await collect(
      setup() +
          query(1, 'ads.test') +
          response(1, 'ads.test') +
          '__TICK__ 1005\n',
    );
    await File(
      '${root.path}/identities',
    ).writeAsString("192.168.1.20|11:22:33:44:55:66|Sam's phone\n");
    await collect(
      '__TICK__ 1010\n__PID__ 42\n__IDENTITIES__ ${root.path}/identities\n' +
          query(2, 'ads.test', time: 1011) +
          response(2, 'ads.test', time: 1011),
    );
    expect(
      await sql('SELECT device_name FROM events ORDER BY id;'),
      "Pixel\nSam's phone",
    );
  });

  test(
    'expiration, missing rules and query IDs without query are fail closed',
    () async {
      await collect(
        setup() +
            query(1, 'ads.test') +
            '__TICK__ 1040\n' +
            response(1, 'ads.test', time: 1040) +
            '__POLICY__ ${root.path}/missing\n' +
            query(2, 'ads.test', time: 1041) +
            response(2, 'ads.test', time: 1041) +
            response(99, 'ads.test'),
      );
      expect(await sql('SELECT count(*) FROM events;'), '0');
    },
  );

  test('retention bounds rows and time; IDs do not reset', () async {
    var records = setup();
    for (var i = 1; i <= 5; i++) {
      records += query(i, 'ads.test') + response(i, 'ads.test');
    }
    await collect('$records\n__TICK__ 1060\n', rows: 2);
    expect(await sql('SELECT id FROM events ORDER BY id;'), '4\n5');
    await collect('__TICK__ 90000\n', rows: 2);
    expect(await sql('SELECT count(*) FROM events;'), '0');
    await collect(
      '__TICK__ 90001\n__PID__ 42\n' +
          query(6, 'ads.test', time: 90002) +
          response(6, 'ads.test', time: 90002),
    );
    expect(await sql('SELECT id FROM events;'), '6');
  });

  test(
    'query safely searches, paginates and rejects invalid numeric bounds',
    () async {
      var records = setup();
      for (var i = 1; i <= 3; i++) {
        records += query(i, 'ads.test') + response(i, 'ads.test');
      }
      await collect(records);
      var result = await run(['query', '--search', 'PIXEL', '--limit', '2']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('S|3|3|1001|1001|1000'));
      expect(
        '${result.stdout}'.split('\n').where((s) => s.startsWith('R|')).length,
        2,
      );
      result = await run(['query', '--before', '2']);
      expect('${result.stdout}', contains('R|1|'));
      expect('${result.stdout}', isNot(contains('R|2|')));
      result = await run([
        'query',
        '--search',
        "' OR 1=1; DROP TABLE events; --",
      ]);
      expect(result.exitCode, 0);
      expect('${result.stdout}', contains('S|3|0|'));
      expect(await sql('SELECT count(*) FROM events;'), '3');
      expect(
        (await run(['query', '--before', '1;DELETE FROM events'])).exitCode,
        isNot(0),
      );
      expect((await run(['query', '--limit', '10000'])).exitCode, isNot(0));
    },
  );

  Future<void> lifecycleFixture() async {
    await Directory('${root.path}/config').create();
    env.addAll({
      'FAKE_CONFIG': '${root.path}/config',
      'SERVICE_LOG': '${root.path}/services',
      'OPENWALLA_ADBLOCK_INIT': '${root.path}/bin/reports',
      'OPENWALLA_DNSMASQ_INIT': '${root.path}/bin/dnsmasq',
      'OPENWALLA_ADBLOCK_PARSER': parser,
      'OPENWALLA_RUNTIME_DIR': root.path,
      'OPENWALLA_DNSMASQ_PID_DIR': root.path,
      'OPENWALLA_DHCP_LEASES': '${root.path}/leases',
      'LOG_RECORDS': '${root.path}/records',
      'LOG_PID': '${root.path}/logger.pid',
    });
    await File('${root.path}/bin/uci').writeAsString(r'''#!/bin/sh
if [ "$*" = '-q show dhcp.@dnsmasq[0]' ]; then echo dhcp.cfg1=dnsmasq; exit 0; fi
[ "$1" != -q ] || shift
action="$1"; shift
case "$action" in
 get) cat "$FAKE_CONFIG/$1" 2>/dev/null;;
 set) key="${1%%=*}"; value="${1#*=}"; printf '%s\n' "$value" >"$FAKE_CONFIG/$key";;
 delete) rm -f "$FAKE_CONFIG/$1";;
 commit) exit 0;;
 *) exit 1;;
esac
''');
    for (final name in ['reports', 'dnsmasq']) {
      await File('${root.path}/bin/$name').writeAsString(r'''#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >>"$SERVICE_LOG"
''');
    }
    await File('${root.path}/bin/logread').writeAsString(r'''#!/bin/sh
echo $$ >"$LOG_PID"
cat "$LOG_RECORDS"
exec sleep 600
''');
    for (final name in ['uci', 'reports', 'dnsmasq', 'logread']) {
      await Process.run('chmod', ['+x', '${root.path}/bin/$name']);
    }
    for (final entry in {
      'openwalla.adblock_reports.db_path': db,
      'adblock.global.adb_dns': 'dnsmasq',
      'adblock.global.adb_enabled': '1',
      'adblock.global.adb_dnsdir': root.path,
    }.entries) {
      await File('${root.path}/config/${entry.key}').writeAsString(entry.value);
    }
  }

  test(
    'reports toggle restores original logging and preserves preference with AdBlock off',
    () async {
      await lifecycleFixture();
      var result = await run(['configure', '1']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        await File('${root.path}/config/dhcp.cfg1.logqueries').readAsString(),
        '1\n',
      );
      await File(
        '${root.path}/config/adblock.global.adb_enabled',
      ).writeAsString('0');
      result = await run(['configure', '1']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        await File(
          '${root.path}/config/openwalla.adblock_reports.enabled',
        ).readAsString(),
        '1\n',
      );
      expect(
        File('${root.path}/config/dhcp.cfg1.logqueries').existsSync(),
        isFalse,
      );
      expect(
        await File('${root.path}/services').readAsString(),
        contains('reports stop'),
      );
      await File(
        '${root.path}/config/adblock.global.adb_enabled',
      ).writeAsString('1');
      await File('${root.path}/config/dhcp.cfg1.logqueries').writeAsString('1');
      expect((await run(['configure', '1'])).exitCode, 0);
      expect((await run(['configure', '0'])).exitCode, 0);
      expect(
        await File('${root.path}/config/dhcp.cfg1.logqueries').readAsString(),
        '1',
      );
      await File(
        '${root.path}/config/adblock.global.adb_dns',
      ).writeAsString('unbound');
      expect((await run(['configure', '1'])).exitCode, isNot(0));
      expect((await run(['configure', '0'])).exitCode, 0);
    },
  );

  test(
    'service termination flushes pending events and stops its log reader',
    () async {
      await lifecycleFixture();
      await File(
        '${root.path}/adb_list.overall',
      ).writeAsString('local=/ads.test/\n');
      await File('${root.path}/dnsmasq.cfg1.pid').writeAsString('42');
      await File(
        '${root.path}/leases',
      ).writeAsString('0 aa:bb:cc:dd:ee:ff 192.168.1.20 Pixel *\n');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1;
      await File('${root.path}/records').writeAsString(
        query(1, 'ads.test', time: now) + response(1, 'ads.test', time: now),
      );
      final process = await Process.start('/bin/sh', [
        helper,
        'run',
      ], environment: env);
      final out = process.stdout.drain<void>();
      final err = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      try {
        for (
          var i = 0;
          i < 40 && !File('${root.path}/logger.pid').existsSync();
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(File('${root.path}/logger.pid').existsSync(), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } finally {
        process.kill();
      }
      expect(
        await process.exitCode.timeout(const Duration(seconds: 12)),
        0,
        reason: await err,
      );
      await out;
      expect(
        await sql('SELECT domain,device_name FROM events;'),
        'ads.test|Pixel',
      );
      final pid = (await File('${root.path}/logger.pid').readAsString()).trim();
      expect((await Process.run('/bin/kill', ['-0', pid])).exitCode, isNot(0));
      expect(
        root.listSync().where((f) => f.path.contains('.adblock-reports.')),
        isEmpty,
      );
    },
  );

  test(
    'deployment replaces capture dependency and preserves minute ping task',
    () {
      final installer = File(
        'openwrt-setup/standalone/install-adblock.sh',
      ).readAsStringSync();
      expect(installer, contains('openwalla-adblock-reports.awk'));
      expect(installer, contains('sqlite3-cli'));
      expect(installer, isNot(contains('install_pkg_if_available "tcpdump')));
      final minute = File(
        'openwrt-setup/files/Openwalla-1min-run.sh',
      ).readAsStringSync();
      expect(minute, contains(r'"$PING_SCRIPT"'));
      expect(minute, isNot(contains('report gen')));
      final sync = File(
        'openwrt-setup/files/openwalla-state-sync.sh',
      ).readAsStringSync();
      expect(sync, contains(r'save_sqlite "$adblock_db"'));
      expect(
        sync,
        contains(r'restore_copy "$state_dir/openwalla-adblock.sqlite"'),
      );
    },
  );
}
