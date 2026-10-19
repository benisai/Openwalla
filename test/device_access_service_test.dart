import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/services/device_access_service.dart';

void main() {
  test(
    'RPC succeeds only after the engine emits the verified success marker',
    () async {
      var sshUsed = false;
      final service = DeviceAccessService(
        loadScript: () async => '# shared engine',
        rpc: (args) async => [
          0,
          {
            'code': 0,
            'stdout':
                'OPENWALLA_DEVICE_ACCESS_OK|block|manual|aa:bb:cc:dd:ee:ff\n',
          },
        ],
        ssh: (_, _) async {
          sshUsed = true;
          return '';
        },
      );
      await service.change(mac: 'AA:BB:CC:DD:EE:FF', blocked: true);
      expect(sshUsed, isFalse);
    },
  );

  test('ACL denial executes the identical engine through SSH', () async {
    final service = DeviceAccessService(
      loadScript: () async => '# shared engine',
      rpc: (_) async => [6],
      ssh: (script, args) async {
        expect(script, contains('# shared engine'));
        expect(args.take(3), ['release', 'quarantine', 'aa:bb:cc:dd:ee:ff']);
        return 'OPENWALLA_DEVICE_ACCESS_OK|release|quarantine|aa:bb:cc:dd:ee:ff\n';
      },
    );
    await service.change(
      mac: 'AA:BB:CC:DD:EE:FF',
      blocked: false,
      reason: DeviceBlockReason.quarantine,
    );
  });

  test(
    'execution failures and queued-only output are not reported as success',
    () async {
      final service = DeviceAccessService(
        loadScript: () async => '# shared engine',
        rpc: (_) async => [
          0,
          {'code': 1, 'stdout': 'queued'},
        ],
        ssh: (_, _) async => '',
      );
      await expectLater(
        service.change(mac: 'AA:BB:CC:DD:EE:FF', blocked: true),
        throwsStateError,
      );
    },
  );

  test(
    'an ambiguous RPC failure retries the same operation ID through SSH',
    () async {
      String? operation;
      final service = DeviceAccessService(
        loadScript: () async => '# shared engine',
        rpc: (args) async {
          operation = args.last;
          throw StateError('Reply lost after execution');
        },
        ssh: (script, args) async {
          expect(args.last, operation);
          expect(script, contains('"\$4"'));
          return 'OPENWALLA_DEVICE_ACCESS_OK|release|current|aa:bb:cc:dd:ee:ff\n';
        },
      );
      await service.change(mac: 'AA:BB:CC:DD:EE:FF', blocked: false);
    },
  );
}
