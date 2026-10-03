import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/dashboard_preferences.dart';

void main() {
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
