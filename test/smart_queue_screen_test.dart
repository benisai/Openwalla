import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/screens/smart_queue_screen.dart';
import 'package:openwalla/services/sqm_wan_interfaces.dart';
import 'package:openwalla/state/app_state.dart';

class _SqmState extends ChangeNotifier implements AppState {
  List<SqmWanInterface> interfaces = const [
    SqmWanInterface(name: 'wan', device: 'eth1'),
    SqmWanInterface(name: 'wwan', device: 'phy0-sta0'),
  ];
  _SqmState({bool enabled = true})
    : queue = OpenwrtSqmQueue(
        section: 'queue',
        enabled: enabled,
        interfaceName: 'eth1',
        downloadKbps: 85000,
        uploadKbps: 10000,
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        debugLogging: true,
        verbosity: '7',
      );
  OpenwrtSqmQueue queue;
  OpenwrtSqmQueue? saved;
  bool failSave = false;
  int saves = 0;
  Completer<void>? gate;

  @override
  Future<OpenwrtFeatureStatus> getOpenwrtFeatureStatus(
    OpenwrtFeature feature, {
    bool forceRefresh = false,
    BuildContext? context,
  }) async => OpenwrtFeatureStatus(
    feature: feature,
    label: 'SQM',
    installed: true,
    checkedAt: DateTime.now(),
  );
  @override
  Future<List<OpenwrtSqmQueue>> fetchSqmQueues({BuildContext? context}) async =>
      [queue];
  @override
  Future<List<SqmWanInterface>> fetchSqmWanInterfaces({
    BuildContext? context,
  }) async => interfaces;
  @override
  Future<void> saveSqmQueue(OpenwrtSqmQueue next) async {
    saves++;
    if (gate != null) await gate!.future;
    if (failSave) throw StateError('SQM restart failed');
    saved = next;
    queue = next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> mount(WidgetTester tester, _SqmState state) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStateProvider.overrideWith((ref) => state)],
        child: const MaterialApp(home: SmartQueueScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'named WAN selection saves WWAN runtime device and preserves hidden diagnostics',
    (tester) async {
      final state = _SqmState();
      await mount(tester, state);
      expect(find.text('WAN'), findsWidgets);
      expect(find.text('eth1'), findsNothing);
      expect(find.text('Diagnostics'), findsNothing);
      expect(find.text('Debug Logging'), findsNothing);
      expect(find.text('Log Verbosity'), findsNothing);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>).first,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('WWAN').last);
      await tester.pumpAndSettle();
      state.interfaces = const [
        SqmWanInterface(name: 'wan', device: 'eth1'),
        SqmWanInterface(name: 'wwan', device: 'phy1-sta0'),
      ];
      await tester.ensureVisible(find.text('Save & Apply'));
      await tester.tap(find.text('Save & Apply'));
      await tester.pumpAndSettle();
      expect(state.saved?.interfaceName, 'phy1-sta0');
      expect(state.saved?.debugLogging, isTrue);
      expect(state.saved?.verbosity, '7');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save & Apply'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('no WAN devices means no fabricated eth1 choice or unsafe save', (
    tester,
  ) async {
    final state = _SqmState()..interfaces = [];
    await mount(tester, state);
    expect(find.text('No WAN interfaces found'), findsOneWidget);
    expect(find.text('eth1'), findsNothing);
    await tester.ensureVisible(find.text('Save & Apply'));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save & Apply'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 430.0, 1024.0]) {
    testWidgets('Smart Queue fits width $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await mount(tester, _SqmState());
      await tester.ensureVisible(find.text('Save & Apply'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'enable switch applies immediately and prevents duplicate saves',
    (tester) async {
      final state = _SqmState(enabled: false)..gate = Completer<void>();
      await mount(tester, state);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(state.saves, 1);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      state.gate!.complete();
      await tester.pumpAndSettle();
      expect(state.saved?.enabled, isTrue);
      expect(state.saved?.interfaceName, 'eth1');
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      expect(state.saves, 1);
    },
  );

  testWidgets('disable applies even if the old WAN device is unavailable', (
    tester,
  ) async {
    final state = _SqmState()..interfaces = [];
    await mount(tester, state);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(state.saved?.enabled, isFalse);
    expect(state.saved?.interfaceName, 'eth1');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets(
    'failed enable re-reads settings instead of leaving switch enabled',
    (tester) async {
      final state = _SqmState(enabled: false)..failSave = true;
      await mount(tester, state);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(state.saves, 1);
      expect(state.saved, isNull);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.text('Smart Queue enabled'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
