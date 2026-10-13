import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  group('OpenwallaNotification', () {
    test(
      'corrects old AP/STA Ethernet notifications without changing records',
      () {
        for (final entry in {
          'phy0-sta0': 'Wi-Fi uplink (WWAN)',
          'phy0-ap0': 'Wi-Fi access point',
          'wwan': 'Wi-Fi uplink (WWAN)',
        }.entries) {
          for (final connected in [true, false]) {
            final action = connected ? 'connected' : 'disconnected';
            final notification = OpenwallaNotification.fromSqliteRow(
              '21|1789849887|interface-monitor|old message|0|0|interface|'
              '${connected ? 'resolved' : 'critical'}|Ethernet port $action|'
              '${entry.key} lost its Ethernet link. Its previous speed was Unknown.|'
              'interface=${entry.key};carrier=${connected ? 1 : 0}',
            )!;
            expect(notification.displayTitle, '${entry.value} $action');
            expect(
              notification.displayDetails,
              '${entry.key} wireless link is ${connected ? 'up' : 'down'}.',
            );
            expect(notification.isWirelessInterfaceEvent, isTrue);
            expect(notification.title, 'Ethernet port $action');
          }
        }
      },
    );

    test('uses explicit wireless metadata for custom interface names', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '22|1789849887|interface-monitor|uplink wireless link is up.|0|0|'
        'interface|resolved|Wi-Fi uplink (WWAN) connected|'
        'uplink wireless link is up.|interface=uplink;link_type=wifi-sta;carrier=1',
      )!;
      expect(notification.isWirelessInterfaceEvent, isTrue);
      expect(notification.displayTitle, 'Wi-Fi uplink (WWAN) connected');
      expect(notification.displayDetails, 'uplink wireless link is up.');
    });

    test('does not misclassify Ethernet or TAP interfaces as wireless', () {
      for (final name in ['eth0', 'lan1', 'tap0']) {
        final notification = OpenwallaNotification.fromSqliteRow(
          '23|1789849887|interface-monitor|$name connected at 1 Gbps.|0|0|'
          'interface|resolved|Ethernet port connected|$name connected at 1 Gbps.|'
          'interface=$name;carrier=1',
        )!;
        expect(notification.isWirelessInterfaceEvent, isFalse);
        expect(notification.displayTitle, 'Ethernet port connected');
        expect(notification.displayDetails, '$name connected at 1 Gbps.');
      }
    });

    test('router monitor distinguishes AP, STA, and Ethernet devices', () {
      final source = File(
        'openwrt-setup/files/openwalla-network-monitor.sh',
      ).readAsStringSync();
      final function = source.substring(
        source.indexOf('interface_link_type()'),
        source.indexOf('interface_state_value()'),
      );
      for (final entry in {
        'phy0-sta0': 'wifi-sta',
        'wlan1-sta0': 'wifi-sta',
        'sta0': 'wifi-sta',
        'wwan1': 'wifi-sta',
        'phy0-ap0': 'wifi-ap',
        'ap0': 'wifi-ap',
        'eth0': 'ethernet',
        'lan1': 'ethernet',
        'tap0': 'ethernet',
      }.entries) {
        final result = Process.runSync('/bin/sh', [
          '-c',
          '$function\ninterface_link_type "\$1"',
          'test',
          '/nonexistent/${entry.key}',
        ]);
        expect(result.exitCode, 0);
        expect(result.stdout.toString().trim(), entry.value, reason: entry.key);
      }
    });

    test('parses enriched notification rows', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '8|1789849887|ping-monitor|Connectivity restored|0|0|'
        'network_health|resolved|Internet connection restored|'
        'Connectivity was restored after 2m.|target=1.1.1.1',
      );

      expect(notification, isNotNull);
      expect(notification!.displayTitle, 'Internet connection restored');
      expect(
        notification.displayDetails,
        'Connectivity was restored after 2m.',
      );
      expect(notification.effectiveSeverity, 'resolved');
      expect(notification.effectiveCategory, 'network_health');
      expect(notification.isNetworkPerformanceEvent, isTrue);
    });

    test('presents legacy ping rows with a useful title', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '4|1789849887|ping-monitor|'
        'Ping outage: target=1.1.1.1 result=outage reason=timeout|0|0',
      );

      expect(notification, isNotNull);
      expect(notification!.displayTitle, 'Internet connection lost');
      expect(notification.effectiveSeverity, 'critical');
      expect(notification.effectiveCategory, 'network_health');
    });

    test('recognizes interface events from enriched rows', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '9|1789849887|interface-monitor|lan1 changed speed|0|0|interface|'
        'warning|Ethernet link speed decreased|'
        'lan1 changed from 1 Gbps to 100 Mbps.|speed_mbps=100',
      );

      expect(notification, isNotNull);
      expect(notification!.displayTitle, 'Ethernet link speed decreased');
      expect(notification.effectiveSeverity, 'warning');
      expect(notification.effectiveCategory, 'interface');
    });

    test('recognizes WireGuard peer activity as a VPN event', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '10|1789849887|wireguard-monitor|Alice became active on wg0.|0|0|'
        'vpn|resolved|WireGuard client connected|'
        'Alice became active on wg0.|interface=wg0;peer=public-key',
      );

      expect(notification, isNotNull);
      expect(notification!.displayTitle, 'WireGuard client connected');
      expect(notification.effectiveSeverity, 'resolved');
      expect(notification.effectiveCategory, 'vpn');
    });

    test('presents new quarantine events as device warnings', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '11|1789849887|device-quarantine|New device quarantined '
        'mac=AA:BB:CC:DD:EE:FF ip=192.168.1.42 host=phone|0|0',
      );

      expect(notification, isNotNull);
      expect(notification!.displayTitle, 'New device detected');
      expect(notification.effectiveSeverity, 'warning');
      expect(notification.effectiveCategory, 'device');
      expect(notification.isNetworkPerformanceEvent, isFalse);
      expect(notification.isQuarantineEvent, isTrue);
      expect(notification.deviceMacAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('reads quarantine device MAC from enriched metadata', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '12|1789849887|device-quarantine|New device quarantined|0|0|device|'
        'warning|Device quarantined|Phone needs approval|mac=aa-bb-cc-dd-ee-ff',
      )!;
      expect(notification.deviceMacAddress, 'AA:BB:CC:DD:EE:FF');
    });

    test('quarantine rows without a valid MAC do not link to a device', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '13|1789849887|device-quarantine|New device quarantined mac=invalid|0|0',
      )!;
      expect(notification.isQuarantineEvent, isTrue);
      expect(notification.deviceMacAddress, isNull);
    });

    test('unrelated device events do not become quarantine links', () {
      final notification = OpenwallaNotification.fromSqliteRow(
        '14|1789849887|devices|Device connected mac=AA:BB:CC:DD:EE:FF|0|0',
      )!;
      expect(notification.isQuarantineEvent, isFalse);
      expect(notification.deviceMacAddress, isNull);
    });
  });
}
