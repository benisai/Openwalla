import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  late Directory root;
  late Directory proc;
  late Directory bin;

  Future<void> addProcess(
    int pid,
    String name,
    int? rss,
    int? virtual,
    List<String> args,
  ) async {
    final dir = await Directory('${proc.path}/$pid').create();
    await File('${dir.path}/status').writeAsString(
      'Name:\t$name\n'
      '${rss == null ? '' : 'VmRSS:\t$rss kB\n'}'
      '${virtual == null ? '' : 'VmSize:\t$virtual kB\n'}',
    );
    await File(
      '${dir.path}/cmdline',
    ).writeAsString(args.isEmpty ? '' : '${args.join('\x00')}\x00');
  }

  Future<ProcessResult> run(String command) => Process.run(
    '/bin/sh',
    ['-c', command.replaceFirst('/proc/', '${proc.path}/')],
    environment: {'PATH': '${bin.path}:/usr/bin:/bin'},
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('openwalla-memory-');
    proc = await Directory('${root.path}/proc').create();
    bin = await Directory('${root.path}/bin').create();
    // Emulate a minimal BusyBox sort: reject the optional -t/-k flags.
    await File('${bin.path}/sort').writeAsString(r'''#!/bin/sh
if [ "$#" != 1 ] || [ "$1" != "-nr" ]; then
  echo 'sort: unsupported option' >&2
  exit 2
fi
exec /usr/bin/sort -nr
''');
    final chmod = await Process.run('chmod', ['+x', '${bin.path}/sort']);
    expect(chmod.exitCode, 0);
    await addProcess(10, 'small', 9, 100, ['/usr/sbin/small']);
    await addProcess(20, 'medium', 100, 400, ['/usr/sbin/medium', '--flag']);
    await addProcess(30, 'large', 2048, 8192, ['/usr/sbin/large', 'a|b']);
    await addProcess(40, 'kworker', null, null, []);
  });

  tearDown(() async => root.delete(recursive: true));

  test(
    'basic sort ranks process RSS numerically, not alphabetically',
    () async {
      final result = await run(AppState.buildProcessMemoryCommand(10));
      expect(result.exitCode, 0);
      expect(result.stderr, isEmpty);
      final lines = result.stdout.toString().trim().split('\n');
      expect(lines, [
        '2048|8192|30|large|/usr/sbin/large a|b',
        '100|400|20|medium|/usr/sbin/medium --flag',
        '9|100|10|small|/usr/sbin/small',
        '0|0|40|kworker|[kworker]',
      ]);
    },
  );

  test('old extended sort flags reproduce the empty result', () async {
    final oldCommand = AppState.buildProcessMemoryCommand(
      10,
    ).replaceFirst('sort -nr', 'sort -t "|" -k1,1nr');
    final result = await run(oldCommand);
    expect(result.stdout.toString().trim(), isEmpty);
    expect(result.stderr, contains('unsupported option'));
  });

  test('limit selects highest RSS entries after sorting', () async {
    final result = await run(AppState.buildProcessMemoryCommand(2));
    final lines = result.stdout.toString().trim().split('\n');
    expect(lines.length, 2);
    expect(lines.first, startsWith('2048|'));
    expect(lines.last, startsWith('100|'));
  });

  test('limits are clamped to the existing 1 through 25 range', () {
    expect(AppState.buildProcessMemoryCommand(0), endsWith('head -n 1'));
    expect(AppState.buildProcessMemoryCommand(100), endsWith('head -n 25'));
  });
}
