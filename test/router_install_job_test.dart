import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Map<String, String> env;
  final helper = File(
    'openwrt-setup/files/openwalla-install-job.sh',
  ).absolute.path;

  Future<ProcessResult> invoke(List<String> args) =>
      Process.run('sh', [helper, ...args], environment: env);

  Future<String> start(String id, String script) async {
    final process = await Process.start('sh', [
      helper,
      'start',
      id,
    ], environment: env);
    process.stdin.write(script);
    await process.stdin.close();
    final output = process.stdout.transform(utf8.decoder).join();
    final error = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode.timeout(const Duration(seconds: 3));
    expect(code, 0, reason: await error);
    return output;
  }

  Future<Map<String, dynamic>> status(String id) async {
    final result = await invoke(['status', id, '0']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return jsonDecode(result.stdout.toString().split('\n').first)
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> finish(String id) async {
    for (var i = 0; i < 150; i++) {
      final value = await status(id);
      if (!['starting', 'running'].contains(value['state'])) return value;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Worker did not finish');
  }

  Future<String> log(String id) async {
    final result = await invoke(['status', id, '0']);
    final lines = result.stdout.toString().split('\n');
    return utf8.decode(base64Decode(lines[1]));
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openwalla-job-test-');
    env = {
      'OPENWALLA_INSTALL_JOBS_DIR': '${root.path}/jobs',
      'OPENWALLA_RUNTIME_DIR': '${root.path}/runtime',
      'OPENWALLA_INSTALL_LOG_DIR': '${root.path}/persistent-logs',
    };
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'worker outlives launch and records its real exit status and log',
    () async {
      expect(
        await start('survive', 'sleep 0.3\necho installed\n'),
        contains('OPENWALLA_JOB|survive'),
      );
      final result = await finish('survive');
      expect(result['state'], 'completed');
      expect(result['exit_code'], 0);
      expect(await log('survive'), contains('installed'));
      expect(Directory('${root.path}/jobs/active.lock').existsSync(), isFalse);
    },
  );

  test('a printed success marker cannot hide a failed installer', () async {
    await start('failed', 'echo "[openwalla-setup] Setup complete."\nexit 7\n');
    final result = await finish('failed');
    expect(result['state'], 'failed');
    expect(result['exit_code'], 7);
  });

  test('worker ignores SSH-style hangup signals', () async {
    await start('hangup', 'sleep 0.4\necho survived-hangup\n');
    for (var i = 0; i < 100; i++) {
      if ((await status('hangup'))['state'] == 'running') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final pid = int.parse(
      await File('${root.path}/jobs/hangup/pid').readAsString(),
    );
    Process.killPid(pid, ProcessSignal.sighup);
    expect((await finish('hangup'))['state'], 'completed');
    expect(await log('hangup'), contains('survived-hangup'));
  });

  test(
    'duplicate IDs resume without rerunning and concurrent jobs are rejected',
    () async {
      await start('first', 'sleep 0.4\necho one-run\n');
      final blocked = await invoke([
        'launch',
        'second',
        'echo',
        'must-not-run',
      ]);
      expect(blocked.exitCode, 3);
      await start('first', 'echo must-not-run\n');
      await finish('first');
      await start('first', 'echo must-not-run\n');
      expect('one-run'.allMatches(await log('first')).length, 1);
      expect(await log('first'), isNot(contains('must-not-run')));
    },
  );

  test('abandoned workers become interrupted and release the lock', () async {
    final job = await Directory(
      '${root.path}/jobs/dead',
    ).create(recursive: true);
    await File(
      '${job.path}/status.json',
    ).writeAsString('{"id":"dead","state":"running","exit_code":null}\n');
    await File('${job.path}/pid').writeAsString('99999999');
    await File('${job.path}/started').writeAsString('1');
    await File('${job.path}/install.log').writeAsString('partial install\n');
    await Directory('${root.path}/jobs/active.lock').create();
    await File('${root.path}/jobs/active.lock/owner-dead').writeAsString('');
    expect((await status('dead'))['state'], 'interrupted');
    await start('next', 'echo recovered\n');
    expect((await finish('next'))['state'], 'completed');
  });

  test('a living installer remains locked after its supervisor dies', () async {
    final child = await Process.start('sh', ['-c', 'sleep 0.5']);
    final job = await Directory(
      '${root.path}/jobs/orphan',
    ).create(recursive: true);
    await File(
      '${job.path}/status.json',
    ).writeAsString('{"id":"orphan","state":"running","exit_code":null}\n');
    await File('${job.path}/pid').writeAsString('99999999');
    await File('${job.path}/child-pid').writeAsString('${child.pid}');
    await File('${job.path}/install.log').writeAsString('installing\n');
    await Directory('${root.path}/jobs/active.lock').create();
    await File('${root.path}/jobs/active.lock/owner-orphan').writeAsString('');
    expect((await status('orphan'))['state'], 'running');
    expect((await invoke(['launch', 'other', 'echo', 'bad'])).exitCode, 3);
    await child.exitCode;
    expect((await status('orphan'))['state'], 'interrupted');
  });

  test('launch preserves argv quoting and rejects unsafe IDs', () async {
    final result = await invoke([
      'launch',
      'quoted',
      'printf',
      '%s\n',
      "single'quote",
      'two words',
      '; echo injection',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    await finish('quoted');
    expect(
      await log('quoted'),
      contains("single'quote\ntwo words\n; echo injection"),
    );
    expect((await invoke(['status', '../bad', '0'])).exitCode, 2);
    expect((await invoke(['status', 'quoted', 'bad'])).exitCode, 2);
    expect((await invoke(['status', 'missing', '0'])).exitCode, 4);
  });

  test('log polling supports byte offsets and bounds each response', () async {
    await start(
      'large',
      'awk \'BEGIN {for(i=0;i<70000;i++) printf "x"; print ""}\'\n',
    );
    await finish('large');
    final first = await log('large');
    expect(utf8.encode(first).length, 65536);
    final result = await invoke(['status', 'large', '65536']);
    final next = utf8.decode(
      base64Decode(result.stdout.toString().split('\n')[1]),
    );
    final full = await File(
      '${root.path}/jobs/large/install.log',
    ).readAsString();
    expect('$first$next', full);
  });

  test('all standalone installers inherit opt-in background support', () async {
    final standalone = await Directory(
      '${root.path}/standalone/lib',
    ).create(recursive: true);
    await File(
      'openwrt-setup/standalone/lib/openwalla-standalone-common.sh',
    ).copy('${standalone.path}/openwalla-standalone-common.sh');
    await Directory('${root.path}/files').create();
    await File(helper).copy('${root.path}/files/openwalla-install-job.sh');
    final bin = await Directory('${root.path}/bin').create();
    final id = await File(
      '${bin.path}/id',
    ).writeAsString('#!/bin/sh\necho 0\n');
    await Process.run('chmod', ['755', id.path]);
    final installer = await File('${root.path}/standalone/install-example.sh')
        .writeAsString('''
#!/bin/sh
. "\$(dirname "\$0")/lib/openwalla-standalone-common.sh"
sleep 0.1
echo standalone-installed
''');
    final result = await Process.run(
      'sh',
      [installer.path, '--background'],
      environment: {
        ...env,
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
      },
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final jobId = result.stdout.toString().trim().split('|').last;
    expect((await finish(jobId))['state'], 'completed');
    expect(await log(jobId), contains('standalone-installed'));
  });

  test(
    'Router Setup accepts the same background option before dry-run',
    () async {
      final bin = await Directory('${root.path}/bin').create();
      final wget = await File(
        '${bin.path}/wget',
      ).writeAsString('#!/bin/sh\ncp "\$FAKE_HELPER" "\$2"\n');
      await Process.run('chmod', ['755', wget.path]);
      final result = await Process.run(
        'sh',
        [
          File('openwrt-setup/setup-openwrt-router.sh').absolute.path,
          '--background',
          '--dry-run',
          'standard',
        ],
        environment: {
          ...env,
          'PATH': '${bin.path}:${Platform.environment['PATH']}',
          'FAKE_HELPER': helper,
          'OPENWALLA_INSTALL_LOG_ACTIVE': '1',
        },
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final id = result.stdout.toString().trim().split('|').last;
      expect((await finish(id))['state'], 'completed');
      expect(await log(id), contains('Core router packages'));
    },
  );
}
