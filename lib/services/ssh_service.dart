import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

class SshCommandResult {
  final String output;
  final int? exitCode;

  const SshCommandResult({required this.output, required this.exitCode});
}

class SshService {
  Future<SshShellConnection> connectShell({
    required String host,
    required String username,
    required String password,
    int port = 22,
    Duration timeout = const Duration(seconds: 18),
  }) async {
    final target = _parseTarget(host, port);
    final socket = await SSHSocket.connect(
      target.host,
      target.port,
      timeout: timeout,
    );
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    try {
      final session = await client.shell(
        pty: const SSHPtyConfig(type: 'xterm-256color', width: 120, height: 40),
      );
      return SshShellConnection(client, session);
    } catch (_) {
      unawaited(client.close());
      rethrow;
    }
  }

  Future<SshCommandResult> runCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    String? stdin,
    int port = 22,
    Duration timeout = const Duration(seconds: 18),
    void Function(String chunk)? onOutput,
  }) async {
    final target = _parseTarget(host, port);
    SSHClient? client;

    final socket = await SSHSocket.connect(
      target.host,
      target.port,
      timeout: timeout,
    );
    client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );

    try {
      final session = await client.execute(command);
      final output = StringBuffer();

      void append(String chunk) {
        output.write(chunk);
        onOutput?.call(chunk);
      }

      final stdoutDone = utf8.decoder
          .bind(session.stdout)
          .listen(append)
          .asFuture<void>();
      final stderrDone = utf8.decoder
          .bind(session.stderr)
          .listen(append)
          .asFuture<void>();

      if (stdin != null) {
        session.stdin.add(Uint8List.fromList(utf8.encode(stdin)));
        await session.stdin.close();
      }

      await Future.wait([stdoutDone, stderrDone], eagerError: true);
      await session.done;

      final exitCode = session.exitCode;
      if (exitCode != null && exitCode != 0) {
        append('\nExit code: $exitCode');
      }

      return SshCommandResult(output: output.toString(), exitCode: exitCode);
    } finally {
      unawaited(client.close());
      unawaited(client.done.catchError((_) {}));
    }
  }

  _SshTarget _parseTarget(String rawHost, int defaultPort) {
    var value = rawHost.trim();
    if (value.isEmpty) {
      throw ArgumentError('SSH host cannot be empty');
    }

    if (value.contains('://')) {
      final uri = Uri.parse(value);
      return _SshTarget(uri.host, defaultPort);
    }

    value = value.split('/').first;
    if (value.startsWith('[')) {
      final end = value.indexOf(']');
      if (end > 0) {
        final host = value.substring(1, end);
        final portText = value.substring(end + 1);
        final parsedPort = portText.startsWith(':')
            ? int.tryParse(portText.substring(1))
            : null;
        return _SshTarget(host, parsedPort ?? defaultPort);
      }
    }

    final colonCount = ':'.allMatches(value).length;
    if (colonCount == 1) {
      final parts = value.split(':');
      final parsedPort = int.tryParse(parts[1]);
      if (parsedPort != null) {
        return _SshTarget(parts[0], parsedPort);
      }
    }

    return _SshTarget(value, defaultPort);
  }
}

class SshShellConnection {
  SshShellConnection(this._client, this._session);

  final SSHClient _client;
  final SSHSession _session;
  bool _closed = false;

  Stream<String> get stdout => utf8.decoder.bind(_session.stdout);
  Stream<String> get stderr => utf8.decoder.bind(_session.stderr);
  Future<void> get done => _session.done;

  void write(String value) {
    if (_closed) return;
    _session.stdin.add(Uint8List.fromList(utf8.encode(value)));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _session.close();
    await _client.close();
  }
}

class _SshTarget {
  final String host;
  final int port;

  const _SshTarget(this.host, this.port);
}
