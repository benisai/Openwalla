import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  String shellFunction(String source, String name) {
    return RegExp(
      '$name\\(\\) \\{[\\s\\S]*?\\n\\}',
    ).firstMatch(source)!.group(0)!;
  }

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
      final function = shellFunction(source, 'collect_firewall_macs');
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

  test(
    'collector discovers configured router interface MAC addresses',
    () async {
      final source = File(
        'openwrt-setup/files/openwalla-devices-collector.sh',
      ).readAsStringSync();
      final function = shellFunction(source, 'collect_router_macs');
      final result = await Process.run('sh', [
        '-c',
        '''
uci() {
  printf '%s\n' "network.wwan.macaddr='7A:FF:DE:3C:15:96'" "wireless.sta.macaddr='5A:C1:1A:0B:BB:36'"
}
ip() { printf '%s\n' '2: wlan0: <BROADCAST,UP> mtu 1500' '    link/ether 02:11:22:33:44:55 brd ff:ff:ff:ff:ff:ff'; }
$function
collect_router_macs
''',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final macs = result.stdout.toString().trim().split('\n');
      expect(macs, contains('7a:ff:de:3c:15:96'));
      expect(macs, contains('5a:c1:1a:0b:bb:36'));
      expect(macs, contains('02:11:22:33:44:55'));
    },
  );

  test('collector discovers and excludes every router IPv4 address', () async {
    final source = File(
      'openwrt-setup/files/openwalla-devices-collector.sh',
    ).readAsStringSync();
    final function = shellFunction(source, 'collect_router_ipv4');
    final result = await Process.run('sh', [
      '-c',
      '''
ip() {
  printf '%s\n' '    inet 192.168.1.1/24 brd 192.168.1.255 scope global br-lan' '    inet 192.168.1.206/24 brd 192.168.1.255 scope global phy0-sta0'
}
$function
collect_router_ipv4
''',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString().trim().split('\n'), [
      '192.168.1.1',
      '192.168.1.206',
    ]);
    expect(RegExp(r'is_router_ipv4 "\$ip"').allMatches(source).length, 3);
    expect(
      source,
      contains("SELECT lower(mac) FROM devices WHERE ip='\$esc_ip'"),
    );
  });
}
