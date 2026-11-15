import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/monthly_usage_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _MonthlyState extends ChangeNotifier implements AppState {
  int reads = 0;
  @override
  Future<List<VnstatUsageSample>> fetchVnstatUsageSamples({
    required String period,
    String? interfaceName,
    int limit = 12,
    BuildContext? context,
  }) async {
    reads++;
    final now = DateTime.now();
    return [
      VnstatUsageSample(
        timestamp: DateTime(now.year, now.month, 1),
        downloadBytes: 1024 * 1024,
        uploadBytes: 512 * 1024,
      ),
      VnstatUsageSample(
        timestamp: DateTime(now.year, now.month, 2),
        downloadBytes: 0,
        uploadBytes: 0,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<_MonthlyState> mount(WidgetTester tester) async {
    final state = _MonthlyState();
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(
          home: MonthlyUsageScreen(interfaceName: 'br-lan'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('monthly bars show date and download/upload totals on tap', (
    tester,
  ) async {
    final state = await mount(tester);
    final bar = find.byKey(const ValueKey('monthly-usage-bar-1'));
    await tester.ensureVisible(bar);
    await tester.tap(bar);
    await tester.pumpAndSettle();
    final message = tester.widget<Tooltip>(bar).message!;
    expect(message, contains('Total 1.5 MB'));
    expect(message, contains('Down 1.0 MB  Up 0.5 MB'));
    expect(message, contains('${DateTime.now().year}'));
    expect(find.text(message, findRichText: true), findsOneWidget);
    expect(state.reads, 1);
  });

  testWidgets(
    'zero and missing days are distinct and another tap changes the tip',
    (tester) async {
      await mount(tester);
      final zero = find.byKey(const ValueKey('monthly-usage-bar-2'));
      await tester.ensureVisible(zero);
      await tester.tap(zero);
      await tester.pumpAndSettle();
      final firstMessage = tester.widget<Tooltip>(zero).message!;
      expect(firstMessage, contains('Total 0 B'));
      final empty = find.byKey(const ValueKey('monthly-usage-bar-3'));
      await tester.tap(empty);
      await tester.pumpAndSettle();
      final secondMessage = tester.widget<Tooltip>(empty).message!;
      expect(secondMessage, contains('No usage data'));
      expect(secondMessage, isNot(contains('Total 0 B')));
      expect(find.text(secondMessage, findRichText: true), findsOneWidget);
      expect(find.text(firstMessage, findRichText: true), findsNothing);
    },
  );

  for (final width in [320.0, 430.0]) {
    testWidgets('monthly tooltips fit edge bars at $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester);
      final now = DateTime.now();
      final last = DateTime(now.year, now.month + 1, 0).day;
      for (final day in [1, last]) {
        final bar = find.byKey(ValueKey('monthly-usage-bar-$day'));
        await tester.ensureVisible(bar);
        await tester.tap(bar);
        await tester.pumpAndSettle();
        final tip = find.text(
          tester.widget<Tooltip>(bar).message!,
          findRichText: true,
        );
        expect(tip, findsOneWidget);
        final bounds = tester.getRect(tip);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(900));
        expect(tester.takeException(), isNull);
      }
    });
  }
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
          if (scale > 1 &&
              day != 1 &&
              day != days &&
              label.evaluate().isEmpty) {
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
