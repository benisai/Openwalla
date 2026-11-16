import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/usage_chart_unit.dart';
import 'package:openwalla/screens/usage_settings_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _State extends ChangeNotifier implements AppState {
  MonthlyUsageSettings? saved;
  @override
  Future<MonthlyUsageSettings> fetchMonthlyUsageSettings({
    BuildContext? context,
  }) async => const MonthlyUsageSettings(
    monthStartDay: 1,
    interfaceName: 'br-lan',
    chartUnit: UsageChartUnit.mb,
  );
  @override
  Future<List<String>> fetchVnstatInterfaceNames({
    BuildContext? context,
  }) async => ['br-lan'];
  @override
  Future<void> saveMonthlyUsageSettings(
    MonthlyUsageSettings settings, {
    BuildContext? context,
  }) async {
    saved = settings;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'units use existing binary byte convention and numeric-only formatting',
    () {
      for (final unit in UsageChartUnit.values) {
        expect(unit.format(unit.bytes), '1');
        expect(unit.format(unit.bytes * 23.1), '23.1');
        expect(unit.format(0), '0');
        expect(double.parse(unit.format(1)), greaterThan(0));
        expect(unit.format(unit.bytes * 0.125), '0.125');
        expect(UsageChartUnit.parse(unit.label), unit);
      }
      expect(UsageChartUnit.parse(null), UsageChartUnit.gb);
      expect(UsageChartUnit.parse('unknown'), UsageChartUnit.gb);
    },
  );

  for (final width in [320.0, 430.0]) {
    testWidgets('Usage Settings loads and saves chart units at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final state = _State();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => state)],
          child: const MaterialApp(home: UsageSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('usage-chart-unit'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('TB').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(state.saved?.chartUnit, UsageChartUnit.tb);
      expect(state.saved?.interfaceName, 'br-lan');
      expect(state.saved?.monthlyLimitGb, 100);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
