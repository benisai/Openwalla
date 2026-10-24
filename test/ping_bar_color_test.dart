import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/screens/network_performance_screen.dart';

void main() {
  for (final entry in {
    59.99: const Color(0xFF86EFAC),
    60.0: const Color(0xFF168A48),
    150.0: const Color(0xFF168A48),
    199.99: const Color(0xFF168A48),
    200.0: const Color(0xFFEAB308),
    250.0: const Color(0xFFEAB308),
  }.entries) {
    test('200 ms threshold colors ${entry.key} ms proportionally', () {
      expect(
        NetworkPerformanceScreen.pingStatusColor(
          hasSamples: true,
          latencyMs: entry.key,
          emptyColor: Colors.grey,
          thresholdMs: 200,
        ),
        entry.value,
      );
    });
  }

  test('lower thresholds scale down and invalid thresholds use defaults', () {
    expect(
      NetworkPerformanceScreen.pingLatencyColor(15, thresholdMs: 50),
      const Color(0xFF168A48),
    );
    expect(
      NetworkPerformanceScreen.pingLatencyColor(50, thresholdMs: 50),
      const Color(0xFFEAB308),
    );
    for (final threshold in [0, -1]) {
      expect(
        NetworkPerformanceScreen.pingLatencyColor(100, thresholdMs: threshold),
        const Color(0xFFEAB308),
      );
    }
  });

  test('missing ping data is gray, rather than failed red', () {
    expect(
      NetworkPerformanceScreen.pingStatusColor(
        hasSamples: false,
        latencyMs: null,
        emptyColor: Colors.grey,
      ),
      Colors.grey.withValues(alpha: 0.76),
    );
  });

  test('failed ping is red', () {
    expect(
      NetworkPerformanceScreen.pingStatusColor(
        hasSamples: true,
        latencyMs: null,
        emptyColor: Colors.grey,
      ),
      const Color(0xFFFF424B),
    );
  });

  test('all ping surfaces use the same latency palette', () {
    for (final latency in [0.0, 29.99, 30.0, 99.99, 100.0, 250.0]) {
      expect(
        NetworkPerformanceScreen.pingStatusColor(
          hasSamples: true,
          latencyMs: latency,
          emptyColor: Colors.grey,
        ),
        NetworkPerformanceScreen.pingLatencyColor(latency),
      );
    }
  });

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
