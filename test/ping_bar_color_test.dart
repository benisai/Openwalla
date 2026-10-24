import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/screens/network_performance_screen.dart';

void main() {
  for (final latency in [0.0, 12.0, 29.99]) {
    test('$latency ms uses excellent light green', () {
      expect(
        NetworkPerformanceScreen.pingLatencyColor(latency),
        const Color(0xFF86EFAC),
      );
    });
  }

  for (final latency in [30.0, 65.0, 99.99]) {
    test('$latency ms uses regular dark green', () {
      expect(
        NetworkPerformanceScreen.pingLatencyColor(latency),
        const Color(0xFF168A48),
      );
    });
  }

  for (final latency in [100.0, 250.0]) {
    test('$latency ms keeps existing yellow', () {
      expect(
        NetworkPerformanceScreen.pingLatencyColor(latency),
        const Color(0xFFEAB308),
      );
    });
  }
}
