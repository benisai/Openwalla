import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/dashboard_preferences.dart';

void main() {
  test(
    'Network and Wi-Fi are removed from default and saved shortcut orders',
    () {
      expect(
        DashboardPreferences.defaultShortcutOrder,
        isNot(contains('network')),
      );
      final restored = DashboardPreferences.fromJson({
        'shortcutOrder': ['network', 'wifi', 'routes', 'dns'],
      });
      expect(restored.shortcutOrder, isNot(contains('network')));
      expect(restored.shortcutOrder, isNot(contains('wifi')));
      expect(restored.shortcutOrder.take(2), ['routes', 'dns']);
    },
  );
  test('Network panel visibility persists independently of Wi-Fi', () {
    expect(DashboardPreferences.fromJson({}).showNetworkPanel, isTrue);
    final hidden = DashboardPreferences().copyWith(
      showNetworkPanel: false,
      showWifiShortcut: false,
    );
    final restored = DashboardPreferences.fromJson(hidden.toJson());
    expect(restored.showNetworkPanel, isFalse);
    expect(restored.showWifiShortcut, isFalse);
    expect(restored.copyWith(showNetworkPanel: true).showWifiShortcut, isFalse);
    expect(restored.copyWith(showWifiShortcut: true).showNetworkPanel, isFalse);
    expect(
      DashboardPreferences.fromJson({
        'showWifiShortcut': false,
      }).showWifiShortcut,
      isFalse,
    );
  });
  for (final count in [3, 6, 9]) {
    test('$count shortcut icons persist through copy and JSON', () {
      final updated = DashboardPreferences().copyWith(
        shortcutPanelVisibleCount: count,
      );
      expect(
        DashboardPreferences.fromJson(
          updated.toJson(),
        ).shortcutPanelVisibleCount,
        count,
      );
      expect(
        DashboardPreferences.fromJson({
          'shortcutPanelVisibleCount': '$count',
        }).shortcutPanelVisibleCount,
        count,
      );
      expect(
        updated.copyWith(showWifiShortcut: false).shortcutPanelVisibleCount,
        count,
      );
    });
  }

  test('missing or unsupported shortcut counts keep six-icon default', () {
    for (final value in [null, 0, 4, 12, 'invalid']) {
      expect(
        DashboardPreferences.fromJson({
          'shortcutPanelVisibleCount': value,
        }).shortcutPanelVisibleCount,
        6,
      );
    }
    expect(DashboardPreferences.fromJson({}).shortcutPanelVisibleCount, 6);
  });

  test('Tunnel is hidden by default and in older saved preferences', () {
    expect(DashboardPreferences().showTunnelPage, isFalse);
    expect(DashboardPreferences.fromJson({}).showTunnelPage, isFalse);
    expect(
      DashboardPreferences.fromJson({'showFlowsCard': true}).showTunnelPage,
      isFalse,
    );
  });

  test('Tunnel visibility persists without changing flow visibility', () {
    final original = DashboardPreferences(showFlowsCard: true);
    final shown = original.copyWith(showTunnelPage: true);
    final restored = DashboardPreferences.fromJson(shown.toJson());
    expect(restored.showTunnelPage, isTrue);
    expect(restored.showFlowsCard, isTrue);
    expect(restored.copyWith(showStatisticsTab: true).showTunnelPage, isTrue);
    expect(restored.copyWith(showTunnelPage: false).showTunnelPage, isFalse);
    expect(original.showTunnelPage, isFalse);
  });

  test('shortcut visibility helper hides install-dependent shortcuts', () {
    var preferences = DashboardPreferences();
    const shortcutIds = [
      'smart_queue',
      'adblock',
      'vpn',
      'parental',
      'scheduler',
      'ddns',
      'tor',
      'tailscale',
      'multi_wan',
      'quarantine',
      'geo_blocking',
    ];

    for (final shortcutId in shortcutIds) {
      preferences = preferences.copyWithShortcutVisibility(
        shortcutId,
        visible: false,
      );
    }

    expect(preferences.showSmartQueueShortcut, isFalse);
    expect(preferences.showAdblockShortcut, isFalse);
    expect(preferences.showVpnShortcut, isFalse);
    expect(preferences.showParentalShortcut, isFalse);
    expect(preferences.showSchedulerShortcut, isFalse);
    expect(preferences.showDdnsShortcut, isFalse);
    expect(preferences.showTorShortcut, isFalse);
    expect(preferences.showTailscaleShortcut, isFalse);
    expect(preferences.showMultiWanShortcut, isFalse);
    expect(preferences.showQuarantineShortcut, isFalse);
    expect(preferences.showGeoBlockingShortcut, isFalse);
  });

  test('statistics section expansion preferences persist', () {
    final defaults = DashboardPreferences.fromJson({});
    expect(defaults.statisticsTopDevicesExpanded, isTrue);
    expect(defaults.statisticsActivityAnalysisExpanded, isTrue);

    final collapsed = defaults.copyWith(
      statisticsTopDevicesExpanded: false,
      statisticsActivityAnalysisExpanded: false,
    );
    final restored = DashboardPreferences.fromJson(collapsed.toJson());

    expect(restored.statisticsTopDevicesExpanded, isFalse);
    expect(restored.statisticsActivityAnalysisExpanded, isFalse);
  });
}
