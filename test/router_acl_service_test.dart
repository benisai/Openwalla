import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/router_acl_service.dart';
import 'package:openwalla/services/ssh_service.dart';

class _FakeSshService extends SshService {
  _FakeSshService(this.result, {this.error});

  final SshCommandResult result;
  final Object? error;
  String? command;

  @override
  Future<SshCommandResult> runCommand({
    required String host,
    required String username,
    required String password,
    required String command,
    String? stdin,
    int port = 22,
    Duration timeout = const Duration(seconds: 18),
    Duration? executionTimeout,
    void Function(String chunk)? onOutput,
  }) async {
    this.command = command;
    if (error case final error?) throw error;
    return result;
  }
}

void main() {
  test(
    'recognizes an installed ACL through the background SSH probe',
    () async {
      final ssh = _FakeSshService(
        const SshCommandResult(output: 'OPENWALLA_ACL_PRESENT\n', exitCode: 0),
      );

      final status = await RouterAclService(
        sshService: ssh,
      ).check(host: '192.168.1.1', username: 'root', password: 'secret');

      expect(status, RouterAclStatus.present);
      expect(ssh.command, contains(RouterAclService.aclRouterPath));
    },
  );

  test('recognizes a confirmed missing ACL', () async {
    final ssh = _FakeSshService(
      const SshCommandResult(output: 'OPENWALLA_ACL_MISSING\n', exitCode: 0),
    );

    final status = await RouterAclService(
      sshService: ssh,
    ).check(host: '192.168.1.1', username: 'root', password: '');

    expect(status, RouterAclStatus.missing);
  });

  test('keeps SSH failures quiet and reports an unavailable check', () async {
    final ssh = _FakeSshService(
      const SshCommandResult(output: '', exitCode: null),
      error: StateError('SSH disabled'),
    );

    final status = await RouterAclService(
      sshService: ssh,
    ).check(host: '192.168.1.1', username: 'root', password: 'secret');

    expect(status, RouterAclStatus.unavailable);
  });

  test('removes the LuCI web port before an automatic SSH check', () {
    expect(routerAclSshHost('192.168.1.1:8443'), '192.168.1.1');
    expect(routerAclSshHost('https://router.example:8443'), 'router.example');
    expect(routerAclSshHost('[fd00::1]:8443'), 'fd00::1');
  });
}
