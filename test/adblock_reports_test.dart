import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/models/adblock_report.dart';
import 'package:openwalla/screens/adblock_reports_screen.dart';
import 'package:openwalla/state/app_state.dart';

String sample({String search = ''}) => search.isEmpty
    ? 'S|20|20|1|100|1794592800\nR|5|100|192.168.1.20|aa:bb:cc:dd:ee:ff|Pixel|ads.example.com|A|example.com\nR|4|99|192.168.1.30|||ads.other.net|AAAA|other.net'
    : search == 'nothing'
    ? 'S|20|0|1|100|1794592800'
    : 'S|20|1|1|100|1794592800\nR|4|99|192.168.1.30|||ads.other.net|AAAA|other.net';

class _State extends ChangeNotifier implements AppState {
  bool fail = false;
  bool empty = false;
  bool paginate = false;
  int reads = 0;
  final cursors = <int?>[];
  Completer<AdblockReport?>? gate;
  @override
  Future<AdblockReport?> fetchAdblockReport({
    String search = '',
    int? beforeId,
    int limit = 200,
  }) async {
    reads++;
    cursors.add(beforeId);
    if (fail) throw StateError('Disconnected');
    if (gate != null) return gate!.future;
    if (empty) return AdblockReport.parse('S|0|0|0|0|0');
    if (paginate && beforeId == null) {
      return AdblockReport.parse(sample(), limit: 1);
    }
    if (paginate && beforeId != null) {
      return AdblockReport.parse(
        'S|20|20|1|100|1794592800\nR|4|99|192.168.1.30|||ads.other.net|AAAA|other.net',
      );
    }
    return AdblockReport.parse(sample(search: search));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('parses database identities and paginated results', () {
    final report = AdblockReport.parse(sample(), limit: 1);
    expect(report.total, 20);
    expect(report.hasMore, isTrue);
    expect(report.nextId, 5);
    expect(report.requests.single.deviceLabel, 'Pixel');
    expect(report.requests.single.matchedRule, 'example.com');
    expect(
      AdblockReport.parse(sample()).requests.last.deviceLabel,
      '192.168.1.30',
    );
  });
  test('rejects malformed responses rather than reporting zero traffic', () {
    for (final value in [
      'broken',
      '{}',
      'S|invalid|0|0|0|0',
      'S|1|1|0|0|0\nR|1',
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

  testWidgets('renders device identity and debounces server-side search', (
    tester,
  ) async {
    final state = _State();
    await mount(tester, state);
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.textContaining('Pixel'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.1.30');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsNothing);
    expect(find.text('ads.other.net'), findsOneWidget);
    expect(state.reads, 2);
    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('No matching queries'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsOneWidget);
  });
  testWidgets('failed refresh retains the rows and reports an error', (
    tester,
  ) async {
    final state = _State();
    await mount(tester, state);
    state.fail = true;
    await tester.tap(find.byTooltip('Refresh reports'));
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.textContaining('Could not read reports.'), findsOneWidget);
  });
  testWidgets(
    'empty database is distinct from a failure and polls for new rows',
    (tester) async {
      final state = _State()..empty = true;
      await mount(tester, state);
      expect(find.text('No blocked DNS queries recorded yet.'), findsOneWidget);
      state.empty = false;
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(state.reads, 2);
      expect(find.text('ads.example.com'), findsOneWidget);
    },
  );
  testWidgets('loads another page using the last database ID', (tester) async {
    final state = _State()..paginate = true;
    await mount(tester, state);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(state.cursors, [null, 5]);
    expect(find.text('ads.other.net'), findsOneWidget);
    expect(find.text('ads.example.com'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });
  testWidgets('stale response cannot overwrite a newer search', (tester) async {
    final state = _State();
    await mount(tester, state);
    state.gate = Completer<AdblockReport?>();
    await tester.tap(find.byTooltip('Refresh reports'));
    await tester.pump();
    final old = state.gate!;
    state.gate = null;
    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    old.complete(AdblockReport.parse(sample()));
    await tester.pumpAndSettle();
    expect(find.text('ads.example.com'), findsNothing);
    expect(find.text('No matching queries'), findsOneWidget);
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
