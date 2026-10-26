import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/network_performance_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _PingState extends ChangeNotifier implements AppState {
  @override
  bool get offlineViewing => false;
  final List<PingMonitorSample> samples;
  final int thresholdMs;
  _PingState(this.samples, this.thresholdMs);

  @override
  Future<NetworkMonitorSettings> fetchNetworkMonitorSettings({
    BuildContext? context,
  }) async =>
      NetworkMonitorSettings(target: '1.1.1.1', thresholdMs: thresholdMs);

  @override
  Map<String, dynamic> get dashboardData => {'pingSamples': samples};

  @override
  Future<bool> hasNetworkPerformanceSupport({BuildContext? context}) async =>
      true;

  @override
  Future<List<PingMonitorSample>> fetchPingMonitorSamples({
    int limit = kOpenwallaPingTimelineSampleLimit,
    BuildContext? context,
  }) async => samples;

  @override
  Future<List<SpeedtestMonitorSample>> fetchSpeedtestMonitorSamples({
    int limit = 30,
    BuildContext? context,
  }) async => [];

  @override
  Future<List<OpenwallaNotification>> fetchNotifications({
    int limit = 200,
    bool includeArchived = false,
    BuildContext? context,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final threshold in [100, 200]) {
    testWidgets(
      'Ping Test uses $threshold ms router threshold for rendered bars',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(600, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final now = DateTime.now();
        final slot = DateTime(
          now.year,
          now.month,
          now.day,
          now.hour,
          now.minute ~/ 5 * 5,
        );
        final samples = [12.0, 65.0, 150.0, null].asMap().entries.map((entry) {
          return PingMonitorSample(
            timestamp: slot.subtract(Duration(minutes: entry.key * 5)),
            target: '1.1.1.1',
            status: entry.value == null ? 'ERROR' : 'OK',
            latencyMs: entry.value,
            message: '',
          );
        }).toList();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith(
                (_) => _PingState(samples, threshold),
              ),
            ],
            child: MaterialApp(home: const NetworkPerformanceScreen()),
          ),
        );
        await tester.pumpAndSettle();
        final chart = find.byKey(const ValueKey('ping-test-chart'));
        expect(chart, findsOneWidget);
        final panel = tester.widget(chart);
        // Check the ping panel at phone width independently of other page panels.
        await tester.binding.setSurfaceSize(const Size(390, 800));
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: panel)));
        await tester.pumpAndSettle();
        final bars = find.descendant(
          of: chart,
          matching: find.byType(Container),
        );
        final colors = tester
            .widgetList<Container>(bars)
            .where((container) => container.constraints?.maxWidth == 10)
            .map((container) => (container.decoration as BoxDecoration).color)
            .toList();
        expect(colors.length, 12);
        expect(colors.sublist(8), [
          const Color(0xFFFF424B),
          threshold == 100 ? const Color(0xFFEAB308) : const Color(0xFF86EFAC),
          const Color(0xFF86EFAC),
          const Color(0xFF168A48),
        ]);
        final context = tester.element(chart);
        final gray = Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.76);
        expect(colors.take(8), everyElement(gray));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
