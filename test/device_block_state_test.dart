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

  test('configured DHCP names win and replace stale cached names', () {
    final source = File(
      'openwrt-setup/files/openwalla-devices-collector.sh',
    ).readAsStringSync();
    final candidates = source.substring(
      source.indexOf('collect_candidates()'),
      source.indexOf('collect_totals()'),
    );

    expect(
      candidates.indexOf('collect_static_dhcp'),
      lessThan(candidates.indexOf('collect_dhcp')),
    );
    expect(source, contains('tolower(host) == router_hostname'));
    expect(
      RegExp(r'hostname=excluded\.hostname').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('collector reads actual iwinfo associations on the LAN radio', () async {
    final source = File(
      'openwrt-setup/files/openwalla-devices-collector.sh',
    ).readAsStringSync();
    final function = shellFunction(source, 'collect_wireless');
    final result = await Process.run('sh', [
      '-c',
      '''
LAN_NETWORK=lan
ubus() {
  if [ "\$2" = network.wireless ]; then
    printf '%s\\n' '{"radio0":{"interfaces":[{"ifname":"phy0-ap0"}]}}'
  elif [ "\$2" = iwinfo ] && [ "\$3" = assoclist ]; then
    printf '%s\\n' '{"results":[{"mac":"AA:BB:CC:DD:EE:01"}]}'
  fi
}
jsonfilter() {
  case "\$*" in
    *ifname*) printf '%s\\n' phy0-ap0 ;;
    *results*) printf '%s\\n' AA:BB:CC:DD:EE:01 ;;
  esac
}
$function
collect_wireless
''',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout.toString().trim(), 'aa:bb:cc:dd:ee:01|||1');
  });

  test(
    'failed quarantine is retried without remembering or notifying success',
    () async {
      final source = File(
        'openwrt-setup/files/openwalla-devices-collector.sh',
      ).readAsStringSync();
      final functions = [
        'process_new_device',
        'quarantine_new_device',
      ].map((name) => shellFunction(source, name)).join('\n');
      final directory = await Directory.systemTemp.createTemp(
        'openwalla-quarantine-retry-',
      );
      try {
        final result = await Process.run('sh', [
          '-c',
          '''
STATE_FILE="\$1/known"
QUARANTINE_ENABLED=1
engine_fails=1
is_known_mac() { grep -qx "\$1" "\$STATE_FILE" 2>/dev/null; }
remember_mac() { printf '%s\\n' "\$1" >>"\$STATE_FILE"; }
is_enabled_flag() { [ "\$1" = 1 ]; }
is_ipv4() { return 0; }
apply_device_access() { [ "\$engine_fails" = 0 ]; }
sql_escape() { printf '%s' "\$1"; }
sql_exec() { :; }
write_quarantine_notification() { echo success >>"\$STATE_FILE.notifications"; }
log() { :; }
$functions
process_new_device aa:bb:cc:dd:ee:ff 192.168.1.5 android
[ "\$?" = 2 ] || exit 11
[ ! -s "\$STATE_FILE" ] || exit 12
[ ! -e "\$STATE_FILE.notifications" ] || exit 13
engine_fails=0
process_new_device aa:bb:cc:dd:ee:ff 192.168.1.5 android || exit 14
grep -qx aa:bb:cc:dd:ee:ff "\$STATE_FILE" || exit 15
[ "\$(wc -l <"\$STATE_FILE.notifications" | tr -d ' ')" = 1 ] || exit 16
''',
          'retry-test',
          directory.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'existing IPv4 quarantine rules upgrade through the shared engine once',
    () async {
      final source = File(
        'openwrt-setup/files/openwalla-devices-collector.sh',
      ).readAsStringSync();
      final directory = await Directory.systemTemp.createTemp(
        'openwalla-quarantine-upgrade-',
      );
      try {
        final function = shellFunction(source, 'upgrade_quarantine_rules')
            .replaceAll(
              '/tmp/openwalla/device-access-migrated-v1',
              '${directory.path}/done',
            );
        final result = await Process.run('sh', [
          '-c',
          '''
collect_quarantined() { echo aa:bb:cc:dd:ee:ff; }
uci() { echo firewall.old=rule; }
uci_get() {
  case "\$1" in
    *.name) echo openwalla_quarantine_phone_lan ;;
    *.src_mac) echo aa:bb:cc:dd:ee:ff ;;
    *.family) echo ipv4 ;;
  esac
}
apply_device_access() { printf '%s\\n' "\$*" >>"\$1file"; }
$function
upgrade_quarantine_rules || exit 1
upgrade_quarantine_rules || exit 2
'''
              .replaceAll('"\$1file"', '"${directory.path}/calls"'),
        ]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(
          await File('${directory.path}/calls').readAsString(),
          'block quarantine aa:bb:cc:dd:ee:ff\n',
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
