import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/utils/device_firewall_state.dart';

void main() {
  const automaticMac = 'AA:BB:CC:DD:EE:01';
  const manualMac = 'AA:BB:CC:DD:EE:02';
  const scheduledMac = 'AA:BB:CC:DD:EE:03';
  const disabledMac = 'AA:BB:CC:DD:EE:04';

  test('live firewall rules are the source of blocked device state', () {
    final state = parseDeviceFirewallState([
      0,
      {
        'values': {
          'automatic': {
            'name': 'openwalla_quarantine_phone_lan',
            'src_mac': automaticMac.toLowerCase(),
          },
          'manual': {
            'name': 'owrt_device_block_laptop_wan',
            'src_mac': [manualMac],
          },
          'scheduled': {
            'name': 'openwalla_schedule_kids',
            'src_mac_address': scheduledMac,
          },
          'disabled': {
            'name': 'openwalla_quarantine_old_lan',
            'src_mac': disabledMac,
            'enabled': '0',
          },
        },
      },
    ]);

    expect(state.available, isTrue);
    expect(state.blockedMacs, {automaticMac, manualMac, scheduledMac});
    expect(state.quarantinedMacs, {automaticMac});
    expect(state.blockedMacs, isNot(contains(disabledMac)));
  });

  test('legacy app blocks are blocked but are not quarantine devices', () {
    final state = parseDeviceFirewallState([
      0,
      {
        'values': {
          'lan': {
            'name': 'openwalla_quarantine_tablet_lan',
            'src_mac': manualMac,
          },
          'router': {
            'name': 'openwalla_quarantine_tablet_router',
            'src_mac': manualMac,
          },
        },
      },
    ]);

    expect(state.blockedMacs, {manualMac});
    expect(state.quarantinedMacs, isEmpty);
  });

  test('failed firewall reads are marked unavailable', () {
    final state = parseDeviceFirewallState([6]);

    expect(state.available, isFalse);
    expect(state.blockedMacs, isEmpty);
  });

  test('confirmed empty firewall rules clear stale cached block state', () {
    final disposition = resolveDeviceFirewallDisposition(
      state: const DeviceFirewallState(),
      mac: automaticMac,
      cachedBlocked: true,
      cachedQuarantined: true,
    );

    expect(disposition.blocked, isFalse);
    expect(disposition.quarantined, isFalse);
  });

  test('unavailable firewall reads preserve cached state', () {
    final disposition = resolveDeviceFirewallDisposition(
      state: const DeviceFirewallState(available: false),
      mac: automaticMac,
      cachedBlocked: true,
      cachedQuarantined: true,
    );

    expect(disposition.blocked, isTrue);
    expect(disposition.quarantined, isTrue);
  });
}
