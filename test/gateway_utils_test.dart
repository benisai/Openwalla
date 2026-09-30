import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/utils/gateway_utils.dart';

void main() {
  test('proposes the first address on the local IPv4 subnet', () {
    expect(GatewayUtils.gatewayCandidate('10.0.4.114'), '10.0.4.1');
    expect(GatewayUtils.gatewayCandidate('192.168.8.52'), '192.168.8.1');
  });

  test('rejects invalid and non-IPv4 addresses', () {
    expect(GatewayUtils.gatewayCandidate('not-an-address'), isNull);
    expect(GatewayUtils.gatewayCandidate('192.168.8.999'), isNull);
    expect(GatewayUtils.gatewayCandidate('fe80::1'), isNull);
  });
}
