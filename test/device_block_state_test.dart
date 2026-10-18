import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  OpenwrtFirewallRule rule(String name) => OpenwrtFirewallRule(
    section: 'cfg123',
    name: name,
    source: '*',
    sourceIp: '',
    destination: 'wan',
    protocol: 'all',
    port: '',
    action: 'DROP',
    enabled: true,
  );

  test('manual and automatic device rules appear under Openwalla', () {
    expect(rule('owrt_device_block_aabbccddeeff_wan').isOpenwallaRule, isTrue);
    expect(rule('openwalla_quarantine_phone_lan').isOpenwallaRule, isTrue);
    expect(rule('Allow-Ping').isOpenwallaRule, isFalse);
  });

  test(
    'collector distinguishes manual, legacy manual, and automatic quarantine',
    () async {
      final source = File(
        'openwrt-setup/files/openwalla-devices-collector.sh',
      ).readAsStringSync();
      final function = RegExp(
        r'collect_firewall_macs\(\) \{[\s\S]*?\n\}',
      ).firstMatch(source)!.group(0)!;
      const firewall = '''
firewall.auto=rule
firewall.auto.src_mac='AA:BB:CC:DD:EE:01'
firewall.auto.name='openwalla_quarantine_phone_lan'
firewall.manual=rule
firewall.manual.name='owrt_device_block_laptop_wan'
firewall.manual.src_mac='AA:BB:CC:DD:EE:02'
firewall.legacy=rule
firewall.legacy.name='openwalla_quarantine_tablet_router'
firewall.legacy.src_mac='AA:BB:CC:DD:EE:03'
firewall.disabled=rule
firewall.disabled.name='owrt_device_block_off_wan'
firewall.disabled.src_mac='AA:BB:CC:DD:EE:04'
firewall.disabled.enabled='0'
''';
      final quoted = "'${firewall.replaceAll("'", "'\"'\"'")}'";
      Future<List<String>> collect(String prefix) async {
        final result = await Process.run('sh', [
          '-c',
          "uci() { printf '%s\\n' $quoted; }\n$function\ncollect_firewall_macs '$prefix'",
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        return result.stdout.toString().trim().split('\n');
      }

      expect(await collect('openwalla_quarantine_'), ['aa:bb:cc:dd:ee:01']);
      expect(await collect('owrt_device_block_'), [
        'aa:bb:cc:dd:ee:02',
        'aa:bb:cc:dd:ee:03',
      ]);
    },
  );

  test('collector rebuilds cached quarantine flags from firewall rules', () {
    final source = File(
      'openwrt-setup/files/openwalla-devices-collector.sh',
    ).readAsStringSync();
    final reset = source.indexOf('UPDATE devices SET quarantined=0;');
    final rebuild = source.indexOf('UPDATE devices SET quarantined=1');

    expect(reset, greaterThan(-1));
    expect(rebuild, greaterThan(reset));
  });
}
