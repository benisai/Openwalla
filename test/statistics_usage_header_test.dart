import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/screens/statistics_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _UsageState extends ChangeNotifier implements AppState {
  final String interfaceName;
  _UsageState(
    this.interfaceName, {
    this.offline = false,
    this.support = true,
    this.empty = false,
  });
  bool offline;
  final bool support;
  final bool empty;
  int supportChecks = 0;

  @override
  DashboardPreferences get dashboardPreferences => DashboardPreferences();
  @override
  bool get isDashboardLoading => false;
  @override
  bool get offlineViewing => offline;
  @override
  Map<String, dynamic> get dashboardData => {};
  @override
  StatisticsPreloadData? get statisticsPreloadData => null;
  @override
  Future<StatisticsPreloadData>? get statisticsPreloadFuture => null;
  @override
  Future<bool> hasStatisticsSupport({BuildContext? context}) async {
    supportChecks++;
    return support;
  }

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
  }) async => empty
      ? []
      : [
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
  for (final empty in [false, true]) {
    testWidgets('offline Statistics skips installation checks (empty=$empty)', (
      tester,
    ) async {
      final state = _UsageState(
        'br-lan',
        offline: true,
        support: false,
        empty: empty,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: const MaterialApp(home: StatisticsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(state.supportChecks, 0);
      expect(find.text('Statistics tools are not installed'), findsNothing);
      expect(
        find.byKey(const ValueKey('interface-usage-header')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Usage settings',
              ),
            )
            .onPressed,
        isNull,
      );
      if (!empty) {
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('interface-usage-total')))
              .data,
          'Total 48 MB',
        );
      }
    });
  }
  testWidgets('live missing-tools check remains, then offline bypasses it', (
    tester,
  ) async {
    final state = _UsageState('br-lan', support: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: StatisticsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Statistics tools are not installed'), findsOneWidget);
    state.offline = true;
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Statistics tools are not installed'), findsNothing);
    expect(
      find.byKey(const ValueKey('interface-usage-header')),
      findsOneWidget,
    );
    expect(state.supportChecks, 1);
  });
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
