import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/adblock_report.dart';
import 'package:openwalla/screens/adblock_reports_screen.dart';
import 'package:openwalla/state/app_state.dart';

String sample({bool legacy = false}) => jsonEncode({
  'generated_at': 1794592800,
  'data': [
    {
      'total': '20',
      'blocked': '3',
      'start_date': '2026-11-13',
      'start_time': '09:00:00',
      'end_date': '2026-11-13',
      'end_time': '09:05:00',
      'requests': [
        {
          'domain': 'example.com',
          'client': '192.168.1.20',
          'rc': 'OK',
          'date': '2026-11-13',
          'time': '09:04:00',
          if (!legacy) 'type': 'A',
          if (!legacy) 'iface': 'br-lan',
        },
        {'domain': 'ads.example.net', 'client': '192.168.1.30', 'rc': 'NX'},
      ],
    },
  ],
});

class _State extends ChangeNotifier implements AppState {
  AdblockReport? report = AdblockReport.parse(sample());
  bool fail = false;
  int reads = 0;
  @override
  Future<AdblockReport?> fetchAdblockReport() async {
    reads++;
    if (fail) throw StateError('Disconnected');
    return report;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('parses both report shapes and case-insensitive searches', () {
    for (final legacy in [false, true]) {
      final report = AdblockReport.parse(sample(legacy: legacy));
      expect(report.total, 20);
      expect(report.blocked, 3);
      expect(report.requests.length, 2);
      expect(report.requests.first.matches('EXAMPLE.COM'), isTrue);
      expect(report.requests.first.matches('192.168.1.20'), isTrue);
      expect(report.requests.last.matches('NXDOMAIN'), isTrue);
    }
  });
  test('rejects malformed caches rather than reporting zero traffic', () {
    for (final value in [
      'broken',
      '{}',
      '{"generated_at":1,"data":[]}',
      '{"generated_at":1,"data":{"total":1,"requests":42}}',
    ]) {
      expect(() => AdblockReport.parse(value), throwsFormatException);
    }
  });

  Future<void> mount(WidgetTester tester, _State state) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: AdblockReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders cached queries and searches without extra router reads',
    (tester) async {
      final state = _State();
      await mount(tester, state);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.text('ads.example.net'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '192.168.1.30');
      await tester.pump();
      expect(find.text('example.com'), findsNothing);
      expect(find.text('ads.example.net'), findsOneWidget);
      expect(state.reads, 1);
      await tester.enterText(find.byType(TextField), 'nothing');
      await tester.pump();
      expect(find.text('No matching queries'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('example.com'), findsOneWidget);
    },
  );
  testWidgets('failed refresh retains the report and reports an error', (
    tester,
  ) async {
    final state = _State();
    await mount(tester, state);
    state.fail = true;
    await tester.tap(find.byTooltip('Refresh reports'));
    await tester.pumpAndSettle();
    expect(find.text('example.com'), findsOneWidget);
    expect(find.textContaining('Could not read reports.'), findsOneWidget);
    expect(state.reads, 2);
  });
  testWidgets('no cache yet is distinct from a failure', (tester) async {
    await mount(tester, _State()..report = null);
    expect(find.text('Waiting for the first DNS report.'), findsOneWidget);
    expect(find.text('Report unavailable'), findsNothing);
  });
  testWidgets('waiting page automatically picks up a new cached report', (
    tester,
  ) async {
    final state = _State()..report = null;
    await mount(tester, state);
    state.report = AdblockReport.parse(sample());
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(state.reads, 2);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Waiting for the first DNS report.'), findsNothing);
  });
  testWidgets('large text fits a small screen', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(tester, _State());
    expect(tester.takeException(), isNull);
  });
}
