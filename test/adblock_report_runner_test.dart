import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File(
    'openwrt-setup/files/Openwalla-1min-run.sh',
  ).absolute.path;
  late Directory root;
  late Map<String, String> env;
  Future<void> executable(String path, String source) async {
    final file = File('${root.path}/$path');
    await file.writeAsString('#!/bin/sh\n$source');
    expect((await Process.run('chmod', ['755', file.path])).exitCode, 0);
  }

  Future<ProcessResult> run() => Process.run('sh', [script], environment: env);
  Future<String> snapshot() =>
      File('${root.path}/run/adblock-report.json').readAsString();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('adblock-runner-');
    for (final dir in ['bin', 'init', 'proc', 'run', 'capture']) {
      await Directory('${root.path}/$dir').create();
    }
    env = {
      'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
      'FAKE_ROOT': root.path,
      'OPENWALLA_RUNTIME_DIR': '${root.path}/run',
      'OPENWALLA_INIT_DIR': '${root.path}/init',
      'OPENWALLA_PROC_DIR': '${root.path}/proc',
      'OPENWALLA_DEVICES_PING': '${root.path}/missing-ping',
    };
    await File('${root.path}/proc/cpuinfo').writeAsString('processor : 0\n');
    await File('${root.path}/capture/adb_report.pcap0').writeAsString('');
    await File('${root.path}/proc/loadavg').writeAsString('0.1 0.1 0.1\n');
    await File(
      '${root.path}/proc/meminfo',
    ).writeAsString('MemAvailable: 64000 kB\n');
    await File(
      '${root.path}/run/adblock-report.json',
    ).writeAsString('previous report');
    await executable('bin/uci', r'''
case "$*" in
  *adblock.global.adb_enabled) echo "${ADBLOCK_ENABLED:-1}" ;;
  *adblock.global.adb_report) echo "${REPORT_ENABLED:-1}" ;;
  *adblock.global.adb_reportdir) echo "$FAKE_ROOT/capture" ;;
  *) exit 1 ;;
esac
''');
    await executable('bin/tcpdump', 'exit 0\n');
    await executable('bin/jsonfilter', r'''
[ "${BAD_JSON:-0}" != 1 ] || exit 1
echo 20
''');
    await executable('bin/timeout', r'''
echo "timeout $1" >>"$FAKE_ROOT/actions"
shift
exec "$@"
''');
    await executable('init/adblock', r'''
echo "$*" >>"$FAKE_ROOT/actions"
if [ "$1" = reload ]; then touch "$FAKE_ROOT/capture/adb_report.pcap0"; exit 0; fi
if [ "$2" = gen ]; then exit "${GEN_FAIL:-0}"; fi
[ "${EMPTY_JSON:-0}" != 1 ] || exit 0
printf '[{"total":"20","blocked":"3","requests":[]}]\n'
''');
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'publishes a timestamped cache with bounded requests when Netify is absent',
    () async {
      expect((await run()).exitCode, 0);
      final decoded = jsonDecode(await snapshot()) as Map;
      expect(decoded['generated_at'], isA<int>());
      expect(decoded['data'][0]['total'], '20');
      final actions = await File('${root.path}/actions').readAsString();
      expect(actions, contains('report gen 10 1000'));
      expect(actions, contains('report json'));
      expect(actions, contains('timeout 45'));
      expect(actions, contains('timeout 10'));
      expect(
        await Directory('${root.path}/run')
            .list()
            .where((entry) => entry.path.contains('.adblock-report.'))
            .isEmpty,
        isTrue,
      );
    },
  );
  test(
    'disabled reporting or AdBlock preserves the existing snapshot',
    () async {
      for (final key in ['ADBLOCK_ENABLED', 'REPORT_ENABLED']) {
        env[key] = '0';
        expect((await run()).exitCode, 0);
        expect(await snapshot(), 'previous report');
        env.remove(key);
      }
      expect(await File('${root.path}/actions').exists(), isFalse);
    },
  );
  test('busy router and low available memory skip work', () async {
    await File('${root.path}/proc/loadavg').writeAsString('2.5 1 1\n');
    expect((await run()).exitCode, 0);
    expect(await snapshot(), 'previous report');
    await File('${root.path}/proc/loadavg').writeAsString('0.1 1 1\n');
    await File(
      '${root.path}/proc/meminfo',
    ).writeAsString('MemAvailable: 1000 kB\n');
    expect((await run()).exitCode, 0);
    expect(await File('${root.path}/actions').exists(), isFalse);
  });
  test(
    'failed generation or JSON validation does not replace good data',
    () async {
      env['GEN_FAIL'] = '1';
      expect((await run()).exitCode, 1);
      expect(await snapshot(), 'previous report');
      env.remove('GEN_FAIL');
      env['BAD_JSON'] = '1';
      expect((await run()).exitCode, 1);
      expect(await snapshot(), 'previous report');
    },
  );
  test('shared lock prevents overlapping generation', () async {
    await Directory('${root.path}/run/adblock-report.lock').create();
    expect((await run()).exitCode, 0);
    expect(await snapshot(), 'previous report');
    expect(await File('${root.path}/actions').exists(), isFalse);
  });
  test('AdBlock installer deploys shared runner and capture dependency', () {
    final source = File(
      'openwrt-setup/standalone/install-adblock.sh',
    ).readAsStringSync();
    expect(source, contains('install_pkg_if_available "tcpdump-mini"'));
    expect(
      source,
      contains(
        'install_file "\$FILES_DIR/Openwalla-5min-run.sh" /usr/bin/Openwalla-5min-run.sh 0755',
      ),
    );
    expect(source, contains('/usr/bin/Openwalla-5min-run.sh install-cron'));
    expect(
      source,
      contains(
        'install_file "\$FILES_DIR/Openwalla-1min-run.sh" /usr/bin/Openwalla-1min-run.sh 0755',
      ),
    );
    expect(source, contains('/usr/bin/Openwalla-1min-run.sh install-cron'));
    expect(source, isNot(contains('adb_report "1"')));
  });
  test(
    'report log distinguishes generation failure from empty capture',
    () async {
      env['GEN_FAIL'] = '1';
      expect((await run()).exitCode, 1);
      expect(
        await File('${root.path}/run/adblock-report.last.log').readAsString(),
        contains('Generation failed or timed out'),
      );
      env.remove('GEN_FAIL');
      env['EMPTY_JSON'] = '1';
      expect((await run()).exitCode, 0);
      expect(
        await File('${root.path}/run/adblock-report.last.log').readAsString(),
        contains('No native report yet'),
      );
      expect(await snapshot(), 'previous report');
    },
  );
  test('report is generated even if client ping fails', () async {
    await executable('bin/ping-task', 'exit 1\n');
    env['OPENWALLA_DEVICES_PING'] = '${root.path}/bin/ping-task';
    expect((await run()).exitCode, 1);
    expect((jsonDecode(await snapshot()) as Map)['generated_at'], isA<int>());
  });
  test('five-minute runner no longer generates duplicate reports', () {
    final source = File(
      'openwrt-setup/files/Openwalla-5min-run.sh',
    ).readAsStringSync();
    expect(source, isNot(contains('update_adblock_report')));
  });
  test(
    'missing capture directory after reboot is recreated and capture requested',
    () async {
      await Directory('${root.path}/capture').delete(recursive: true);
      expect((await run()).exitCode, 0);
      expect(
        await File('${root.path}/capture/adb_report.pcap0').exists(),
        isTrue,
      );
      expect(await snapshot(), 'previous report');
      expect(
        await File('${root.path}/actions').readAsString(),
        contains('reload'),
      );
      expect((await run()).exitCode, 0);
      expect((jsonDecode(await snapshot()) as Map)['generated_at'], isA<int>());
    },
  );
}
