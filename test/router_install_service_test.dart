import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/router_install_service.dart';
import 'package:openwalla/services/ssh_service.dart';

void main() {
  String? pending;
  late List<String> commands;
  late List<String?> bodies;
  late Future<SshCommandResult> Function(String, {String? stdin}) execute;

  RouterInstallService service({int retries = 3}) => RouterInstallService(
    execute: (command, {stdin}) => execute(command, stdin: stdin),
    readPending: () async => pending,
    writePending: (value) async {
      pending = value;
    },
    loadWorker: () async => '#!/bin/sh\necho worker\n',
    pollInterval: Duration.zero,
    retryLimit: retries,
  );

  SshCommandResult response(String state, {int? exitCode, String log = ''}) {
    final id = (jsonDecode(pending!) as Map)['id'];
    return SshCommandResult(
      output:
          '${jsonEncode({'id': id, 'state': state, 'exit_code': exitCode})}\n$log',
      exitCode: 0,
    );
  }

  setUp(() {
    pending = null;
    commands = [];
    bodies = [];
  });

  test(
    'starts once and drains logs using line offsets before completing',
    () async {
      execute = (command, {stdin}) async {
        commands.add(command);
        bodies.add(stdin);
        if (stdin != null) {
          return SshCommandResult(
            output: 'OPENWALLA_JOB|${(jsonDecode(pending!) as Map)['id']}',
            exitCode: 0,
          );
        }
        return command.contains(" 0;")
            ? response('completed', exitCode: 0, log: 'installed\n')
            : response('completed', exitCode: 0);
      };
      final chunks = <String>[];
      expect(
        await service().run('sh installer.sh', onOutput: chunks.add),
        'installed',
      );
      expect(bodies.whereType<String>().single, 'sh installer.sh\n');
      expect(commands.last, contains(' 1;'));
      expect(commands.first, isNot(contains('base64')));
      expect(commands.first, contains("<<'OPENWALLA_WORKER_"));
      expect(chunks.join(), contains('installed'));
      expect(pending, isNull);
    },
  );

  test('a different selection cannot replace a running installation', () async {
    pending = jsonEncode({'id': 'saved-job', 'command': 'old-installer'});
    execute = (command, {stdin}) async {
      expect(stdin, isNull);
      return response('running');
    };
    await expectLater(
      service().run('new-installer'),
      throwsA(isA<RouterInstallException>()),
    );
    expect(pending, contains('old-installer'));
  });

  test(
    'a finished previous selection does not prevent a new installation',
    () async {
      pending = jsonEncode({'id': 'saved-job', 'command': 'old-installer'});
      var starts = 0;
      execute = (command, {stdin}) async {
        if (stdin != null) {
          starts++;
          expect(stdin, 'new-installer\n');
          return SshCommandResult(
            output: 'OPENWALLA_JOB|${(jsonDecode(pending!) as Map)['id']}',
            exitCode: 0,
          );
        }
        return response('completed', exitCode: 0);
      };
      await service().run('new-installer');
      expect(starts, 1);
      expect(pending, isNull);
    },
  );

  test('Unicode and whitespace in complete log lines remain intact', () async {
    pending = jsonEncode({'id': 'saved-job', 'command': 'installer'});
    var calls = 0;
    execute = (command, {stdin}) async {
      if (!command.contains('status-lines')) {
        return const SshCommandResult(output: '', exitCode: 0);
      }
      calls++;
      return switch (calls) {
        1 => response('running', log: '  caf\u00e9\n\n'),
        2 => response('completed', exitCode: 0, log: '  installed\n'),
        _ => response('completed', exitCode: 0),
      };
    };
    expect(await service().run('installer'), '  caf\u00e9\n\n  installed');
  });

  test(
    'lost launch response retries the same job ID rather than a new install',
    () async {
      var starts = 0;
      final ids = <String>{};
      execute = (command, {stdin}) async {
        if (stdin != null) {
          starts++;
          final id = (jsonDecode(pending!) as Map)['id'] as String;
          ids.add(id);
          if (starts == 1) throw StateError('Disconnected after launch');
          return SshCommandResult(output: 'OPENWALLA_JOB|$id', exitCode: 0);
        }
        return response('completed', exitCode: 0);
      };
      await service().run('installer');
      expect(starts, 2);
      expect(ids.length, 1);
    },
  );

  test(
    'persisted jobs reconnect without launching another installer',
    () async {
      pending = jsonEncode({'id': 'saved-job', 'command': 'installer'});
      var calls = 0;
      execute = (command, {stdin}) async {
        expect(stdin, isNull);
        calls++;
        if (calls == 1) throw StateError('Phone was asleep');
        return response('completed', exitCode: 0);
      };
      await service().run('installer');
      expect(calls, 3);
      expect(pending, isNull);
    },
  );

  test(
    'monitoring failure retains pending identity for a later reconnect',
    () async {
      pending = jsonEncode({'id': 'saved-job', 'command': 'installer'});
      execute = (command, {stdin}) async => throw StateError('Offline');
      await expectLater(
        service(retries: 2).run('installer'),
        throwsA(isA<RouterInstallException>()),
      );
      expect(pending, contains('saved-job'));
    },
  );

  test(
    'failure is based on status rather than a printed success message',
    () async {
      pending = jsonEncode({'id': 'saved-job', 'command': 'installer'});
      execute = (command, {stdin}) async => response('failed', exitCode: 7);
      await expectLater(
        service().run('installer'),
        throwsA(isA<RouterInstallException>()),
      );
      expect(pending, isNull);
    },
  );

  test(
    'missing job after a router reboot is not automatically restarted',
    () async {
      pending = jsonEncode({'id': 'saved-job', 'command': 'installer'});
      execute = (command, {stdin}) async {
        expect(stdin, isNull);
        if (!command.contains('status-lines')) {
          return const SshCommandResult(output: '', exitCode: 0);
        }
        return const SshCommandResult(output: 'missing', exitCode: 4);
      };
      await expectLater(
        service().run('installer'),
        throwsA(isA<RouterInstallException>()),
      );
      expect(pending, isNull);
    },
  );
}
