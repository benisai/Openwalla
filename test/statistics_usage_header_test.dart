import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/screens/statistics_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _UsageState extends ChangeNotifier implements AppState {
  final String interfaceName;
  _UsageState(this.interfaceName);

  @override
  DashboardPreferences get dashboardPreferences => DashboardPreferences();
  @override
  bool get isDashboardLoading => false;
  @override
  Map<String, dynamic> get dashboardData => {};
  @override
  StatisticsPreloadData? get statisticsPreloadData => null;
  @override
  Future<StatisticsPreloadData>? get statisticsPreloadFuture => null;
  @override
  Future<bool> hasStatisticsSupport({BuildContext? context}) async => true;
  @override
  Future<MonthlyUsageSettings> fetchMonthlyUsageSettings({
    BuildContext? context,
  }) async =>
      MonthlyUsageSettings(monthStartDay: 1, interfaceName: interfaceName);
  @override
  Future<List<NlbwDeviceUsage>> fetchNlbwTopDevices({
    int limit = 5,
    BuildContext? context,
  }) async => [];
  @override
  Future<List<NlbwProtocolUsage>> fetchNlbwProtocolUsage({
    int limit = 5,
    BuildContext? context,
  }) async => [];
  @override
  Future<List<VnstatUsageSample>> fetchVnstatUsageSamples({
    required String period,
    String? interfaceName,
    int limit = 12,
    BuildContext? context,
  }) async => [
    VnstatUsageSample(
      timestamp: DateTime.now(),
      downloadBytes: limit * 1024 * 1024,
      uploadBytes: limit * 1024 * 1024,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final width in [360.0, 390.0, 1280.0]) {
    testWidgets('usage total is centered without overlap at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const name = 'br-lan';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStateProvider.overrideWith((ref) => _UsageState(name)),
          ],
          child: const MaterialApp(home: StatisticsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final header = find.byKey(const ValueKey('interface-usage-header'));
      final total = find.byKey(const ValueKey('interface-usage-total'));
      final title = find.text('$name Usage');
      final timeframe = find.text('Last 24 hours');
      expect(tester.widget<Text>(total).data, 'Total 48 MB');
      expect(
        tester.getCenter(total).dx,
        closeTo(tester.getCenter(header).dx, 0.1),
      );
      expect(
        tester.getRect(title).right,
        lessThanOrEqualTo(tester.getRect(total).left),
      );
      expect(
        tester.getRect(total).right,
        lessThanOrEqualTo(tester.getRect(timeframe).left),
      );
      expect(tester.takeException(), isNull);

      if (width == 360) {
        final pager = find.byKey(const ValueKey('interface-usage-pager'));
        await tester.ensureVisible(pager);
        await tester.drag(pager, const Offset(300, 0));
        await tester.pumpAndSettle();
        expect(find.text('Last 12 hours'), findsOneWidget);
        expect(tester.widget<Text>(total).data, 'Total 24 MB');
        expect(tester.takeException(), isNull);
      }
    });
  }
}
