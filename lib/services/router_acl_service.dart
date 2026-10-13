import 'package:flutter/services.dart';
import 'package:openwalla/services/ssh_service.dart';

enum RouterAclStatus { present, missing, unavailable }

String routerAclSshHost(String rawAddress) {
  var value = rawAddress.trim();
  if (value.contains('://')) {
    return Uri.tryParse(value)?.host ?? value;
  }
  value = value.split('/').first;
  if (value.startsWith('[')) {
    final end = value.indexOf(']');
    if (end > 0) return value.substring(1, end);
  }
  if (':'.allMatches(value).length == 1) {
    return value.split(':').first;
  }
  return value;
}

class RouterAclService {
  RouterAclService({SshService? sshService})
    : _sshService = sshService ?? SshService();

  static const aclAssetPath = 'openwrt-setup/rpcd-acl.json';
  static const aclRouterPath = '/usr/share/rpcd/acl.d/openwalla.json';

  static const checkCommand =
      '''
if [ -s $aclRouterPath ] && grep -q '"openwalla"' $aclRouterPath 2>/dev/null; then
  echo OPENWALLA_ACL_PRESENT
else
  echo OPENWALLA_ACL_MISSING
fi
''';

  static const installCommand =
      '''
set -e
echo "[openwalla-acl] Installing bundled RPC permissions..."
mkdir -p /usr/share/rpcd/acl.d
cat > $aclRouterPath
chmod 0644 $aclRouterPath
test -s $aclRouterPath
if [ -x /etc/init.d/rpcd ]; then
  /etc/init.d/rpcd restart
fi
echo "[openwalla-acl] Install complete. Return to Openwalla and connect again."
''';

  final SshService _sshService;

  Future<RouterAclStatus> check({
    required String host,
    required String username,
    required String password,
    int port = 22,
  }) async {
    try {
      final result = await _sshService.runCommand(
        host: host,
        port: port,
        username: username.trim().isEmpty ? 'root' : username,
        password: password,
        command: checkCommand,
        timeout: const Duration(seconds: 8),
      );
      if (result.output.contains('OPENWALLA_ACL_PRESENT')) {
        return RouterAclStatus.present;
      }
      if (result.output.contains('OPENWALLA_ACL_MISSING')) {
        return RouterAclStatus.missing;
      }
    } catch (_) {
      // SSH may be disabled or use separate credentials. Login should continue.
    }
    return RouterAclStatus.unavailable;
  }

  Future<SshCommandResult> install({
    required String host,
    required String username,
    required String password,
    int port = 22,
    void Function(String chunk)? onOutput,
  }) async {
    final acl = await rootBundle.loadString(aclAssetPath);
    return _sshService.runCommand(
      host: host,
      port: port,
      username: username.trim().isEmpty ? 'root' : username,
      password: password,
      command: installCommand,
      stdin: acl,
      onOutput: onOutput,
    );
  }
}
