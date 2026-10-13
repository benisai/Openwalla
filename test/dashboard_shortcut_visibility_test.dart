import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/dashboard_preferences.dart';

void main() {
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
}
