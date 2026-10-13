import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/interface.dart';
import 'package:openwalla/screens/interfaces_screen.dart';

void main() {
  group('public IP interface details', () {
    test('shows on WAN, STA names, STA devices, and WWAN repeaters', () {
      for (final row in [
        {'interface': 'wan', 'device': 'eth1'},
        {'interface': 'sta', 'device': 'wlan0'},
        {'interface': 'repeater-sta0', 'device': 'wlan0'},
        {'interface': 'uplink', 'device': 'phy0-sta0'},
        {'interface': 'uplink', 'l3_device': 'wlan1-sta0'},
        {'interface': 'wwan', 'device': 'wlan0'},
        {'interface': 'wwan1', 'device': 'wlan1'},
        {'interface': ' WWAN2 ', 'device': 'wlan2'},
        {'interface': 'uplink', 'device': 'PHY1-STA0'},
      ]) {
        expect(
          shouldShowInterfacePublicIp(NetworkInterface.fromJson(row)),
          isTrue,
          reason: '$row',
        );
      }
    });

    test('does not show on unrelated LAN, AP, or VPN interfaces', () {
      for (final row in [
        {'interface': 'lan', 'device': 'br-lan'},
        {'interface': 'guest', 'device': 'phy0-ap0'},
        {'interface': 'wg0', 'device': 'wg0'},
        {'interface': 'loopback', 'device': 'lo'},
        <String, String>{},
      ]) {
        expect(
          shouldShowInterfacePublicIp(NetworkInterface.fromJson(row)),
          isFalse,
          reason: '$row',
        );
      }
    });
  });

  group('wired interface visibility', () {
    test('defaults to enabled interfaces before selection is initialized', () {
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'lan', 'up': true},
          enabledInterfaces: const {},
          selectionInitialized: false,
        ),
        isTrue,
      );
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'wan', 'up': false},
          enabledInterfaces: const {},
          selectionInitialized: false,
        ),
        isTrue,
      );
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'guest', 'up': true, 'disabled': '1'},
          enabledInterfaces: const {},
          selectionInitialized: false,
        ),
        isFalse,
      );
    });

    test('empty initialized selection explicitly shows all interfaces', () {
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'wan', 'up': false},
          enabledInterfaces: const {},
          selectionInitialized: true,
        ),
        isTrue,
      );
    });

    test('initialized selections only show checked interfaces', () {
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'lan', 'up': true},
          enabledInterfaces: const {'lan'},
          selectionInitialized: true,
        ),
        isTrue,
      );
      expect(
        shouldShowWiredInterface(
          interface: {'interface': 'wan', 'up': true},
          enabledInterfaces: const {'lan'},
          selectionInitialized: true,
        ),
        isFalse,
      );
    });
  });
}
