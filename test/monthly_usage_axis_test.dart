import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/monthly_usage_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _MonthlyState extends ChangeNotifier implements AppState {
  @override
  Future<List<VnstatUsageSample>> fetchVnstatUsageSamples({
    required String period,
    String? interfaceName,
    int limit = 12,
    BuildContext? context,
  }) async => [
    VnstatUsageSample(
      timestamp: DateTime.now(),
      downloadBytes: 1024 * 1024,
      uploadBytes: 512 * 1024,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final days in [28, 29, 30, 31]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('$days-day month has readable ticks at scale $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 168,
                    child: MonthlyUsageDayAxis(days: days),
                  ),
                ),
              ),
            ),
          ),
        );
        final axis = tester.getRect(
          find.byKey(const ValueKey('monthly-day-axis')),
        );
        final expected = [1, 7, 14, 21, days];
        Rect? previous;
        for (final day in expected) {
          final label = find.byKey(ValueKey('monthly-day-label-$day'));
          if (scale > 1 && day != 1 && day != days && label.evaluate().isEmpty) {
            continue;
          }
          expect(tester.widget<Text>(label).data, '$day');
          final rect = tester.getRect(label);
          expect(rect.left, greaterThanOrEqualTo(axis.left));
          expect(rect.right, lessThanOrEqualTo(axis.right));
          if (previous != null) {
            expect(previous.right, lessThanOrEqualTo(rect.left));
          }
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(paragraph.didExceedMaxLines, isFalse);
          previous = rect;
        }
        expect(
          find.byType(Text).evaluate().length,
          scale == 1 ? 5 : inInclusiveRange(3, 5),
        );
        expect(
          tester
              .getCenter(find.byKey(const ValueKey('monthly-day-label-14')))
              .dx,
          closeTo(axis.left + axis.width * 13.5 / days, 0.1),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [320.0, 430.0]) {
    testWidgets('monthly chart labels fit full page at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStateProvider.overrideWith((ref) => _MonthlyState())],
          child: const MaterialApp(
            home: MonthlyUsageScreen(interfaceName: 'br-lan'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final last = DateTime(now.year, now.month + 1, 0).day;
      for (final day in [1, 7, 14, 21, last]) {
        if (day == 21) continue;
        expect(find.byKey(ValueKey('monthly-day-label-$day')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
