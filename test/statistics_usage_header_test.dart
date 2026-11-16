import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/dashboard_preferences.dart';
import 'package:openwalla/models/usage_chart_unit.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:openwalla/screens/statistics_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _UsageState extends ChangeNotifier implements AppState {
  final String interfaceName;
  _UsageState(
    this.interfaceName, {
    this.offline = false,
    this.support = true,
    this.empty = false,
    this.unit = UsageChartUnit.gb,
  });
  bool offline;
  final bool support;
  final bool empty;
  UsageChartUnit unit;
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
  }) async => MonthlyUsageSettings(
    monthStartDay: 1,
    interfaceName: interfaceName,
    chartUnit: unit,
  );
  @override
  Future<List<NlbwDeviceUsage>> fetchNlbwTopDevices({
    int limit = 5,
    BuildContext? context,
  }) async => [];
  @override
  Future<List<String>> fetchVnstatInterfaceNames({
    BuildContext? context,
  }) async => [interfaceName];
  @override
  Future<void> saveMonthlyUsageSettings(
    MonthlyUsageSettings settings, {
    BuildContext? context,
  }) async {
    unit = settings.chartUnit;
  }

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
  setUpAll(() async {
    final fonts = Platform.environment['USAGE_CHART_FONT_DIR'];
    if (fonts == null) return;
    for (final entry in {
      'UsageScreenshot': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File(
            '$fonts/${entry.value}',
          ).readAsBytes().then(ByteData.sublistView),
        );
      await loader.load();
    }
  });
  testWidgets('returning from Usage Settings immediately applies chart units', (
    tester,
  ) async {
    final state = _UsageState('br-lan');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: StatisticsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Usage settings'));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('usage-chart-unit'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MB').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Values in MB'), findsOneWidget);
    expect(find.text('Values in GB'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
  });
  for (final unit in UsageChartUnit.values) {
    testWidgets(
      'chart labels use numeric ${unit.label} and tap tips keep units',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStateProvider.overrideWith(
                (ref) => _UsageState('br-lan', unit: unit),
              ),
            ],
            child: const MaterialApp(home: StatisticsScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Values in ${unit.label}'), findsOneWidget);
        final chart = tester
            .widgetList<BarChart>(find.byType(BarChart))
            .firstWhere(
              (chart) => chart.data.barGroups.any(
                (group) => group.barRods.first.toY > 0,
              ),
            );
        final group = chart.data.barGroups.last;
        final label = chart.data.barTouchData.touchTooltipData.getTooltipItem(
          group,
          group.x,
          group.barRods.first,
          0,
        )!;
        expect(label.text, unit.format(48 * 1024 * 1024));
        expect(double.tryParse(label.text), isNotNull);
        expect(label.text, isNot(contains(unit.label)));
        expect(find.text('Total 48 MB'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
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
  for (final width in [320.0, 360.0, 390.0, 1280.0]) {
    testWidgets('usage total is centered without overlap at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (width == 320) {
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      final screenshotKey = GlobalKey();
      const name = 'br-lan';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStateProvider.overrideWith((ref) => _UsageState(name)),
          ],
          child: RepaintBoundary(
            key: screenshotKey,
            child: MaterialApp(
              theme: ThemeData.dark().copyWith(
                textTheme: ThemeData.dark().textTheme.apply(
                  fontFamily:
                      Platform.environment['USAGE_CHART_FONT_DIR'] == null
                      ? null
                      : 'UsageScreenshot',
                ),
              ),
              home: const StatisticsScreen(),
            ),
          ),
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

      final screenshotPath = Platform.environment['USAGE_CHART_SCREENSHOT'];
      if (width == 320 && screenshotPath != null) {
        final boundary =
            screenshotKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(screenshotPath).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

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
