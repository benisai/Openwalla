import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

import 'ssh_service.dart';

typedef InstallCommand =
    Future<SshCommandResult> Function(String command, {String? stdin});

class RouterInstallException implements Exception {
  final String message;
  const RouterInstallException(this.message);
  @override
  String toString() => message;
}

class RouterInstallService {
  RouterInstallService({
    required this.execute,
    required this.readPending,
    required this.writePending,
    this.loadWorker,
    this.pollInterval = const Duration(seconds: 3),
    this.retryLimit = 40,
  });

  final InstallCommand execute;
  final Future<String?> Function() readPending;
  final Future<void> Function(String?) writePending;
  final Future<String> Function()? loadWorker;
  final Duration pollInterval;
  final int retryLimit;
  static const workerPath = '/tmp/openwalla/openwalla-install-job.sh';

  Future<SshCommandResult> _request(String command, {String? stdin}) =>
      execute(command, stdin: stdin).timeout(const Duration(seconds: 25));

  Future<String> run(String command, {void Function(String)? onOutput}) async {
    final saved = await readPending();
    var pending = saved == null
        ? null
        : jsonDecode(saved) as Map<String, dynamic>;
    if (pending != null &&
        !RegExp(
          r'^[a-zA-Z0-9_-]{1,80}$',
        ).hasMatch(pending['id'] as String? ?? '')) {
      throw const RouterInstallException('Invalid saved installation job.');
    }
    if (pending != null && pending['command'] != command) {
      final previous = await _request(
        "if [ -f '$workerPath' ]; then sh '$workerPath' status '${pending['id']}' 0; else exit 4; fi",
      );
      if (previous.exitCode == 4) {
        await writePending(null);
        throw const RouterInstallException(
          'Previous installation state is missing. The router may have restarted; review it before retrying.',
        );
      }
      if (previous.exitCode != 0) {
        throw const RouterInstallException(
          'Unable to check the previous installation. Reconnect to the router and retry.',
        );
      }
      final status =
          jsonDecode(previous.output.split('\n').first) as Map<String, dynamic>;
      if (!['completed', 'failed', 'interrupted'].contains(status['state'])) {
        throw RouterInstallException(
          'Installation ${pending['id']} is still running. Resume the same selection before starting another.',
        );
      }
      await writePending(null);
      pending = null;
    }
    final id =
        pending?['id'] as String? ??
        'job-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      throw const RouterInstallException('Invalid saved installation job.');
    }
    // Save before submission: a lost launch response must reuse the same ID.
    await writePending(jsonEncode({'id': id, 'command': command}));
    final worker =
        await (loadWorker?.call() ??
            rootBundle.loadString(
              'openwrt-setup/files/openwalla-install-job.sh',
            ));
    final encoded = base64Encode(utf8.encode(worker));
    final bootstrap =
        '''
umask 077
mkdir -p /tmp/openwalla || exit 1
base64 -d > '$workerPath.$id' <<'OPENWALLA_WORKER'
$encoded
OPENWALLA_WORKER
chmod 700 '$workerPath.$id' && mv '$workerPath.$id' '$workerPath' || exit 1
sh '$workerPath' start '$id'
''';
    onOutput?.call(
      'Installation job: $id\nRouter log: /tmp/openwalla/install/$id/install.log\n',
    );
    var submitted = pending != null;
    var failures = 0;
    var offset = 0;
    var reconnecting = false;
    final output = StringBuffer();
    final decoder = const Utf8Decoder(
      allowMalformed: true,
    ).startChunkedConversion(StringConversionSink.fromStringSink(output));
    var decoderClosed = false;
    var emittedLength = 0;
    void emit() {
      final text = output.toString();
      if (text.length > emittedLength) {
        onOutput?.call(text.substring(emittedLength));
        emittedLength = text.length;
      }
    }

    try {
      while (true) {
        try {
          if (!submitted) {
            final start = await _request(bootstrap, stdin: '$command\n');
            if (start.exitCode != 0 ||
                !start.output.contains('OPENWALLA_JOB|$id')) {
              await writePending(null);
              throw RouterInstallException(
                'Could not start installation: ${start.output}',
              );
            }
            submitted = true;
          }
          final response = await _request(
            "if [ -f '$workerPath' ]; then sh '$workerPath' status '$id' $offset; else exit 4; fi",
          );
          if (response.exitCode == 4) {
            await writePending(null);
            throw const RouterInstallException(
              'Installation job is missing. The router may have restarted; review the router before retrying.',
            );
          }
          if (response.exitCode != 0) {
            throw StateError(response.output);
          }
          final newline = response.output.indexOf('\n');
          if (newline < 0) throw const FormatException('Missing job status');
          final status =
              jsonDecode(response.output.substring(0, newline))
                  as Map<String, dynamic>;
          if (status['id'] != id) {
            throw const FormatException('Wrong install job');
          }
          final bytes = base64Decode(
            response.output.substring(newline + 1).trim(),
          );
          decoder.add(bytes);
          offset += bytes.length;
          emit();
          failures = 0;
          reconnecting = false;
          final state = status['state'];
          if (state != 'starting' && state != 'running') {
            // Drain remaining output before returning the terminal result.
            if (bytes.isNotEmpty) continue;
            decoder.close();
            decoderClosed = true;
            emit();
            await writePending(null);
            if (state == 'completed' && status['exit_code'] == 0) {
              return output.toString().trimRight();
            }
            throw RouterInstallException(
              'Router installation $state (exit code ${status['exit_code']}).\n\n$output',
            );
          }
        } on RouterInstallException {
          rethrow;
        } catch (_) {
          failures++;
          // A request may have reached the router even when its reply was lost.
          // Retry start with the SAME ID; the router treats that as a resume.
          if (!reconnecting) {
            onOutput?.call(
              '\nConnection lost. The router job is independent; reconnecting...\n',
            );
            reconnecting = true;
          }
          if (failures >= retryLimit) {
            throw const RouterInstallException(
              'Unable to monitor the router. Installation may still be running. Reopen this installation with the same selection to resume its log; do not manually start another installer.',
            );
          }
        }
        await Future<void>.delayed(pollInterval);
      }
    } finally {
      // Closing the monitor never sends a signal to the router worker.
      if (!decoderClosed) decoder.close();
    }
  }
}
