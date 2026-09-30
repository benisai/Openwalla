import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  test('parses global firewall defaults', () {
    final defaults = OpenwrtFirewallDefaults.fromUciSection({
      'input': 'accept',
      'output': 'ACCEPT',
      'forward': 'reject',
      'syn_flood': '1',
    });

    expect(defaults.input, 'ACCEPT');
    expect(defaults.output, 'ACCEPT');
    expect(defaults.forward, 'REJECT');
    expect(defaults.synFloodProtection, isTrue);
  });

  test('parses enabled inter-zone forwarding', () {
    final forwarding = OpenwrtFirewallForwarding.fromUciSection({
      'src': 'lan',
      'dest': 'wan',
    });

    expect(forwarding.source, 'lan');
    expect(forwarding.destination, 'wan');
    expect(forwarding.enabled, isTrue);
  });

  test('honors both OpenWrt disabled representations', () {
    expect(
      OpenwrtFirewallForwarding.fromUciSection({
        'src': 'guest',
        'dest': 'wan',
        'disabled': '1',
      }).enabled,
      isFalse,
    );
    expect(
      OpenwrtFirewallForwarding.fromUciSection({
        'src': 'guest',
        'dest': 'lan',
        'enabled': '0',
      }).enabled,
      isFalse,
    );
  });
}
