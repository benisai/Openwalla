import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/models/system_resource_metrics.dart';

void main() {
  test('parses and formats system uptime', () {
    final metrics = SystemResourceMetrics.fromRouterData({
      'uptime': 93784,
      'load': [0, 0, 0],
    });

    expect(metrics.uptimeSeconds, 93784);
    expect(metrics.formattedUptime, '1d 2h 3m');
  });

  test('normalizes OpenWrt fixed-point load and memory values', () {
    final metrics = SystemResourceMetrics.fromRouterData(
      {
        'load': [214958, 146145, 95027],
        'memory': {
          'total': 1073741824,
          'free': 209715200,
          'buffered': 52428800,
          'cached': 314572800,
        },
      },
      boardInfo: {'system': 'MediaTek MT7988'},
    );

    expect(metrics.load1m, closeTo(3.28, 0.01));
    expect(metrics.cpuUsagePercent, closeTo(42.6, 0.2));
    expect(metrics.usedMemoryBytes, 811597824);
    expect(metrics.memoryUsagePercent, closeTo(75.59, 0.01));
  });

  test('prefers a direct CPU percentage when the router provides one', () {
    final metrics = SystemResourceMetrics.fromRouterData({
      'cpu': {'idle': 77},
      'load': [0, 0, 0],
    });

    expect(metrics.cpuUsagePercent, 23);
  });
}
