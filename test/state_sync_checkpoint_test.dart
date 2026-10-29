import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late String functions;
  late String dispatch;
  late String db;
  late String checkpoint;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('state-sync-test-');
    db = '${directory.path}/live.sqlite';
    checkpoint = '${directory.path}/saved.sqlite';
    final source = await File(
      'openwrt-setup/files/openwalla-state-sync.sh',
    ).readAsString();
    functions = source.substring(
      source.indexOf('uci_get()'),
      source.indexOf('case "\${1:-}"'),
    );
    dispatch = source.substring(source.indexOf('case "\${1:-}"'));
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<ProcessResult> run(String command) => Process.run(
    '/bin/sh',
    ['-c', '$functions\n$command'],
    environment: {'SRC': db, 'DST': checkpoint},
  );

  test('SQLite online backup includes committed WAL data and is valid', () async {
    final writer = await Process.start('/usr/bin/sqlite3', [db]);
    final stdout = writer.stdout.drain<void>();
    final stderr = writer.stderr.drain<void>();
    try {
      writer.stdin.writeln(
        "PRAGMA journal_mode=WAL; CREATE TABLE history(value); INSERT INTO history VALUES ('latest');",
      );
      await writer.stdin.flush();
      for (var i = 0; i < 100; i++) {
        if (await File('$db-wal').exists()) {
          final read = await Process.run('/usr/bin/sqlite3', [
            db,
            'SELECT value FROM history;',
          ]);
          if (read.stdout == 'latest\n') break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(await File('$db-wal').exists(), isTrue);
      final result = await run('save_sqlite "\$SRC" "\$DST"');
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final saved = await Process.run('/usr/bin/sqlite3', [
        checkpoint,
        'PRAGMA quick_check; SELECT value FROM history;',
      ]);
      expect(saved.stdout, 'ok\nlatest\n');
    } finally {
      await writer.stdin.close();
      await writer.exitCode;
      await Future.wait([stdout, stderr]);
    }
  });

  test('corrupt source cannot replace a previous checkpoint', () async {
    await File(db).writeAsString('not a database');
    await File(checkpoint).writeAsString('previous checkpoint');
    final result = await run('save_sqlite "\$SRC" "\$DST"');
    expect(result.exitCode, isNot(0));
    expect(await File(checkpoint).readAsString(), 'previous checkpoint');
  });

  test('vnStat SQLite snapshots exclude stale WAL sidecars', () async {
    final src = Directory('${directory.path}/vnstat');
    final dst = Directory('${directory.path}/vnstat-saved');
    await src.create();
    await dst.create();
    final created = await Process.run('/usr/bin/sqlite3', [
      '${src.path}/vnstat.db',
      "CREATE TABLE usage(value); INSERT INTO usage VALUES ('latest');",
    ]);
    expect(created.exitCode, 0);
    await File('${dst.path}/vnstat.db-wal').writeAsString('obsolete');
    final result = await run('save_vnstat_tree "${src.path}" "${dst.path}"');
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(await File('${dst.path}/vnstat.db-wal').exists(), isFalse);
    final saved = await Process.run('/usr/bin/sqlite3', [
      '${dst.path}/vnstat.db',
      'SELECT value FROM usage;',
    ]);
    expect(saved.stdout, 'latest\n');
  });

  test(
    'copy failures propagate instead of reporting successful saves',
    () async {
      await File(db).writeAsString('data');
      final result = await run('cp() { return 1; }; save_copy "\$SRC" "\$DST"');
      expect(result.exitCode, isNot(0));
      expect(await File(checkpoint).exists(), isFalse);
    },
  );

  test('failed checkpoint produces no reboot acknowledgement', () async {
    final result = await run(
      'save_state() { return 1; }; set -- save-for-reboot; $dispatch',
    );
    expect(result.exitCode, isNot(0));
    expect(result.stdout, isNot(contains('OPENWALLA_STATE_SAVED')));
  });

  test('acknowledgement is emitted only after successful checkpoint', () async {
    final result = await run(
      'save_state() { echo SAVED; }; set -- save-for-reboot; $dispatch',
    );
    expect(result.exitCode, 0);
    expect(result.stdout, 'SAVED\nOPENWALLA_STATE_SAVED\n');
  });

  test(
    'checkpoint failure stops before publishing a new save timestamp',
    () async {
      final result = await run('''
STATE_TS_FILE="\$DST.last"
read_state_dir() { echo /overlay/test-state-sync; }
mkdir() { return 0; }
cd() { return 0; }
pwd() { echo /overlay/test-state-sync; }
save_sqlite() { echo BACKUP_FAILED >&2; return 1; }
save_state
result=\$?
[ "\$result" -ne 0 ] && [ ! -f "\$STATE_TS_FILE" ]
''');
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stderr, contains('BACKUP_FAILED'));
    },
  );
}
