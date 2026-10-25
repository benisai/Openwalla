import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File(
    'openwrt-setup/files/Openwalla-5min-run.sh',
  ).absolute.path;
  late Directory root;
  late Map<String, String> env;

  Future<void> executable(String path, String body) async {
    await File('${root.path}/$path').writeAsString('#!/bin/sh\n$body');
    final result = await Process.run('chmod', ['755', '${root.path}/$path']);
    expect(result.exitCode, 0);
  }

  Future<void> memory(int pid, int parent, int kb) async {
    await Directory('${root.path}/proc/$pid').create(recursive: true);
    await File(
      '${root.path}/proc/$pid/status',
    ).writeAsString('Name:\tworker\nPPid:\t$parent\nVmRSS:\t$kb kB\n');
  }

  Future<ProcessResult> run([String action = 'run']) =>
      Process.run('sh', [script, action], environment: env);

  Future<String> actions() async {
    final file = File('${root.path}/actions');
    return await file.exists() ? file.readAsString() : '';
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openwalla-watchdog-');
    for (final dir in ['bin', 'init', 'proc']) {
      await Directory('${root.path}/$dir').create();
    }
    env = {
      'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
      'FAKE_ROOT': root.path,
      'OPENWALLA_RUNTIME_DIR': '${root.path}/run',
      'OPENWALLA_CRON_PATH': '${root.path}/crontab',
      'OPENWALLA_INIT_DIR': '${root.path}/init',
      'OPENWALLA_PROC_DIR': '${root.path}/proc',
    };
    await File(
      '${root.path}/proc/meminfo',
    ).writeAsString('MemTotal: 1000 kB\n');
    await memory(101, 1, 100);
    await memory(201, 1, 50);
    await memory(202, 201, 50);
    await executable('bin/uci', r'''
case "$*" in
  *collector.enabled) echo "${COLLECTOR_ENABLED:-1}" ;;
  *collector.mode) echo "${COLLECTOR_MODE:-local}" ;;
  *memory_limit_percent) echo "${LIMIT:-25}" ;;
  *) exit 1 ;;
esac
''');
    await executable('bin/ubus', r'''
[ "${UBUS_FAIL:-0}" != 1 ] || exit 1
case "$*" in
  *openwalla-netify-collector*) [ "${COLLECTOR_MISSING:-0}" = 1 ] || echo 201 ;;
  *) [ "${NETIFY_MISSING:-0}" = 1 ] || echo 101 ;;
esac
exit 0
''');
    await executable('bin/jsonfilter', 'cat\n');
    await executable('bin/killall', 'exit 0\n');
    for (final name in ['netifyd', 'openwalla-netify-collector', 'cron']) {
      await executable('init/$name', r'''
name="${0##*/}"
if [ "$1" = enabled ]; then exit "${SERVICE_DISABLED:-0}"; fi
echo "$name $1" >>"$FAKE_ROOT/actions"
if [ "$name" = netifyd ] && [ "$1" = restart ]; then exit "${RESTART_FAIL:-0}"; fi
exit 0
''');
    }
  });

  tearDown(() => root.delete(recursive: true));

  test('healthy services and exactly 25 percent do not restart', () async {
    await memory(101, 1, 250);
    expect((await run()).exitCode, 0);
    expect(await actions(), isEmpty);
  });

  test(
    'Netify above threshold restarts services in dependency order',
    () async {
      await memory(101, 1, 251);
      expect((await run()).exitCode, 0);
      expect(
        await actions(),
        'openwalla-netify-collector stop\nnetifyd restart\n'
        'openwalla-netify-collector start\n',
      );
    },
  );

  test('collector includes child RSS and respects configured limit', () async {
    env['LIMIT'] = '40';
    await memory(202, 201, 351);
    expect((await run()).exitCode, 0);
    expect(await actions(), contains('netifyd restart\n'));
  });

  test('missing Netify recovers source before consumer', () async {
    env['NETIFY_MISSING'] = '1';
    expect((await run()).exitCode, 0);
    expect(
      await actions(),
      'openwalla-netify-collector stop\nnetifyd restart\n'
      'openwalla-netify-collector start\n',
    );
  });

  test('missing collector starts without restarting healthy Netify', () async {
    env['COLLECTOR_MISSING'] = '1';
    expect((await run()).exitCode, 0);
    expect(await actions(), 'openwalla-netify-collector start\n');
  });

  test(
    'external mode and disabled collector never start local collector',
    () async {
      await memory(101, 1, 300);
      env['COLLECTOR_MODE'] = 'external';
      expect((await run()).exitCode, 0);
      expect(await actions(), 'netifyd restart\n');
      await File('${root.path}/actions').delete();
      env['COLLECTOR_MODE'] = 'local';
      env['COLLECTOR_ENABLED'] = '0';
      expect((await run()).exitCode, 0);
      expect(await actions(), 'netifyd restart\n');
    },
  );

  test(
    'failed source restart does not start collector; lock is released',
    () async {
      await memory(101, 1, 300);
      env['RESTART_FAIL'] = '1';
      expect((await run()).exitCode, 1);
      expect(
        await actions(),
        'openwalla-netify-collector stop\nnetifyd restart\n',
      );
      expect(
        await Directory('${root.path}/run/openwalla-5min-run.lock').exists(),
        isFalse,
      );
    },
  );

  test(
    'disabled service or unavailable service query does not restart',
    () async {
      env['SERVICE_DISABLED'] = '1';
      expect((await run()).exitCode, 0);
      env['SERVICE_DISABLED'] = '0';
      env['UBUS_FAIL'] = '1';
      expect((await run()).exitCode, 1);
      expect(await actions(), isEmpty);
    },
  );

  test('missing Netify skips successfully without querying services', () async {
    await File('${root.path}/init/netifyd').delete();
    await File('${root.path}/proc/meminfo').delete();
    env['UBUS_FAIL'] = '1';
    final result = await run();
    expect(result.exitCode, 0);
    expect(result.stdout, contains('Netify is not installed; skipping'));
    expect(await actions(), isEmpty);
    expect(
      await Directory('${root.path}/run/openwalla-5min-run.lock').exists(),
      isFalse,
    );
  });

  test('runner deploys alongside existing maintenance runners', () {
    for (final installer in [
      'install-devices-collector.sh',
      'install-quarantine.sh',
    ]) {
      final source = File(
        'openwrt-setup/standalone/$installer',
      ).readAsStringSync();
      for (final interval in ['1min', '5min', '1hr']) {
        expect(
          source,
          contains('require_file "\$FILES_DIR/Openwalla-$interval-run.sh"'),
        );
        expect(
          source,
          contains(
            'install_file "\$FILES_DIR/Openwalla-$interval-run.sh" /usr/bin/Openwalla-$interval-run.sh 0755',
          ),
        );
        expect(
          source,
          contains('/usr/bin/Openwalla-$interval-run.sh install-cron'),
        );
      }
    }
    final updater = File(
      'openwrt-setup/openwalla-components.sh',
    ).readAsStringSync();
    expect(
      updater,
      contains(
        'files/Openwalla-5min-run.sh)\n\t\t\t[ -x /usr/bin/openwalla-devices-collector ] || \\\n\t\t\t\t[ -x /usr/bin/openwalla-netify-collector ] || return 0',
      ),
    );
    final uninstall = File(
      'openwrt-setup/setup-openwrt-router.sh',
    ).readAsStringSync();
    expect(
      uninstall,
      isNot(contains('remove_cron_marker "OPENWALLA_5MIN_RUN"')),
    );
    expect(uninstall, isNot(contains('rm -f /usr/bin/Openwalla-5min-run.sh')));
  });

  test(
    'cron installation is idempotent and preserves unrelated entries',
    () async {
      await File('${root.path}/crontab').writeAsString('0 * * * * keep-me\n');
      expect((await run('install-cron')).exitCode, 0);
      expect((await run('install-cron')).exitCode, 0);
      final cron = await File('${root.path}/crontab').readAsString();
      expect(cron, contains('0 * * * * keep-me\n'));
      expect('OPENWALLA_5MIN_RUN'.allMatches(cron).length, 1);
      expect(cron, contains('*/5 * * * *'));
    },
  );
}
