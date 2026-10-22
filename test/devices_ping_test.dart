import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String db;
  late Map<String, String> environment;
  final pingScript = File(
    'openwrt-setup/files/openwalla-devices-ping.sh',
  ).absolute.path;
  final runner = File(
    'openwrt-setup/files/Openwalla-1min-run.sh',
  ).absolute.path;

  Future<void> executable(String name, String body) async {
    final file = await File(
      '${root.path}/bin/$name',
    ).writeAsString('#!/bin/sh\n$body');
    await Process.run('chmod', ['755', file.path]);
  }

  Future<String> sql(String statement) async {
    final result = await Process.run('sqlite3', [db, statement]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return result.stdout.toString().trim();
  }

  Future<ProcessResult> scan() =>
      Process.run('sh', [pingScript], environment: environment);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openwalla-ping-test-');
    await Directory('${root.path}/bin').create();
    db = '${root.path}/devices.sqlite';
    environment = {
      'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
      'OPENWALLA_DEVICES_DB': db,
      'OPENWALLA_RUNTIME_DIR': '${root.path}/run',
      'OPENWALLA_CRON_PATH': '${root.path}/crontab',
      'FAKE_ROOT': root.path,
    };
    await executable('uci', 'exit 1\n');
    await executable('killall', 'exit 0\n');
    await executable('ip', r'''
case "$*" in
  '-4 addr show') echo '    inet 192.168.1.1/24 scope global br-lan' ;;
  '-4 neigh show to 192.168.1.8') echo '192.168.1.8 dev br-lan lladdr aa:bb:cc:dd:ee:ff REACHABLE' ;;
esac
''');
    await executable('ping', r'''
for ip do :; done
echo "start $ip" >>"$FAKE_ROOT/pings"
sleep 0.1
echo "end $ip" >>"$FAKE_ROOT/pings"
if [ "${FAKE_CHANGE_IP:-0}" = 1 ]; then
  sqlite3 "$OPENWALLA_DEVICES_DB" "UPDATE devices SET ip='192.168.1.200';"
fi
[ "$ip" != 192.168.1.9 ]
''');
    await sql('''
CREATE TABLE devices (
  mac TEXT PRIMARY KEY, ip TEXT, hidden INTEGER DEFAULT 0,
  last_seen INTEGER DEFAULT 1, status TEXT DEFAULT 'offline',
  quarantined INTEGER DEFAULT 0, scheduled_block INTEGER DEFAULT 0
);
''');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'replies refresh presence without changing access-control state',
    () async {
      await sql('''
INSERT INTO devices(mac,ip,status,quarantined,scheduled_block) VALUES
('02:00:00:00:00:02','192.168.1.2','offline',0,0),
('02:00:00:00:00:03','192.168.1.3','blocked',0,0),
('02:00:00:00:00:04','192.168.1.4','blocked',1,0),
('02:00:00:00:00:05','192.168.1.5','block-scheduled',0,1);
''');
      final result = await scan();
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        await sql('SELECT status FROM devices ORDER BY ip;'),
        'online\nblocked\nblocked\nblock-scheduled',
      );
      expect(await sql('SELECT count(*) FROM devices WHERE last_seen>1;'), '4');
      expect(await sql('SELECT sum(quarantined) FROM devices;'), '1');
    },
  );

  test(
    'missed replies and reassigned neighbor MACs do not refresh history',
    () async {
      await sql('''
INSERT INTO devices(mac,ip,status) VALUES
('02:00:00:00:00:08','192.168.1.8','offline'),
('02:00:00:00:00:09','192.168.1.9','online');
''');
      expect((await scan()).exitCode, 0);
      expect(await sql('SELECT sum(last_seen) FROM devices;'), '2');
      expect(
        await sql("SELECT status FROM devices WHERE ip='192.168.1.9';"),
        'online',
      );
    },
  );

  test(
    'hidden, router-owned and malformed addresses are never pinged',
    () async {
      await sql('''
INSERT INTO devices(mac,ip,hidden) VALUES
('02:00:00:00:00:01','192.168.1.1',0),
('02:00:00:00:00:02','192.168.1.2',1),
('bad-mac','192.168.1.3',0),
('02:00:00:00:00:04','192.168.1.999',0),
('02:00:00:00:00:05','127.0.0.1',0),
('02:00:00:00:00:06','',0),
('02:00:00:00:00:07','192.168.1.7;touch /tmp/bad',0);
''');
      expect((await scan()).exitCode, 0);
      expect(File('${root.path}/pings').existsSync(), isFalse);
      expect(await sql('SELECT sum(last_seen) FROM devices;'), '7');
    },
  );

  test(
    'workers run in batches of five including the final partial batch',
    () async {
      for (var i = 10; i < 22; i++) {
        await sql(
          "INSERT INTO devices(mac,ip) VALUES('02:00:00:00:00:$i','192.168.1.$i');",
        );
      }
      final result = await scan();
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final events = await File('${root.path}/pings').readAsLines();
      var active = 0;
      var maximum = 0;
      for (final event in events) {
        active += event.startsWith('start') ? 1 : -1;
        if (active > maximum) maximum = active;
        expect(active, inInclusiveRange(0, 5));
      }
      expect(maximum, 5);
      expect(active, 0);
      expect(
        await sql("SELECT count(*) FROM devices WHERE status='online';"),
        '12',
      );
    },
  );

  test(
    'overlapping scans skip and missing databases are not created',
    () async {
      await Directory(
        '${root.path}/run/openwalla-devices-ping.lock',
      ).create(recursive: true);
      expect((await scan()).stdout, contains('already running'));
      await File(db).delete();
      expect((await scan()).exitCode, 0);
      expect(File(db).existsSync(), isFalse);
    },
  );

  test('disabled inventory does not launch probes', () async {
    await executable('uci', 'echo 0\n');
    await sql(
      "INSERT INTO devices(mac,ip) VALUES('02:00:00:00:00:02','192.168.1.2');",
    );
    expect((await scan()).exitCode, 0);
    expect(File('${root.path}/pings').existsSync(), isFalse);
  });

  test('a changed IP during a scan cannot refresh the old assignment', () async {
    await sql(
      "INSERT INTO devices(mac,ip) VALUES('02:00:00:00:00:02','192.168.1.2');",
    );
    environment['FAKE_CHANGE_IP'] = '1';
    expect((await scan()).exitCode, 0);
    expect(
      await sql('SELECT ip,last_seen,status FROM devices;'),
      '192.168.1.200|1|offline',
    );
  });

  test('component updates add ping helpers only for installed collectors', () {
    final source = File(
      'openwrt-setup/openwalla-components.sh',
    ).readAsStringSync();
    expect(
      source,
      contains(
        'files/openwalla-device-access.sh|files/Openwalla-1min-run.sh|files/openwalla-devices-ping.sh)\n\t\t\t[ -x /usr/bin/openwalla-devices-collector ] || return 0',
      ),
    );
    expect(source, contains('/usr/bin/Openwalla-1min-run.sh install-cron'));
  });

  test(
    'minute cron installation is idempotent and preserves other jobs',
    () async {
      await File(
        '${root.path}/crontab',
      ).writeAsString('0 * * * * hourly-task\n');
      for (var i = 0; i < 2; i++) {
        final result = await Process.run('sh', [
          runner,
          'install-cron',
        ], environment: environment);
        expect(result.exitCode, 0, reason: result.stderr.toString());
      }
      final cron = await File('${root.path}/crontab').readAsString();
      expect(cron, contains('hourly-task'));
      expect('OPENWALLA_1MIN_RUN'.allMatches(cron).length, 1);
      expect(cron, contains('* * * * * mkdir -p /tmp/openwalla;'));
      await executable('probe', 'echo called\n');
      final result = await Process.run(
        'sh',
        [runner, 'run'],
        environment: {
          ...environment,
          'OPENWALLA_DEVICES_PING': '${root.path}/bin/probe',
        },
      );
      expect(result.exitCode, 0);
      expect(result.stdout, contains('called'));
    },
  );
}
