import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/flows_screen.dart';
import 'package:openwalla/state/app_state.dart';

class _FlowState extends ChangeNotifier implements AppState {
  final requests = <({int offset, int limit, String? protocol})>[];
  final int count;
  bool failNext = false;
  Completer<void>? pause;
  _FlowState(this.count);

  @override
  Map<String, dynamic> get dashboardData => {};
  @override
  Future<bool> hasNetifySupport({BuildContext? context}) async => true;
  @override
  Future<(Map<String, String>, Map<String, String>)> fetchDeviceNameMaps({
    bool aggregateAllRouters = false,
    BuildContext? context,
  }) async => (<String, String>{}, <String, String>{});
  @override
  Future<OpenwallaFlowSummary> fetchOpenwallaFlowSummary({
    String? protocolFilter,
    int? hoursBack,
    String? deviceMac,
    String? searchQuery,
    OpenwallaFlowProvider? provider,
    BuildContext? context,
  }) async => OpenwallaFlowSummary(
    provider: OpenwallaFlowProvider.netify,
    count: count,
  );

  @override
  Future<List<NetifyFlow>> fetchNetifyFlows({
    int limit = 50,
    int offset = 0,
    String? protocolFilter,
    String? deviceMac,
    String? searchQuery,
    int? hoursBack,
    BuildContext? context,
  }) async {
    requests.add((offset: offset, limit: limit, protocol: protocolFilter));
    final pending = pause;
    pause = null;
    if (pending != null) await pending.future;
    if (failNext) {
      failNext = false;
      throw StateError('Temporary connection failure');
    }
    return List.generate(max(0, min(limit, count - offset)), (index) {
      final id = offset + index;
      return NetifyFlow(
        timestamp: DateTime(2026, 10, 25, 22),
        deviceMac: '',
        localIp: '192.168.1.2',
        localPort: '$id',
        destination: 'flow-$id.example',
        application: 'HTTPS',
        protocol: 'HTTPS',
        destinationIp: '1.1.1.1',
        destinationPort: '443',
        interfaceName: 'wan',
        downloadedBytes: 1,
        uploadedBytes: 1,
        totalBytes: 2,
        countryCode: '',
        region: '',
        direction: 'Outbound',
        rawJson: '{"id":$id}',
      );
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, _FlowState state) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStateProvider.overrideWith((ref) => state)],
      child: const MaterialApp(home: FlowsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> bottom(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads another 2000 at the bottom, then the remaining rows', (
    tester,
  ) async {
    final state = _FlowState(4250);
    await _mount(tester, state);
    expect(
      state.requests.map((r) => r.offset),
      orderedEquals(List.generate(8, (i) => i * 250)),
    );
    await bottom(tester);
    expect(state.requests.last.offset, 3750);
    expect(state.requests.length, 16);
    await bottom(tester);
    expect(
      state.requests.map((r) => r.offset),
      orderedEquals(List.generate(18, (i) => i * 250)),
    );
    await bottom(tester);
    expect(find.textContaining('Loaded 4250 of 4250 flows'), findsOneWidget);
    expect(state.requests.length, 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed page retries without losing rows or advancing offset', (
    tester,
  ) async {
    final state = _FlowState(2200);
    await _mount(tester, state);
    state.failNext = true;
    await bottom(tester);
    expect(find.text('Retry loading flows'), findsOneWidget);
    expect(state.requests.last.offset, 2000);
    await tester.ensureVisible(find.text('Retry loading flows'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry loading flows'));
    await tester.pumpAndSettle();
    expect(state.requests.last.offset, 2000);
    await bottom(tester);
    expect(find.textContaining('Loaded 2200 of 2200 flows'), findsOneWidget);
  });

  testWidgets('ignores an old page when a filter replaces the list', (
    tester,
  ) async {
    final state = _FlowState(2200);
    await _mount(tester, state);
    final pending = Completer<void>();
    state.pause = pending;
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    expect(state.requests.last.offset, 2000);
    scrollable.position.jumpTo(0);
    await tester.pump();
    await tester.tap(find.text('HTTPS'));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    await bottom(tester);
    expect(state.requests.last.offset, 2000);
    expect(state.requests.last.protocol, 'HTTPS');
    expect(tester.takeException(), isNull);
  });
}
