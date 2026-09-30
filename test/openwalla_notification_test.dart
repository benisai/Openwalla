import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  group('OpenwallaNotification', () {
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
    });
  });
}
